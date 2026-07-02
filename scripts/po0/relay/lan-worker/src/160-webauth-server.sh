probe_webauth_target() {
    local failed=0 response targets line source host port user script token ttl extra count=0
    have_cmd ssh || { probe_fail "缺少 ssh。"; failed=1; }
    if ! have_cmd python3 && ! have_cmd python; then
        probe_fail "缺少 python3/python，无法运行 WebAuth 本地 HTTP 服务。"
        failed=1
    fi
    targets="$(webauth_targets_env)" || return 1
    [[ -n "${targets}" ]] || {
        probe_fail "没有 WebAuth 上报目标。请配置 --po0-host/--webauth-token，或在菜单中添加 WebAuth 放行目标。"
        return 1
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" == \#* ]] || continue
        IFS='|' read -r source host port user script token ttl extra <<< "${line}"
        source="$(sanitize_field "${source:-${WEBAUTH_SOURCE}}")"
        host="$(sanitize_field "${host}")"
        port="$(sanitize_field "${port:-22}")"
        user="$(sanitize_field "${user:-root}")"
        script="$(sanitize_field "${script:-${DEFAULT_PO0_SCRIPT}}")"
        token="$(sanitize_field "${token}")"
        extra="$(sanitize_field "${extra:-}")"
        [[ -n "${host}" && -n "${token}" ]] || {
            probe_fail "跳过无效 WebAuth 上报目标：${line}"
            failed=1
            continue
        }
        count=$((count + 1))
        if response="$(remote_manager_call "${host}" "${port:-22}" "${user:-root}" "${script:-${DEFAULT_PO0_SCRIPT}}" "${extra}" --webauth-report-check "${source:-${WEBAUTH_SOURCE}}" "${token}" 2>&1)"; then
            probe_ok "WebAuth 目标 ${source:-${WEBAUTH_SOURCE}}@${host}:${port:-22} 权限检查通过：${response}"
        else
            probe_fail "WebAuth 目标 ${source:-${WEBAUTH_SOURCE}}@${host}:${port:-22} 权限检查失败：${response}"
            failed=1
        fi
    done < <(printf '%s\n' "${targets}")
    if [[ "${count}" == "0" ]]; then
        probe_fail "没有可用的 WebAuth 上报目标。"
        failed=1
    fi
    return "${failed}"
}

run_webauth_server() {
    local py listen_host listen_port targets
    targets="$(webauth_targets_env)" || return 1
    [[ -n "${targets}" ]] || { printf 'missing WebAuth PO0 target. Configure --po0-host/--webauth-token or WebAuth 上报目标。\n' >&2; return 1; }
    if have_cmd python3; then
        py="python3"
    elif have_cmd python; then
        py="python"
    else
        printf 'missing python3/python; cannot run WebAuth server.\n' >&2
        return 1
    fi
    listen_host="${WEBAUTH_LISTEN%:*}"
    listen_port="${WEBAUTH_LISTEN##*:}"
    [[ -n "${listen_host}" && "${listen_host}" != "${WEBAUTH_LISTEN}" ]] || listen_host="127.0.0.1"
    [[ "${listen_port}" =~ ^[0-9]+$ ]] || listen_port="8787"
    export PO0_WEBAUTH_TARGETS="${targets}"
    printf 'WebAuth server listening on %s:%s; PO0 has no HTTP listener.\n' "${listen_host}" "${listen_port}"
    "${py}" - "${listen_host}" "${listen_port}" <<'PY'
import concurrent.futures
import errno
import http.server
import os
import re
import shlex
import shutil
import socketserver
import subprocess
import sys
import time

listen_host, listen_port = sys.argv[1], int(sys.argv[2])
SSH_BIN = shutil.which("ssh") or "ssh"
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
            'source': source or 'cf-access',
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

TARGETS = parse_targets(os.environ.get('PO0_WEBAUTH_TARGETS', ''))
if not TARGETS:
    raise SystemExit('missing PO0_WEBAUTH_TARGETS')

def report_target(target, ip, identity, note):
    ttl = normalized_ttl(target.get('ttl'), 43200)
    expires_at = str(int(time.time()) + max(60, ttl))
    remote = " ".join([
        "bash",
        shlex.quote(target['script']),
        "--webauth-report",
        shlex.quote(target['source']),
        shlex.quote(ip),
        shlex.quote(identity or "unknown"),
        shlex.quote(expires_at),
        shlex.quote(target['token']),
        shlex.quote(note or "lan-webauth"),
    ])
    cmd = [SSH_BIN, "-p", target['port']]
    cmd.extend(sanitized_extra_args(target.get('extra', ''), f"WebAuth {target['user']}@{target['host']}:{target['port']}"))
    cmd.extend([f"{target['user']}@{target['host']}", remote])
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)

def report_one(target, ip, identity, note):
    label = f"{target['source']}@{target['host']}"
    try:
        result = report_target(target, ip, identity, note)
    except subprocess.TimeoutExpired as exc:
        return label, False, f"timeout after {exc.timeout}s"
    except Exception as exc:
        return label, False, str(exc)
    if result.returncode == 0:
        return label, True, ""
    return label, False, str(result.stderr or result.stdout or result.returncode).strip()

def report_all(ip, identity, note):
    ok = []
    failed = []
    max_workers = min(len(TARGETS), 8)
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(report_one, target, ip, identity, note) for target in TARGETS]
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
        if self.path.startswith("/health"):
            send_text(self, 200, b"OK\n")
            return
        ip = self.headers.get("CF-Connecting-IP") or self.headers.get("X-Real-IP") or ""
        if not ip and self.headers.get("X-Forwarded-For"):
            ip = self.headers.get("X-Forwarded-For").split(",", 1)[0].strip()
        if not ip:
            ip = self.client_address[0]
        identity = (
            self.headers.get("Cf-Access-Authenticated-User-Email")
            or self.headers.get("CF-Access-Authenticated-User-Email")
            or self.headers.get("X-Forwarded-User")
            or "unknown"
        )
        if not is_public_ipv4(ip):
            send_text(self, 400, f"invalid public ipv4: {ip}\n")
            return
        try:
            ok, failed = report_all(ip, identity, "cf-access")
        except Exception as exc:
            send_text(self, 502, f"report failed: {exc}\n")
            return
        if failed:
            body = [
                "PO0 WebAuth partial/failed",
                f"ip: {ip}",
                f"identity: {identity}",
                f"ok: {len(ok)}/{len(TARGETS)}",
                "updated: " + (", ".join(ok) if ok else "none"),
                "failed: " + "; ".join(failed),
                "",
            ]
            send_text(self, 502, "\n".join(body))
        else:
            body = [
                "PO0 WebAuth OK",
                f"ip: {ip}",
                f"identity: {identity}",
                "updated: " + ", ".join(ok),
                "",
            ]
            send_text(self, 200, "\n".join(body))

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

with socketserver.ThreadingTCPServer((listen_host, listen_port), Handler) as httpd:
    httpd.serve_forever()
PY
}
install_webauth_service() {
    local script_path unit target_args="" name="po0-lan-webauth.service" targets
    [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]] || {
        printf '安装 systemd 服务需要 root。\n' >&2
        return 1
    }
    command -v systemctl >/dev/null 2>&1 || {
        printf '当前系统没有 systemctl，无法安装服务。\n' >&2
        return 1
    }
    targets="$(webauth_targets_env 2>/dev/null || true)"
    if [[ -z "${targets}" ]]; then
        printf '没有可用的 WebAuth PO0 目标，未安装后台服务。\n' >&2
        printf '请先在菜单里配置：PO0 目标、SSH、Token 与 TTL -> 目标 Token -> WebAuth Token。\n' >&2
        printf '如果还没有 PO0 目标，请先用主菜单“添加 PO0 目标”。\n' >&2
        return 1
    fi
    script_path="$(ensure_persistent_script)" || return 1
    unit="/etc/systemd/system/${name}"
    [[ -n "${WEBAUTH_TARGETS}" ]] && target_args=" --webauth-targets $(sh_quote "${WEBAUTH_TARGETS}")"
    save_local_settings || return 1
    cat > "${unit}" <<EOF
[Unit]
Description=PO0 LAN WebAuth client reporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/env bash $(sh_quote "${script_path}") --config $(sh_quote "${CONFIG_FILE}") --webauth-server --listen $(sh_quote "${WEBAUTH_LISTEN}") --po0-host $(sh_quote "${PO0_HOST}") --po0-port $(sh_quote "${PO0_PORT}") --po0-user $(sh_quote "${PO0_USER}") --po0-script $(sh_quote "${PO0_SCRIPT}") --webauth-source $(sh_quote "${WEBAUTH_SOURCE}") --webauth-token $(sh_quote "${WEBAUTH_TOKEN}") --webauth-ttl $(sh_quote "${WEBAUTH_TTL_SECONDS}")${target_args}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload || return 1
    systemctl enable --now "${name}" || return 1
    printf '已安装并启动 WebAuth 服务：%s\n' "${name}"
}
