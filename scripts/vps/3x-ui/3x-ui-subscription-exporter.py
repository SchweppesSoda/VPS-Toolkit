#!/usr/bin/env python3
"""Transient, bounded 3x-ui subscription producer. No remote files are created.

Execute this reviewed source with CONFIG set to a separate parsed JSON object,
or run it locally with a JSON configuration on stdin. Requires Python 3.9+.
The existing interactive/ZIP exporter deliberately keeps its recovery behavior.
"""
import base64
import hashlib
import json
import pathlib
import re
import signal
import sqlite3
import ssl
import sys
import time
import urllib.parse
import urllib.request

VERSION = "1.0.0"
MAX_LINKS = 1024 * 1024
MAX_ENVELOPE = 2 * MAX_LINKS
MAX_NODES = 1000
MAX_LINE = 16384


class ExportError(Exception):
    pass


def require(ok, category):
    if not ok:
        raise ExportError(category)


def node_identity(line):
    require(isinstance(line, str) and 0 < len(line.encode()) <= MAX_LINE, "format")
    require(not any(ord(c) <= 32 or ord(c) == 127 for c in line), "format")
    u = urllib.parse.urlsplit(line)
    # Fail closed on unsupported protocols instead of guessing client identity.
    require(u.scheme in {"vless", "trojan", "vmess"}, "format")
    if u.scheme == "vmess":
        try:
            d = json.loads(base64.b64decode(u.netloc + "=" * (-len(u.netloc) % 4), validate=True))
            host, port, identity = d["add"], int(d["port"]), d["id"]
        except Exception:
            raise ExportError("format") from None
    else:
        host, port, identity = u.hostname, u.port, urllib.parse.unquote(u.username or "")
    require(bool(host) and isinstance(port, int) and 0 < port <= 65535 and bool(identity), "format")
    require(host not in {"localhost", "127.0.0.1", "::1", "0.0.0.0", "::"}, "format")
    return identity


def normalize(raw):
    require(len(raw) <= MAX_LINKS, "limit")
    raw = raw.strip()
    if b"://" not in raw:
        try:
            raw = base64.b64decode(b"".join(raw.split()), validate=True)
        except Exception:
            raise ExportError("format") from None
    try:
        lines = raw.decode("utf-8").splitlines()
    except UnicodeError:
        raise ExportError("format") from None
    require(0 < len(lines) <= MAX_NODES, "limit")
    for line in lines:
        node_identity(line)
    lines = list(dict.fromkeys(lines))
    links = "\n".join(lines) + "\n"
    require(len(links.encode()) <= MAX_LINKS, "limit")
    return lines


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ExportError("fetch")


def local_fetch(port, path, host, tls):
    # Endpoint is fixed to loopback; never follow panel redirects or env proxies.
    # Trust is the existing local host boundary, not an Internet TLS endpoint.
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect(),
                                        urllib.request.HTTPSHandler(context=context))
    request = urllib.request.Request(
        f'{"https" if tls else "http"}://127.0.0.1:{port}{path}',
        headers={"Host": host, "Accept": "text/plain", "User-Agent": "3x-ui-transient-export/" + VERSION})
    try:
        with opener.open(request, timeout=10) as response:
            require(response.status == 200, "fetch")
            data = response.read(MAX_LINKS + 1)
        return normalize(data)
    except ExportError:
        raise
    except Exception:
        raise ExportError("fetch") from None


def export(config, fetch=local_fetch):
    require(isinstance(config, dict), "config")
    identities = config.get("clientIds")
    host = config.get("address", "")
    require(isinstance(identities, list) and 0 < len(identities) <= MAX_NODES, "config")
    require(all(isinstance(x, str) and 0 < len(x) < 256 for x in identities), "config")
    require(isinstance(host, str) and re.fullmatch(r"[A-Za-z0-9.:-]{1,253}", host), "config")
    wanted = set(identities)
    database = pathlib.Path(config.get("database", "/etc/x-ui/x-ui.db"))
    require(database.is_absolute() and database.is_file(), "database")
    db = sqlite3.connect(":memory:")
    try:
        src = sqlite3.connect(database.as_uri() + "?mode=ro", uri=True, timeout=5)
        try:
            src.backup(db, pages=256)
        finally:
            src.close()
        db.row_factory = sqlite3.Row
        settings = dict(db.execute("SELECT key,value FROM settings"))
        require(settings.get("subEnable") == "true", "config")
        port = int(settings.get("subPort", "2096"))
        path = "/" + settings.get("subPath", "/sub/").strip("/") + "/"
        require(0 < port <= 65535 and not any(c in path for c in "?#\r\n"), "config")
        rows = list(db.execute("SELECT * FROM inbounds ORDER BY id"))
        groups = {}
        all_members = {}
        now = int(time.time() * 1000)
        for row in rows:
            if not row["enable"]:
                continue
            clients = json.loads(row["settings"]).get("clients", [])
            for client in clients:
                identity = client.get("id") or client.get("password")
                if not client.get("enable", True) or 0 < client.get("expiryTime", 0) <= now:
                    continue
                sid = client.get("subId")
                if sid:
                    all_members.setdefault(sid, set()).add(identity)
                if identity not in wanted:
                    continue
                require(row["protocol"] in {"vless", "vmess", "trojan"}, "selection")
                require(isinstance(sid, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,256}", sid), "selection")
                groups.setdefault(sid, []).append(identity)
        require(bool(groups), "selection")
        lines = []
        for sid, expected in groups.items():
            require(all_members[sid] <= wanted, "selection")
            result = fetch(port, path + urllib.parse.quote(sid, safe=""), host, bool(settings.get("subCertFile")))
            # One native renderer URI per selected active inbound-client pair.
            require(sorted(node_identity(line) for line in result) == sorted(expected), "selection")
            lines.extend(result)
        lines = list(dict.fromkeys(lines))
        links = "\n".join(lines) + "\n"
        normalize(links.encode())
        return {"schemaVersion": 1, "exporterVersion": VERSION,
                "exportedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "expectedGroups": len(groups), "successfulGroups": len(groups),
                "nodeCount": len(lines), "bytes": len(links.encode()),
                "sha256": hashlib.sha256(links.encode()).hexdigest(), "links": links}
    except ExportError:
        raise
    except Exception:
        raise ExportError("database") from None
    finally:
        db.close()


def main(config=None):
    try:
        if hasattr(signal, "alarm"):
            def timeout(*_):
                raise ExportError("timeout")
            signal.signal(signal.SIGALRM, timeout)
            signal.alarm(120)
        if config is None:
            raw = sys.stdin.buffer.read(65537)
            require(len(raw) <= 65536, "config")
            config = json.loads(raw)
        result = json.dumps(export(config), ensure_ascii=False) + "\n"
        require(len(result.encode()) <= MAX_ENVELOPE, "limit")
        sys.stdout.write(result)
        return 0
    except Exception as exc:
        category = str(exc) if isinstance(exc, ExportError) else "config"
        sys.stderr.write("3XUI_EXPORT_ERROR " + category + "\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main(globals().get("CONFIG")))
