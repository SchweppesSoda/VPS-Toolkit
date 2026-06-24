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
    export PO0_SELF_REPORT_TARGETS="${targets}" SELF_REPORT_SECRET
    printf 'Self-report server listening on %s:%s; device -> LAN Worker -> SSH -> PO0.\n' "${listen_host}" "${listen_port}"
    "${py}" - "${listen_host}" "${listen_port}" <<'PY'
import http.server
import os
import re
import shlex
import socketserver
import subprocess
import sys
import urllib.parse

listen_host, listen_port = sys.argv[1], int(sys.argv[2])

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

def report_target(target, ip, identity, source_override):
    source = source_override or target['source']
    ttl = str(normalized_ttl(target.get('ttl'), 43200))
    remote = " ".join([
        "bash",
        shlex.quote(target['script']),
        "--client-ip-report",
        shlex.quote(source),
        shlex.quote(ip),
        shlex.quote(target['token']),
        shlex.quote(identity or "self-report"),
        shlex.quote(ttl),
    ])
    cmd = ["ssh", "-p", target['port']]
    cmd.extend(sanitized_extra_args(target.get('extra', ''), f"Self-report {target['user']}@{target['host']}:{target['port']}"))
    cmd.extend([f"{target['user']}@{target['host']}", remote])
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)

def report_all(ip, identity, source_override):
    ok = []
    failed = []
    for target in TARGETS:
        result = report_target(target, ip, identity, source_override)
        label = f"{source_override or target['source']}@{target['host']}"
        if result.returncode == 0:
            ok.append(label)
        else:
            failed.append(f"{label}: {result.stderr or result.stdout or result.returncode}")
    return ok, failed

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.handle_report()

    def do_POST(self):
        self.handle_report()

    def handle_report(self):
        path, params = parse_request(self)
        if path in ("/health", "/health/"):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK\n")
            return
        if path not in ("/report", "/report/"):
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"not found\n")
            return

        secret = os.environ.get("SELF_REPORT_SECRET", "")
        supplied = first([
            params.get("token"),
            self.headers.get("X-PO0-Token"),
            bearer(self.headers.get("Authorization")),
        ])
        if secret and supplied != secret:
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b"unauthorized\n")
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
            self.send_response(400)
            self.end_headers()
            self.wfile.write(f"invalid public ipv4: {ip}\n".encode())
            return
        try:
            ok, failed = report_all(ip, identity, source_override)
        except Exception as exc:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(f"report failed: {exc}\n".encode())
            return
        if failed:
            self.send_response(502)
            self.end_headers()
            self.wfile.write((f"partial/failed {len(ok)}/{len(TARGETS)} OK; " + "; ".join(failed) + "\n").encode())
        else:
            self.send_response(200)
            self.end_headers()
            self.wfile.write((f"OK {ip}; targets={len(ok)}\n").encode())

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

with socketserver.ThreadingTCPServer((listen_host, listen_port), Handler) as httpd:
    httpd.serve_forever()
PY
}
install_self_report_service() {
    local script_path unit target_args="" fallback_args="" secret_args="" name="po0-lan-self-report.service" targets
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
        printf '警告：Self-report secret 为空；访问设备上报将不校验共享密钥。建议先用菜单生成 / 修改 secret。\n' >&2
    fi
    script_path="$(ensure_persistent_script)" || return 1
    unit="/etc/systemd/system/${name}"
    if [[ -n "${SELF_REPORT_TARGETS}" ]]; then
        target_args=" --self-report-targets $(sh_quote "${SELF_REPORT_TARGETS}")"
    elif ! has_config_self_report_target; then
        fallback_args=" --po0-host $(sh_quote "${PO0_HOST}") --po0-port $(sh_quote "${PO0_PORT}") --po0-user $(sh_quote "${PO0_USER}") --po0-script $(sh_quote "${PO0_SCRIPT}") --self-report-source $(sh_quote "${SELF_REPORT_SOURCE}") --client-ip-token $(sh_quote "${CLIENT_IP_TOKEN}") --self-report-ttl $(sh_quote "${SELF_REPORT_TTL_SECONDS}")"
    fi
    [[ -n "${SELF_REPORT_SECRET}" ]] && secret_args=" --self-report-secret $(sh_quote "${SELF_REPORT_SECRET}")"
    save_local_settings || return 1
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

normalize_self_report_https_domain() {
    local domain="$1"
    domain="$(trim "${domain}")"
    domain="${domain#http://}"
    domain="${domain#https://}"
    domain="${domain%%/*}"
    domain="${domain%%:*}"
    domain="${domain,,}"
    printf '%s\n' "${domain}"
}

validate_self_report_https_domain() {
    local domain="$1"
    [[ -n "${domain}" ]] || {
        printf '缺少 Self-report HTTPS 域名。\n' >&2
        return 1
    }
    [[ "${domain}" == *.* && "${domain}" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]] || {
        printf 'Self-report HTTPS 域名格式无效：%s\n' "${domain}" >&2
        return 1
    }
    is_public_ipv4 "${domain}" && {
        printf 'Self-report HTTPS 需要公网域名，不能直接使用 IP：%s\n' "${domain}" >&2
        return 1
    }
    return 0
}

self_report_https_domain_from_caddy() {
    local line
    [[ -r "${SELF_REPORT_CADDY_SNIPPET}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && "${line}" != \#* ]] || continue
        case "${line}" in
            *"{")
                line="${line%\{}"
                line="$(trim "${line}")"
                [[ -n "${line}" ]] || return 1
                printf '%s\n' "${line}"
                return 0
                ;;
        esac
    done < "${SELF_REPORT_CADDY_SNIPPET}"
    return 1
}

current_self_report_https_domain() {
    if [[ -n "${SELF_REPORT_HTTPS_DOMAIN}" ]]; then
        printf '%s\n' "${SELF_REPORT_HTTPS_DOMAIN}"
    else
        self_report_https_domain_from_caddy 2>/dev/null || true
    fi
}

normalize_manager_update_endpoint() {
    local endpoint="$1" host port
    endpoint="$(trim "${endpoint}")"
    endpoint="${endpoint#http://}"
    endpoint="${endpoint#https://}"
    endpoint="${endpoint%%/*}"
    endpoint="${endpoint%%\?*}"
    endpoint="${endpoint,,}"
    if [[ "${endpoint}" == *:* ]]; then
        host="${endpoint%:*}"
        port="${endpoint##*:}"
    else
        host="${endpoint}"
        port="${MANAGER_UPDATE_DEFAULT_PORT}"
    fi
    printf '%s:%s\n' "${host}" "${port}"
}

manager_update_endpoint_host() {
    local endpoint="$1"
    printf '%s\n' "${endpoint%:*}"
}

manager_update_endpoint_port() {
    local endpoint="$1"
    printf '%s\n' "${endpoint##*:}"
}

validate_manager_update_endpoint() {
    local endpoint="$1" host port
    host="$(manager_update_endpoint_host "${endpoint}")"
    port="$(manager_update_endpoint_port "${endpoint}")"
    [[ -n "${host}" ]] || {
        printf '缺少 PO0 manager 更新 HTTP 主机/IP。\n' >&2
        return 1
    }
    [[ "${port}" =~ ^[0-9]+$ ]] && (( 10#${port} >= 1 && 10#${port} <= 65535 )) || {
        printf 'PO0 manager 更新 HTTP 端口无效：%s\n' "${port}" >&2
        return 1
    }
    validate_ip "${host}" && return 0
    [[ "${host}" == *.* && "${host}" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]] || {
        printf 'PO0 manager 更新 HTTP 主机/IP 格式无效：%s\n' "${host}" >&2
        return 1
    }
    return 0
}

manager_update_caddy_site_address() {
    local endpoint="$1" port
    port="$(manager_update_endpoint_port "${endpoint}")"
    printf ':%s\n' "${port}"
}

ensure_caddy_installed() {
    if have_cmd caddy; then
        return 0
    fi
    [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]] || {
        printf '安装 Caddy 需要 root。请先手动安装 caddy，或用 root 重新运行菜单。\n' >&2
        return 1
    }
    if have_cmd apt-get; then
        apt-get update -y && apt-get install -y caddy
    elif have_cmd dnf; then
        dnf install -y caddy
    elif have_cmd yum; then
        yum install -y caddy
    elif have_cmd apk; then
        apk add --no-cache caddy
    else
        printf '未识别的包管理器。请先手动安装 Caddy，再重新配置 Self-report HTTPS。\n' >&2
        return 1
    fi
    have_cmd caddy || {
        printf 'Caddy 安装后仍不可用，请检查包管理器输出。\n' >&2
        return 1
    }
}

ensure_caddyfile_import() {
    local caddy_dir snippet_dir manager_snippet_dir import_line manager_import_line
    caddy_dir="$(path_dirname "${CADDYFILE_PATH}")"
    snippet_dir="$(path_dirname "${SELF_REPORT_CADDY_SNIPPET}")"
    manager_snippet_dir="$(path_dirname "${MANAGER_UPDATE_CADDY_SNIPPET}")"
    mkdir -p "${caddy_dir}" "${snippet_dir}" "${manager_snippet_dir}" || return 1
    [[ -f "${CADDYFILE_PATH}" ]] || : > "${CADDYFILE_PATH}" || return 1
    import_line="import ${snippet_dir%/}/*.caddy"
    if ! awk '{$1=$1; print}' "${CADDYFILE_PATH}" 2>/dev/null | grep -Fxq "${import_line}"; then
        {
            printf '\n'
            printf '# PO0 LAN Worker managed snippets\n'
            printf '%s\n' "${import_line}"
        } >> "${CADDYFILE_PATH}" || return 1
    fi
    manager_import_line="import ${manager_snippet_dir%/}/*.caddy"
    if [[ "${manager_import_line}" != "${import_line}" ]] \
        && ! awk '{$1=$1; print}' "${CADDYFILE_PATH}" 2>/dev/null | grep -Fxq "${manager_import_line}"; then
        printf '%s\n' "${manager_import_line}" >> "${CADDYFILE_PATH}" || return 1
    fi
}

write_self_report_caddy_config() {
    local domain="$1" backend_host backend_port
    backend_host="${SELF_REPORT_HTTPS_BACKEND%:*}"
    backend_port="${SELF_REPORT_HTTPS_BACKEND##*:}"
    [[ -n "${backend_host}" && "${backend_host}" != "${SELF_REPORT_HTTPS_BACKEND}" ]] || backend_host="127.0.0.1"
    [[ "${backend_port}" =~ ^[0-9]+$ ]] || backend_port="8788"
    mkdir -p "$(path_dirname "${SELF_REPORT_CADDY_SNIPPET}")" || return 1
    cat > "${SELF_REPORT_CADDY_SNIPPET}" <<EOF
# Managed by po0-lan-client. Self-report HTTPS entrypoint.
${domain} {
    handle /report {
        reverse_proxy ${backend_host}:${backend_port}
    }
    handle /health {
        reverse_proxy ${backend_host}:${backend_port}
    }
    respond 404
}
EOF
}
