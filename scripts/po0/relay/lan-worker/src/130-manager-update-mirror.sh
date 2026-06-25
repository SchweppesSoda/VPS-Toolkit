manager_update_tokens_env() {
    local tokens="" seen=";" line token
    if [[ -n "${RESOURCE_TOKEN}" ]]; then
        token="$(sanitize_field "${RESOURCE_TOKEN}")"
        if [[ -n "${token}" && "${seen}" != *";${token};"* ]]; then
            tokens+="${token}"$'\n'
            seen+="${token};"
        fi
    fi
    ensure_config_file || true
    if [[ -r "${CONFIG_FILE}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            parse_target_line "${line}" || continue
            [[ "${TARGET_ENABLED}" == "1" ]] || continue
            token="$(sanitize_field "${TARGET_RESOURCE_TOKEN}")"
            [[ -n "${token}" ]] || continue
            if [[ "${seen}" != *";${token};"* ]]; then
                tokens+="${token}"$'\n'
                seen+="${token};"
            fi
        done < "${CONFIG_FILE}"
    fi
    printf '%s' "${tokens}"
}

run_manager_update_mirror_server() {
    local py listen_host listen_port tokens
    tokens="$(manager_update_tokens_env)" || return 1
    [[ -n "${tokens}" ]] || {
        printf '没有可用的 resource token，无法启动 manager 更新镜像。\n' >&2
        return 1
    }
    if have_cmd python3; then
        py="python3"
    elif have_cmd python; then
        py="python"
    else
        printf 'missing python3/python; cannot run manager update mirror server.\n' >&2
        return 1
    fi
    listen_host="${MANAGER_UPDATE_LISTEN%:*}"
    listen_port="${MANAGER_UPDATE_LISTEN##*:}"
    [[ -n "${listen_host}" && "${listen_host}" != "${MANAGER_UPDATE_LISTEN}" ]] || listen_host="127.0.0.1"
    [[ "${listen_port}" =~ ^[0-9]+$ ]] || listen_port="8789"
    export PO0_MANAGER_UPDATE_TOKENS="${tokens}"
    export PO0_MANAGER_DOWNLOAD_URL="${MANAGER_DOWNLOAD_URL}"
    printf 'Manager update mirror listening on %s:%s; PO0 pulls over HTTP, mirror pulls GitHub over HTTPS.\n' "${listen_host}" "${listen_port}"
    "${py}" - "${listen_host}" "${listen_port}" <<'PY'
import hashlib
import hmac
import http.server
import re
import socketserver
import sys
import time
import urllib.parse
import urllib.request
import os

listen_host, listen_port = sys.argv[1], int(sys.argv[2])
raw_url = os.environ.get("PO0_MANAGER_DOWNLOAD_URL", "")
tokens = [t.strip() for t in os.environ.get("PO0_MANAGER_UPDATE_TOKENS", "").splitlines() if t.strip()]
token_by_id = {hashlib.sha256(t.encode("utf-8")).hexdigest(): t for t in tokens}
PATH = "/po0-manager-update/nftables-relay-manager.sh"
HEALTH = "/po0-manager-update/health"

if not raw_url.startswith("https://"):
    raise SystemExit("manager download URL must use HTTPS")
if not token_by_id:
    raise SystemExit("missing manager update tokens")

class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "po0-manager-update-mirror/1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - - [%s] %s\n" % (self.client_address[0], self.log_date_time_string(), fmt % args))

    def send_text(self, code, text):
        data = text.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == HEALTH:
            self.send_text(200, "OK\n")
            return
        if parsed.path != PATH:
            self.send_text(404, "not found\n")
            return
        query = urllib.parse.parse_qs(parsed.query)
        nonce = query.get("nonce", [""])[0]
        token_id = query.get("token_id", [""])[0]
        if not re.fullmatch(r"[A-Za-z0-9._:-]{8,128}", nonce or ""):
            self.send_text(400, "invalid nonce\n")
            return
        if not re.fullmatch(r"[a-f0-9]{64}", token_id or ""):
            self.send_text(400, "invalid token_id\n")
            return
        token = token_by_id.get(token_id)
        if not token:
            self.send_text(403, "unknown token_id\n")
            return
        try:
            req = urllib.request.Request(raw_url, headers={"User-Agent": self.server_version})
            with urllib.request.urlopen(req, timeout=60) as resp:
                body = resp.read(2 * 1024 * 1024)
        except Exception as exc:
            self.send_text(502, "fetch failed: %s\n" % exc)
            return
        if len(body) == 0 or len(body) >= 2 * 1024 * 1024:
            self.send_text(502, "invalid script size\n")
            return
        text = body.decode("utf-8", "replace")
        if 'SCRIPT_NAME="po0-nftables-relay-manager"' not in text or "# CHANGELOG_BEGIN" not in text or "# CHANGELOG_END" not in text:
            self.send_text(502, "fetched file is not po0 manager script\n")
            return
        version_match = re.search(r'^SCRIPT_VERSION="([^"]+)"', text, re.MULTILINE)
        version = version_match.group(1) if version_match else "unknown"
        sha = hashlib.sha256(body).hexdigest()
        size = str(len(body))
        message = "|".join([nonce, sha, size, version])
        sig = hmac.new(token.encode("utf-8"), message.encode("utf-8"), hashlib.sha256).hexdigest()
        self.send_response(200)
        self.send_header("Content-Type", "text/x-shellscript; charset=utf-8")
        self.send_header("Content-Length", size)
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-PO0-Manager-Version", version)
        self.send_header("X-PO0-Manager-SHA256", sha)
        self.send_header("X-PO0-Manager-Size", size)
        self.send_header("X-PO0-Manager-Nonce", nonce)
        self.send_header("X-PO0-Manager-HMAC", sig)
        self.end_headers()
        self.wfile.write(body)

class ReusableThreadingTCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True

with ReusableThreadingTCPServer((listen_host, listen_port), Handler) as httpd:
    httpd.serve_forever()
PY
}
