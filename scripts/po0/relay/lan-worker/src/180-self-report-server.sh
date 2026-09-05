run_self_report_server() {
    local py listen_host listen_port targets
    targets="$(self_report_targets_env)" || return 1
    [[ -n "${targets}" ]] || { printf 'missing Self-report PO0 target. Configure --po0-host/--client-ip-token or 设备自上报目标。\n' >&2; return 1; }
    if have_cmd python3; then
        py="python3"
    elif have_cmd python; then
        py="python"
    else
        printf 'missing python3/python; cannot run self-report server.\n' >&2
        return 1
    fi
    listen_host="${SELF_REPORT_LISTEN%:*}"
    listen_port="${SELF_REPORT_LISTEN##*:}"
    [[ -n "${listen_host}" && "${listen_host}" != "${SELF_REPORT_LISTEN}" ]] || listen_host="127.0.0.1"
    [[ "${listen_port}" =~ ^[0-9]+$ ]] || listen_port="8788"
    official_prepare_python_preflight_env
    export PO0_SELF_REPORT_TARGETS="${targets}" SELF_REPORT_SECRET
    printf 'Self-report server listening on %s:%s; device -> LAN Worker -> SSH -> PO0.\n' "${listen_host}" "${listen_port}"
    env -u PO0_FIREWALL_TOKENS "${py}" - "${listen_host}" "${listen_port}" <<'PY'
import concurrent.futures
import datetime
import errno
import hmac
import http.server
import ipaddress
import json
import math
import os
import re
import shlex
import shutil
import socketserver
import subprocess
import sys
import threading
import time
import urllib.parse

listen_host, listen_port = sys.argv[1], int(sys.argv[2])
SSH_BIN = shutil.which("ssh") or "ssh"
OFFICIAL_CLIENT = os.environ.get("PO0_LAN_CLIENT_PATH", "")
OFFICIAL_CONFIG = os.environ.get("PO0_LAN_CLIENT_CONFIG_FILE", "")
OFFICIAL_SETTINGS = os.environ.get("PO0_LAN_CLIENT_SETTINGS_FILE", "")
BASH_BIN = shutil.which("bash") or "bash"
DISCONNECT_ERRNOS = {errno.EPIPE}
if hasattr(errno, "ECONNRESET"):
    DISCONNECT_ERRNOS.add(errno.ECONNRESET)

def send_text(handler, status, body, content_type="text/plain; charset=utf-8"):
    if isinstance(body, str):
        body = body.encode("utf-8")
    try:
        handler.send_response(status)
        if content_type:
            handler.send_header("Content-Type", content_type)
        handler.end_headers()
        handler.wfile.write(body)
        return True
    except (BrokenPipeError, ConnectionResetError) as exc:
        print(f"[WARN] client disconnected before response was written: {exc}", file=sys.stderr)
        return False
    except OSError as exc:
        if getattr(exc, "errno", None) in DISCONNECT_ERRNOS or getattr(exc, "winerror", None) in (10053, 10054):
            print(f"[WARN] client disconnected before response was written: {exc}", file=sys.stderr)
            return False
        raise

def send_json(handler, status, payload, extra_headers=None):
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    try:
        handler.send_response(status)
        handler.send_header("Content-Type", "application/json; charset=utf-8")
        handler.send_header("Content-Length", str(len(body)))
        handler.send_header("Cache-Control", "no-store")
        for name, value in (extra_headers or {}).items():
            handler.send_header(name, value)
        handler.end_headers()
        handler.wfile.write(body)
        return True
    except (BrokenPipeError, ConnectionResetError) as exc:
        print(f"[WARN] client disconnected before JSON response was written: {exc}", file=sys.stderr)
        return False
    except OSError as exc:
        if getattr(exc, "errno", None) in DISCONNECT_ERRNOS or getattr(exc, "winerror", None) in (10053, 10054):
            print(f"[WARN] client disconnected before JSON response was written: {exc}", file=sys.stderr)
            return False
        raise

def is_public_ipv4(ip):
    m = re.match(r"^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$", ip or "")
    if not m:
        return False
    o = [int(x) for x in m.groups()]
    if any(x < 0 or x > 255 for x in o):
        return False
    if o[0] in (0, 10, 127) or o[0] >= 224:
        return False
    if o[0] == 100 and 64 <= o[1] <= 127:
        return False
    if o[0] == 169 and o[1] == 254:
        return False
    if o[0] == 172 and 16 <= o[1] <= 31:
        return False
    if o[0] == 192 and o[1] == 168:
        return False
    if o[0] == 198 and 18 <= o[1] <= 19:
        return False
    return True

def first(values, default=""):
    for value in values:
        if value:
            return value
    return default

def bearer(auth):
    if not auth:
        return ""
    parts = auth.split(None, 1)
    if len(parts) == 2 and parts[0].lower() == "bearer":
        return parts[1].strip()
    return ""

def parse_request(handler):
    parsed = urllib.parse.urlparse(handler.path)
    params = {k: v[-1] for k, v in urllib.parse.parse_qs(parsed.query).items()}
    if handler.command == "POST":
        length = int(handler.headers.get("Content-Length") or "0")
        if length:
            body = handler.rfile.read(length).decode("utf-8", "replace")
            params.update({k: v[-1] for k, v in urllib.parse.parse_qs(body).items()})
    return parsed.path, params

def parse_json_request(handler, max_bytes=16384):
    content_type = (handler.headers.get("Content-Type") or "").split(";", 1)[0].strip().lower()
    if content_type != "application/json":
        raise ValueError("content-type must be application/json")
    raw_length = handler.headers.get("Content-Length") or ""
    if not raw_length.isdigit():
        raise ValueError("content-length is required")
    length = int(raw_length)
    if length <= 0 or length > max_bytes:
        raise ValueError("invalid content-length")
    try:
        payload = json.loads(handler.rfile.read(length).decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("invalid JSON body") from exc
    if not isinstance(payload, dict):
        raise ValueError("JSON body must be an object")
    return payload

def parse_targets(raw):
    targets = []
    for line in (raw or "").replace(";", "\n").splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = [part.strip() for part in line.split('|')]
        while len(parts) < 8:
            parts.append('')
        source, host, port, user, script, token, ttl, extra = parts[:8]
        if not host or not token:
            continue
        targets.append({
            'source': source or 'self-report',
            'host': host,
            'port': port or '22',
            'user': user or 'root',
            'script': script or '/root/nftables-relay-manager.sh',
            'token': token,
            'ttl': ttl or '43200',
            'extra': extra,
        })
    return targets

def normalized_ttl(value, fallback=43200):
    try:
        ttl = int(value or fallback)
    except ValueError:
        ttl = fallback
    return min(max(60, ttl), 604800)

def safe_report_token(value, fallback="self-report"):
    raw = (value or "").strip().lower()
    out = []
    last_dash = False
    for ch in raw:
        if ord(ch) < 128 and (ch.isalnum() or ch in "._-"):
            out.append(ch)
            last_dash = False
        else:
            if not last_dash:
                out.append("-")
                last_dash = True
    safe = "".join(out).strip("-")
    if not safe:
        safe = fallback
    return safe[:48].rstrip("-") or fallback

SOURCE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,47}$")
REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
STASH_REQUEST_MAX_DRIFT_SECONDS = 600
STASH_REQUEST_ID_TTL_SECONDS = 600
SEEN_STASH_REQUEST_IDS = {}
SEEN_STASH_REQUEST_IDS_LOCK = threading.Lock()

def valid_source_id(value):
    return isinstance(value, str) and SOURCE_ID_RE.fullmatch(value) is not None

def valid_request_id(value):
    return isinstance(value, str) and REQUEST_ID_RE.fullmatch(value) is not None

def parse_observed_at(value):
    if isinstance(value, bool):
        raise ValueError("observed_at must be a Unix timestamp or ISO-8601 time")
    if isinstance(value, (int, float)):
        timestamp = float(value)
        if not math.isfinite(timestamp):
            raise ValueError("observed_at must be finite")
        return timestamp
    if not isinstance(value, str) or not value.strip():
        raise ValueError("observed_at must be a Unix timestamp or ISO-8601 time")
    text = value.strip()
    try:
        timestamp = float(text)
        if not math.isfinite(timestamp):
            raise ValueError("observed_at must be finite")
        return timestamp
    except ValueError:
        pass
    iso_text = text[:-1] + "+00:00" if text.endswith(("Z", "z")) else text
    try:
        parsed = datetime.datetime.fromisoformat(iso_text)
    except (AttributeError, ValueError):
        parsed = None
        for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ"):
            try:
                parsed = datetime.datetime.strptime(text, fmt).replace(tzinfo=datetime.timezone.utc)
                break
            except ValueError:
                continue
        if parsed is None:
            raise ValueError("observed_at must be a Unix timestamp or ISO-8601 time")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=datetime.timezone.utc)
    return parsed.timestamp()

def utc_iso(timestamp):
    return datetime.datetime.fromtimestamp(timestamp, datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

def remember_stash_request_id(request_id, now):
    cutoff = now - STASH_REQUEST_ID_TTL_SECONDS
    with SEEN_STASH_REQUEST_IDS_LOCK:
        for old_request_id, seen_at in list(SEEN_STASH_REQUEST_IDS.items()):
            if seen_at < cutoff:
                del SEEN_STASH_REQUEST_IDS[old_request_id]
        if request_id in SEEN_STASH_REQUEST_IDS:
            return False
        SEEN_STASH_REQUEST_IDS[request_id] = now
        return True

def warn_ignored_extra(context, reason):
    print(f"[WARN] {context}: ignored SSH extra arg ({reason}).", file=sys.stderr)

def sanitized_extra_args(extra, context):
    out = []
    has_batchmode = False
    has_connect_timeout = False
    has_strict_host = False
    has_connection_attempts = False
    has_number_prompts = False
    has_preferred_auth = False
    has_password_auth = False
    has_kbd_auth = False
    has_gssapi = False
    private_key_words = False
    private_key_warned = False
    connect_timeout = os.environ.get("PO0_SSH_CONNECT_TIMEOUT_SECONDS", "15") or "15"
    try:
        parts = shlex.split(extra or "")
    except ValueError as exc:
        warn_ignored_extra(context, f"parse error: {exc}")
        parts = []
    options_with_value = {
        "-B", "-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L",
        "-l", "-m", "-O", "-o", "-P", "-Q", "-R", "-S", "-W", "-w",
    }
    option_assignments = (
        "IdentityFile=", "BatchMode=", "StrictHostKeyChecking=",
        "UserKnownHostsFile=", "HostKeyAlias=", "ProxyJump=", "ProxyCommand=",
        "ConnectTimeout=", "ConnectionAttempts=", "NumberOfPasswordPrompts=",
        "PreferredAuthentications=", "PasswordAuthentication=",
        "KbdInteractiveAuthentication=", "GSSAPIAuthentication=",
    )
    i = 0
    while i < len(parts):
        token = parts[i]
        next_token = parts[i + 1] if i + 1 < len(parts) else ""
        if private_key_words and (
            token in ("OPENSSH", "RSA", "DSA", "EC", "ECDSA", "ED25519", "PRIVATE", "KEY", "KEY-----")
            or token.endswith("KEY-----")
            or token.startswith("-----END")
        ):
            if token.endswith("KEY-----") or token.startswith("-----END"):
                private_key_words = False
            i += 1
        elif token.startswith("-----BEGIN") or token.startswith("-----END"):
            if not private_key_warned:
                warn_ignored_extra(context, "private key text is not an SSH option; save it to a file and use -i /path/key")
                private_key_warned = True
            private_key_words = True
            if token.endswith("KEY-----") or token.startswith("-----END"):
                private_key_words = False
            i += 1
        elif token == "-" or token.startswith("--"):
            warn_ignored_extra(context, "invalid option/private-key marker")
            i += 1
        elif token == "-p":
            warn_ignored_extra(context, "port belongs in the PO0 SSH port field")
            i += 2 if next_token and not next_token.startswith("-") else 1
        elif token.startswith("-p"):
            warn_ignored_extra(context, "port belongs in the PO0 SSH port field")
            i += 1
        elif token.startswith(option_assignments):
            if token.startswith("BatchMode="):
                has_batchmode = True
            elif token.startswith("ConnectTimeout="):
                has_connect_timeout = True
            elif token.startswith("StrictHostKeyChecking="):
                has_strict_host = True
            elif token.startswith("ConnectionAttempts="):
                has_connection_attempts = True
            elif token.startswith("NumberOfPasswordPrompts="):
                has_number_prompts = True
            elif token.startswith("PreferredAuthentications="):
                has_preferred_auth = True
            elif token.startswith("PasswordAuthentication="):
                has_password_auth = True
            elif token.startswith("KbdInteractiveAuthentication="):
                has_kbd_auth = True
            elif token.startswith("GSSAPIAuthentication="):
                has_gssapi = True
            out.extend(["-o", token])
            i += 1
        elif token in options_with_value:
            if not next_token or next_token.startswith("-"):
                warn_ignored_extra(context, f"missing value for {token}")
                i += 1
            else:
                if token == "-o":
                    if next_token.startswith("BatchMode="):
                        has_batchmode = True
                    elif next_token.startswith("ConnectTimeout="):
                        has_connect_timeout = True
                    elif next_token.startswith("StrictHostKeyChecking="):
                        has_strict_host = True
                    elif next_token.startswith("ConnectionAttempts="):
                        has_connection_attempts = True
                    elif next_token.startswith("NumberOfPasswordPrompts="):
                        has_number_prompts = True
                    elif next_token.startswith("PreferredAuthentications="):
                        has_preferred_auth = True
                    elif next_token.startswith("PasswordAuthentication="):
                        has_password_auth = True
                    elif next_token.startswith("KbdInteractiveAuthentication="):
                        has_kbd_auth = True
                    elif next_token.startswith("GSSAPIAuthentication="):
                        has_gssapi = True
                out.extend([token, next_token])
                i += 2
        elif token.startswith("-"):
            if token.startswith("-oBatchMode="):
                has_batchmode = True
            elif token.startswith("-oConnectTimeout="):
                has_connect_timeout = True
            elif token.startswith("-oStrictHostKeyChecking="):
                has_strict_host = True
            elif token.startswith("-oConnectionAttempts="):
                has_connection_attempts = True
            elif token.startswith("-oNumberOfPasswordPrompts="):
                has_number_prompts = True
            elif token.startswith("-oPreferredAuthentications="):
                has_preferred_auth = True
            elif token.startswith("-oPasswordAuthentication="):
                has_password_auth = True
            elif token.startswith("-oKbdInteractiveAuthentication="):
                has_kbd_auth = True
            elif token.startswith("-oGSSAPIAuthentication="):
                has_gssapi = True
            out.append(token)
            i += 1
        else:
            warn_ignored_extra(context, "bare value without an SSH option")
            i += 1
    if not has_batchmode:
        out.extend(["-o", "BatchMode=yes"])
    if not has_connect_timeout:
        out.extend(["-o", f"ConnectTimeout={connect_timeout}"])
    if not has_strict_host:
        out.extend(["-o", "StrictHostKeyChecking=accept-new"])
    if not has_connection_attempts:
        out.extend(["-o", "ConnectionAttempts=1"])
    if not has_number_prompts:
        out.extend(["-o", "NumberOfPasswordPrompts=0"])
    if not has_preferred_auth:
        out.extend(["-o", "PreferredAuthentications=publickey"])
    if not has_password_auth:
        out.extend(["-o", "PasswordAuthentication=no"])
    if not has_kbd_auth:
        out.extend(["-o", "KbdInteractiveAuthentication=no"])
    if not has_gssapi:
        out.extend(["-o", "GSSAPIAuthentication=no"])
    return out

TARGETS = parse_targets(os.environ.get('PO0_SELF_REPORT_TARGETS', ''))
if not TARGETS:
    raise SystemExit('missing PO0_SELF_REPORT_TARGETS')

def official_preflight():
    if not OFFICIAL_CLIENT or not OFFICIAL_CONFIG or not OFFICIAL_SETTINGS:
        return False
    command = [
        BASH_BIN,
        OFFICIAL_CLIENT,
        "--config", OFFICIAL_CONFIG,
        "--settings-file", OFFICIAL_SETTINGS,
        "--official-preflight-only",
    ]
    child_env = os.environ.copy()
    child_env.pop("PO0_FIREWALL_TOKENS", None)
    try:
        result = subprocess.run(
            command,
            env=child_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=40,
        )
        return result.returncode == 0
    except Exception:
        return False

def target_label(target, source_override):
    port = target.get('port') or '22'
    port_suffix = "" if port == "22" else f":{port}"
    return f"{safe_report_token(source_override or target['source'], 'self-report')}@{target['host']}{port_suffix}"

def report_target(target, ip, identity, source_override, cidr_prefix=None):
    source = safe_report_token(source_override or target['source'], "self-report")
    identity = safe_report_token(identity or "self-report", source)
    ttl = str(normalized_ttl(target.get('ttl'), 43200))
    remote_parts = [
        "bash",
        shlex.quote(target['script']),
        "--client-ip-report",
        shlex.quote(source),
        shlex.quote(ip),
        shlex.quote(target['token']),
        shlex.quote(identity or "self-report"),
        shlex.quote(ttl),
    ]
    if cidr_prefix is not None:
        remote_parts.append(shlex.quote(str(cidr_prefix)))
    remote = " ".join(remote_parts)
    cmd = [SSH_BIN, "-p", target['port']]
    cmd.extend(sanitized_extra_args(target.get('extra', ''), f"Self-report {target['user']}@{target['host']}:{target['port']}"))
    cmd.extend([f"{target['user']}@{target['host']}", remote])
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)

def report_one(target, ip, identity, source_override, cidr_prefix=None):
    label = target_label(target, source_override)
    try:
        result = report_target(target, ip, identity, source_override, cidr_prefix)
    except subprocess.TimeoutExpired as exc:
        return label, False, f"timeout after {exc.timeout}s"
    except Exception as exc:
        return label, False, str(exc)
    if result.returncode == 0:
        return label, True, ""
    return label, False, str(result.stderr or result.stdout or result.returncode).strip()

def report_all(ip, identity, source_override, cidr_prefix=None):
    # Do the optional host-local report first; failures never change the
    # legacy self-report HTTP result.
    official_preflight()
    ok = []
    failed = []
    max_workers = min(len(TARGETS), 8)
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(report_one, target, ip, identity, source_override, cidr_prefix) for target in TARGETS]
        for future in futures:
            try:
                label, success, detail = future.result()
            except Exception as exc:
                failed.append(f"unknown-target: {exc}")
                continue
            if success:
                ok.append(label)
            else:
                failed.append(f"{label}: {detail}")
    return ok, failed

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if urllib.parse.urlparse(self.path).path in ("/stash-report/v1", "/stash-report/v1/"):
            send_json(self, 405, {"ok": False, "error": "method_not_allowed"}, {"Allow": "POST"})
            return
        self.handle_report()

    def do_POST(self):
        if urllib.parse.urlparse(self.path).path in ("/stash-report/v1", "/stash-report/v1/"):
            self.handle_stash_report()
            return
        self.handle_report()

    def handle_stash_report(self):
        secret = os.environ.get("SELF_REPORT_SECRET", "")
        if not secret:
            send_json(self, 503, {"ok": False, "error": "server_not_configured"})
            return
        supplied = bearer(self.headers.get("Authorization"))
        if not supplied or not hmac.compare_digest(supplied, secret):
            send_json(self, 401, {"ok": False, "error": "unauthorized"})
            return
        try:
            payload = parse_json_request(self)
        except ValueError as exc:
            send_json(self, 400, {"ok": False, "error": "invalid_request", "message": str(exc)})
            return

        source_id = payload.get("source_id")
        ip = payload.get("ip")
        network = payload.get("network")
        observed_at = payload.get("observed_at")
        request_id = payload.get("request_id")
        if not valid_source_id(source_id):
            send_json(self, 400, {"ok": False, "error": "invalid_source_id"})
            return
        if not isinstance(ip, str) or not is_public_ipv4(ip):
            send_json(self, 400, {"ok": False, "error": "invalid_public_ipv4"})
            return
        if not isinstance(network, str) or network.strip().lower() not in ("cellular", "wifi", "unknown"):
            send_json(self, 400, {"ok": False, "error": "invalid_network"})
            return
        network = network.strip().lower()
        if not valid_request_id(request_id):
            send_json(self, 400, {"ok": False, "error": "invalid_request_id"})
            return
        try:
            observed_timestamp = parse_observed_at(observed_at)
        except ValueError as exc:
            send_json(self, 400, {"ok": False, "error": "invalid_observed_at", "message": str(exc)})
            return
        now = time.time()
        if abs(now - observed_timestamp) > STASH_REQUEST_MAX_DRIFT_SECONDS:
            send_json(self, 400, {"ok": False, "error": "stale_observation"})
            return
        if not remember_stash_request_id(request_id, now):
            send_json(self, 409, {"ok": False, "error": "duplicate_request", "request_id": request_id})
            return

        cidr_prefix = 32
        accepted_cidr = ipaddress.ip_network(f"{ip}/{cidr_prefix}", strict=False).with_prefixlen
        ttl_seconds = min(normalized_ttl(target.get("ttl"), 43200) for target in TARGETS)
        target_names = [target_label(target, source_id) for target in TARGETS]
        accepted_at = utc_iso(now)
        expires_at = utc_iso(now + ttl_seconds)
        try:
            ok, failed = report_all(ip, source_id, source_id, cidr_prefix)
        except Exception as exc:
            print(f"[WARN] Stash report failed before target completion: {exc}", file=sys.stderr)
            ok, failed = [], ["internal report failure"]
        ok_names = set(ok)
        targets = [{"name": name, "ok": name in ok_names} for name in target_names]
        response = {
            "ok": not failed,
            "source_id": source_id,
            "accepted_cidr": accepted_cidr,
            "accepted_at": accepted_at,
            "expires_at": expires_at,
            "targets": targets,
            "request_id": request_id,
        }
        if failed:
            print(f"[WARN] Stash report partial/failed {len(ok)}/{len(TARGETS)}: " + "; ".join(failed), file=sys.stderr)
            response["error"] = "target_report_failed"
            send_json(self, 502, response)
        else:
            send_json(self, 200, response)

    def handle_report(self):
        path, params = parse_request(self)
        if path in ("/health", "/health/"):
            send_text(self, 200, b"OK\n")
            return
        if path not in ("/report", "/report/"):
            send_text(self, 404, b"not found\n")
            return

        secret = os.environ.get("SELF_REPORT_SECRET", "")
        if not secret:
            send_text(self, 503, b"server not configured\n")
            return
        supplied = first([
            params.get("token"),
            self.headers.get("X-PO0-Token"),
            bearer(self.headers.get("Authorization")),
        ])
        if not supplied or not hmac.compare_digest(supplied, secret):
            send_text(self, 401, b"unauthorized\n")
            return

        ip = first([
            params.get("ip"),
            self.headers.get("X-PO0-Client-IP"),
            self.headers.get("CF-Connecting-IP"),
            self.headers.get("X-Real-IP"),
            (self.headers.get("X-Forwarded-For") or "").split(",", 1)[0].strip(),
            self.client_address[0],
        ])
        source_override = first([params.get("source"), params.get("source_id")])
        identity = first([
            params.get("identity"),
            self.headers.get("Cf-Access-Authenticated-User-Email"),
            self.headers.get("CF-Access-Authenticated-User-Email"),
            self.headers.get("X-Forwarded-User"),
            "self-report",
        ])

        if not is_public_ipv4(ip):
            send_text(self, 400, f"invalid public ipv4: {ip}\n")
            return
        try:
            ok, failed = report_all(ip, identity, source_override)
        except Exception as exc:
            send_text(self, 502, f"report failed: {exc}\n")
            return
        if failed:
            send_text(self, 502, f"partial/failed {len(ok)}/{len(TARGETS)} OK; " + "; ".join(failed) + "\n")
        else:
            send_text(self, 200, f"OK {ip}; targets={len(ok)}; target_names={','.join(ok)}\n")

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

with socketserver.ThreadingTCPServer((listen_host, listen_port), Handler) as httpd:
    httpd.serve_forever()
PY
}
install_self_report_service() {
    local script_path unit target_args="" fallback_args="" secret_args="" name="po0-lan-self-report.service" targets generated_secret=0
    [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]] || {
        printf '安装 systemd 服务需要 root。\n' >&2
        return 1
    }
    command -v systemctl >/dev/null 2>&1 || {
        printf '当前系统没有 systemctl，无法安装服务。\n' >&2
        return 1
    }
    targets="$(self_report_targets_env 2>/dev/null || true)"
    if [[ -z "${targets}" ]]; then
        printf '没有可用的 Self-report PO0 目标，未安装后台服务。\n' >&2
        printf '请先在菜单里配置：Self-report 配置 / 启动 -> 目标 Token -> Self-report client-ip Token。\n' >&2
        printf '如果还没有 PO0 目标，请先用主菜单“添加 PO0 目标”。\n' >&2
        return 1
    fi
    if [[ -z "${SELF_REPORT_SECRET}" ]]; then
        SELF_REPORT_SECRET="$(random_secret)"
        [[ -n "${SELF_REPORT_SECRET}" ]] || {
            printf '无法生成 Self-report secret，未安装后台服务。\n' >&2
            return 1
        }
        generated_secret=1
    fi
    script_path="$(ensure_persistent_script)" || return 1
    unit="/etc/systemd/system/${name}"
    if [[ -n "${SELF_REPORT_TARGETS}" ]]; then
        target_args=" --self-report-targets $(sh_quote "${SELF_REPORT_TARGETS}")"
    elif ! has_config_self_report_target; then
        fallback_args=" --po0-host $(sh_quote "${PO0_HOST}") --po0-port $(sh_quote "${PO0_PORT}") --po0-user $(sh_quote "${PO0_USER}") --po0-script $(sh_quote "${PO0_SCRIPT}") --self-report-source $(sh_quote "${SELF_REPORT_SOURCE}") --client-ip-token $(sh_quote "${CLIENT_IP_TOKEN}") --self-report-ttl $(sh_quote "${SELF_REPORT_TTL_SECONDS}")"
    fi
    secret_args=" --self-report-secret $(sh_quote "${SELF_REPORT_SECRET}")"
    save_local_settings || return 1
    if [[ "${generated_secret}" == "1" ]]; then
        printf '检测到 Self-report secret 尚未配置，已自动生成并保存：%s\n' "${SELF_REPORT_SECRET}"
        printf '请把该值同步到访问设备；已有 secret 的环境不会重新生成或轮换。\n'
    fi
    cat > "${unit}" <<EOF
[Unit]
Description=PO0 LAN self-report receiver
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/env bash $(sh_quote "${script_path}") --config $(sh_quote "${CONFIG_FILE}") --self-report-server --self-report-listen $(sh_quote "${SELF_REPORT_LISTEN}")${secret_args}${target_args}${fallback_args}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload || return 1
    systemctl reset-failed "${name}" 2>/dev/null || true
    systemctl enable "${name}" || return 1
    systemctl restart "${name}" || return 1
    printf '已安装并启动 Self-report 服务：%s\n' "${name}"
}
