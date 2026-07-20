#!/usr/bin/env python3
"""Loopback-only HTTP receiver for the optional Stash -> SSH -> PO0 PoC."""

from __future__ import annotations

import hmac
import ipaddress
import json
import os
import re
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "2026.07.20+build.1"
LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 8790
PATH = "/stash-report/v1"
MAX_BODY = 8192
MAX_CLOCK_SKEW = 600
REPLAY_TTL = 600
SOURCE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
REQUEST_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$")
_seen: dict[str, float] = {}
_seen_lock = threading.Lock()


def env_required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"missing environment variable: {name}")
    return value


def prune_and_claim(request_id: str, now: float) -> bool:
    with _seen_lock:
        for key, stamp in list(_seen.items()):
            if now - stamp > REPLAY_TTL:
                _seen.pop(key, None)
        if request_id in _seen:
            return False
        _seen[request_id] = now
        return True


class Handler(BaseHTTPRequestHandler):
    server_version = "PO0StashLoopback/" + VERSION

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"[stash-loopback] {self.client_address[0]} {fmt % args}", flush=True)

    def send_json(self, status: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path.rstrip("/") == "/health":
            self.send_json(200, {"ok": True, "version": VERSION, "listen": "loopback"})
        else:
            self.send_json(404, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path.rstrip("/") != PATH:
            self.send_json(404, {"ok": False, "error": "not found"})
            return
        try:
            expected = env_required("PO0_STASH_RECEIVER_SECRET")
            supplied = self.headers.get("Authorization", "")
            if not supplied.startswith("Bearer ") or not hmac.compare_digest(supplied[7:], expected):
                self.send_json(401, {"ok": False, "error": "unauthorized"})
                return
            length = int(self.headers.get("Content-Length", "0"))
            if length < 2 or length > MAX_BODY:
                self.send_json(413, {"ok": False, "error": "invalid body size"})
                return
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict):
                raise ValueError("JSON body must be an object")
            source_id = str(data.get("source_id", ""))
            request_id = str(data.get("request_id", ""))
            network = str(data.get("network", "unknown")).lower()
            observed_at = int(data.get("observed_at", 0))
            address = ipaddress.ip_address(str(data.get("ip", "")))
            now = int(time.time())
            if not SOURCE_RE.fullmatch(source_id):
                raise ValueError("invalid source_id")
            if not REQUEST_RE.fullmatch(request_id):
                raise ValueError("invalid request_id")
            if address.version != 4 or not address.is_global:
                raise ValueError("ip must be a public IPv4")
            if network not in {"wifi", "cellular", "unknown"}:
                raise ValueError("network must be wifi, cellular, or unknown")
            if abs(now - observed_at) > MAX_CLOCK_SKEW:
                raise ValueError("observed_at outside allowed clock skew")
            if not prune_and_claim(request_id, now):
                self.send_json(409, {"ok": False, "error": "duplicate request_id"})
                return
            prefix = 24 if network == "cellular" else 32
            cidr = str(ipaddress.ip_network(f"{address}/{prefix}", strict=False))
            token = env_required("PO0_STASH_REPORT_TOKEN")
            manager = os.environ.get("PO0_MANAGER", "/root/nftables-relay-manager.sh")
            identity = os.environ.get("PO0_STASH_REPORT_IDENTITY", "stash-ssh-poc")
            ttl = int(os.environ.get("PO0_STASH_REPORT_TTL", "43200"))
            if ttl < 60 or ttl > 604800:
                raise ValueError("PO0_STASH_REPORT_TTL must be 60..604800")
            command = ["bash", manager, "--ssh-ip-report", source_id, str(address), token, identity, str(ttl), str(prefix)]
            completed = subprocess.run(command, text=True, capture_output=True, timeout=20, check=False)
            if completed.returncode != 0:
                detail = (completed.stderr or completed.stdout or "manager failed").strip().splitlines()[-1][:240]
                self.send_json(502, {"ok": False, "error": detail})
                return
            self.send_json(200, {"ok": True, "source_id": source_id, "accepted_cidr": cidr, "accepted_at": now, "expires_at": now + ttl, "targets": ["local-po0"]})
        except (ValueError, TypeError, json.JSONDecodeError) as exc:
            self.send_json(400, {"ok": False, "error": str(exc)})
        except subprocess.TimeoutExpired:
            self.send_json(504, {"ok": False, "error": "manager timeout"})
        except RuntimeError as exc:
            self.send_json(503, {"ok": False, "error": str(exc)})
        except Exception as exc:
            print(f"[stash-loopback] internal error: {type(exc).__name__}: {exc}", flush=True)
            self.send_json(500, {"ok": False, "error": "internal error"})


def main() -> None:
    env_required("PO0_STASH_RECEIVER_SECRET")
    env_required("PO0_STASH_REPORT_TOKEN")
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    print(f"PO0 Stash loopback receiver {VERSION} listening on {LISTEN_HOST}:{LISTEN_PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
