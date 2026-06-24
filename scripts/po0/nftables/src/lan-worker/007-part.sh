progress_cat() {
    local file="$1"
    local total="${2:-0}"
    local block_size=262144 blocks idx sent percent
    if command -v pv >/dev/null 2>&1 && [[ "${total}" =~ ^[0-9]+$ && "${total}" -gt 0 ]]; then
        pv -f -p -t -e -r -b -s "${total}" "${file}"
        return $?
    fi
    if ! [[ "${total}" =~ ^[0-9]+$ ]] || [[ "${total}" -le 0 ]]; then
        cat "${file}"
        return $?
    fi
    blocks=$(((total + block_size - 1) / block_size))
    idx=0
    while [[ "${idx}" -lt "${blocks}" ]]; do
        dd if="${file}" bs="${block_size}" skip="${idx}" count=1 2>/dev/null || return 1
        sent=$(((idx + 1) * block_size))
        [[ "${sent}" -gt "${total}" ]] && sent="${total}"
        percent=$((sent * 100 / total))
        printf '\r上传进度：%3s%% %s/%s bytes' "${percent}" "${sent}" "${total}" >&2
        idx=$((idx + 1))
    done
    printf '\n' >&2
}

iplist_parallel_jobs() {
    local jobs="${IPLIST_JOBS:-16}"
    [[ "${jobs}" =~ ^[0-9]+$ ]] || jobs=16
    (( jobs >= 1 )) || jobs=1
    (( jobs <= 50 )) || jobs=50
    printf '%s\n' "${jobs}"
}

relative_iplist_data_path() {
    local url="$1"
    case "${url}" in
        */iplist/data/cncity/*.txt)
            printf '%s\n' "data/cncity/${url#*/iplist/data/cncity/}"
            ;;
        */data/cncity/*.txt)
            printf '%s\n' "data/cncity/${url#*/data/cncity/}"
            ;;
        *)
            return 1
            ;;
    esac
}

xargs_supports_parallel() {
    command -v xargs >/dev/null 2>&1 || return 1
    printf 'test\0' | xargs -0 -n 1 -P 1 sh -c ':' _ >/dev/null 2>&1
}

build_iplist_resource() {
    local output="$1"
    local work doc urls queue url rel supported=0 jobs
    work="$(mktemp -d "${TMPDIR:-/tmp}/po0-iplist-worker.XXXXXX")" || return 1
    doc="${work}/docs/cncity.md"
    urls="${work}/urls.txt"
    queue="${work}/download-queue.bin"
    mkdir -p "${work}/docs" "${work}/data/cncity" || {
        rm -rf -- "${work}"
        return 1
    }
    fetch_to_file "https://raw.githubusercontent.com/metowolf/iplist/refs/heads/master/docs/cncity.md" "${doc}" || {
        rm -rf -- "${work}"
        return 1
    }
    grep -Eo 'https?://[^|[:space:]]+\.txt' "${doc}" | sort -u > "${urls}"
    [[ -s "${urls}" ]] || {
        rm -rf -- "${work}"
        return 1
    }
    : > "${queue}" || {
        rm -rf -- "${work}"
        return 1
    }
    while IFS= read -r url; do
        rel="$(relative_iplist_data_path "${url}")" || continue
        ((supported++))
        printf '%s\0%s\0%s\0%s\0' "${supported}" "${rel}" "${url}" "${work}/${rel}" >> "${queue}"
    done < "${urls}"
    [[ "${supported}" -gt 0 ]] || {
        rm -rf -- "${work}"
        return 1
    }
    jobs="$(iplist_parallel_jobs)"
    printf 'iplist 数据下载：%s 个文件，并发 %s\n' "${supported}" "${jobs}"
    if [[ "${jobs}" -gt 1 ]] && xargs_supports_parallel; then
        TOTAL_SUPPORTED="${supported}" xargs -0 -n 4 -P "${jobs}" bash -c '
idx="$1"
rel="$2"
url="$3"
output="$4"
mkdir -p "$(dirname "${output}")"
printf "[%s/%s] %s\n" "${idx}" "${TOTAL_SUPPORTED}" "${rel}"
if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 180 "${url}" -o "${output}"
elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=180 "${url}" -O "${output}"
else
    echo "系统缺少 curl 或 wget。" >&2
    exit 1
fi
' _ < "${queue}" || {
            rm -rf -- "${work}"
            return 1
        }
    else
        [[ "${jobs}" -gt 1 ]] && printf '当前 xargs 不支持并发参数，退回逐个下载。\n' >&2
        while IFS= read -r -d '' _idx && IFS= read -r -d '' rel && IFS= read -r -d '' url && IFS= read -r -d '' _output; do
            printf '[%s/%s] %s\n' "${_idx}" "${supported}" "${rel}"
            mkdir -p "${work}/${rel%/*}" || {
                rm -rf -- "${work}"
                return 1
            }
            fetch_to_file "${url}" "${work}/${rel}" || {
                rm -rf -- "${work}"
                return 1
            }
        done < "${queue}"
    fi
    tar -czf "${output}" -C "${work}" docs data || {
        rm -rf -- "${work}"
        return 1
    }
    rm -rf -- "${work}"
}

sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${file}" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${file}" | awk '{print $1}'
    else
        return 1
    fi
}

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

report_resource_failure() {
    local task_id="$1" worker_id="$2" reason="$3" host="$4" port="$5" user="$6" script="$7" token="$8" extra="$9"
    local remote_cmd
    local -a ssh_args=(-n -p "${port}")
    sanitize_ssh_extra_args "${extra}" "resource fail ${user}@${host}:${port}"
    ssh_args+=("${SSH_EXTRA_ARGV[@]}")
    remote_cmd="bash $(sh_quote "${script}") --resource-task-fail $(sh_quote "${task_id}") $(sh_quote "${worker_id}") $(sh_quote "${reason}") $(sh_quote "${token}")"
    run_with_optional_timeout "$(timeout_seconds "${RESOURCE_CONTROL_TIMEOUT_SECONDS}" 120)" ssh "${ssh_args[@]}" "${user}@${host}" "${remote_cmd}" >/dev/null 2>&1 || true
}

timeout_seconds() {
    local value="${1:-}" fallback="${2:-0}"
    [[ "${value}" =~ ^[0-9]+$ ]] || value="${fallback}"
    printf '%s\n' "${value}"
}

run_with_optional_timeout() {
    local seconds="$1"
    shift
    if [[ "${seconds}" -gt 0 ]] && command -v timeout >/dev/null 2>&1; then
        timeout "${seconds}" "$@"
    else
        "$@"
    fi
}

resource_task_max_per_run() {
    local max="${RESOURCE_TASK_MAX_PER_RUN:-10}"
    [[ "${max}" =~ ^[0-9]+$ ]] || max=10
    (( max <= 100 )) || max=100
    printf '%s\n' "${max}"
}

run_resource_endpoint() {
    local host="$1" port="$2" user="$3" script="$4" token="$5" extra="$6"
    local worker_id endpoint_id remote_cmd response protocol task_id task_type upload_path work output sha size upload_response complete_response reason
    local processed=0 failed=0 max_per_run upload_timeout complete_timeout control_timeout upload_rc complete_rc claim_rc
    local -a ssh_args=(-p "${port}")
    local -a control_ssh_args=(-n -p "${port}")
    worker_id="$(sanitize_field "${WORKER_ID}")"
    worker_id="${worker_id// /_}"
    endpoint_id="$(resource_endpoint_id_for "${host}" "${port}" "${user}")"
    sanitize_ssh_extra_args "${extra}" "resource ${user}@${host}:${port}"
    ssh_args+=("${SSH_EXTRA_ARGV[@]}")
    control_ssh_args+=("${SSH_EXTRA_ARGV[@]}")
    max_per_run="$(resource_task_max_per_run)"
    upload_timeout="$(timeout_seconds "${RESOURCE_UPLOAD_TIMEOUT_SECONDS}" 900)"
    complete_timeout="$(timeout_seconds "${RESOURCE_COMPLETE_TIMEOUT_SECONDS}" 600)"
    control_timeout="$(timeout_seconds "${RESOURCE_CONTROL_TIMEOUT_SECONDS}" 120)"
    while true; do
        if [[ "${max_per_run}" -gt 0 && "${processed}" -ge "${max_per_run}" ]]; then
            printf '资源任务：%s 本轮已处理 %s 个，达到上限 %s。\n' "${host}" "${processed}" "${max_per_run}"
            [[ "${failed}" == "0" ]]
            return $?
        fi

        reason=""
        task_id=""
        task_type=""
        upload_path=""
        output=""
        remote_cmd="bash $(sh_quote "${script}") --resource-task-claim $(sh_quote "${worker_id}") $(sh_quote "${token}")"
        response="$(run_with_optional_timeout "${control_timeout}" ssh "${control_ssh_args[@]}" "${user}@${host}" "${remote_cmd}" 2>&1)"
        claim_rc=$?
        if [[ "${claim_rc}" -ne 0 ]]; then
            if [[ "${claim_rc}" == "124" ]]; then
                response="资源任务查询超时（${control_timeout} 秒）"
            fi
            printf '资源任务查询失败：%s@%s:%s\n' "${user}" "${host}" "${port}" >&2
            [[ -n "${response}" ]] && printf '  %s\n' "$(sanitize_field "${response}")" >&2
            update_resource_stats "${endpoint_id}" "" "" "查询失败" "${response}" || true
            return 1
        fi
        protocol="$(printf '%s\n' "${response}" | grep -E '^(TASK|NO_TASK|ERROR)(\||$)' | tail -n 1)"
        case "${protocol}" in
            NO_TASK)
                if [[ "${processed}" -gt 0 ]]; then
                    printf '资源任务：%s 本轮处理 %s 个，失败 %s，已无待处理任务。\n' "${host}" "${processed}" "${failed}"
                else
                    printf '资源任务：%s 暂无任务。\n' "${host}"
                    update_resource_stats "${endpoint_id}" "" "" "无任务" "PO0 当前没有等待任务" || true
                fi
                [[ "${failed}" == "0" ]]
                return $?
                ;;
            ERROR\|*)
                printf '资源任务查询被拒绝：%s\n' "${protocol#ERROR|}" >&2
                update_resource_stats "${endpoint_id}" "" "" "查询失败" "${protocol#ERROR|}" || true
                return 1
                ;;
            TASK\|*)
                IFS='|' read -r _ task_id task_type upload_path <<< "${protocol}"
                ;;
            *)
                printf 'PO0 返回了无法识别的任务响应：%s\n' "${response}" >&2
                update_resource_stats "${endpoint_id}" "" "" "查询失败" "无法识别 PO0 响应" || true
                return 1
                ;;
        esac

        work="$(mktemp -d "${TMPDIR:-/tmp}/po0-resource-task.XXXXXX")" || return 1
        case "${task_type}" in
            iplist)
                output="${work}/iplist.tar.gz"
                printf '执行资源任务 %s：构建 iplist.tar.gz\n' "${task_id}"
                build_iplist_resource "${output}" || reason="构建 iplist.tar.gz 失败"
                ;;
            ipdb)
                output="${work}/qqwry.ipdb"
                printf '执行资源任务 %s：下载 qqwry.ipdb\n' "${task_id}"
                fetch_to_file "${IPDB_DOWNLOAD_URL}" "${output}" || reason="下载 qqwry.ipdb 失败"
                if [[ -z "${reason}" ]]; then
                    size="$(wc -c < "${output}" | tr -d '[:space:]')"
                    [[ "${size}" =~ ^[0-9]+$ && "${size}" -ge 102400 ]] || reason="qqwry.ipdb 文件过小"
                fi
                ;;
            *)
                reason="PO0 下发了不支持的任务类型"
                ;;
        esac
        if [[ -n "${reason}" ]]; then
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            ((processed++))
            ((failed++))
            continue
        fi
        printf '资源任务 %s：计算 SHA-256 和文件大小...\n' "${task_id}"
        sha="$(sha256_file "${output}")" || reason="本机缺少 SHA-256 工具"
        size="$(wc -c < "${output}" | tr -d '[:space:]')"
        if [[ -n "${reason}" ]]; then
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            ((processed++))
            ((failed++))
            continue
        fi
        remote_cmd="bash $(sh_quote "${script}") --resource-task-upload $(sh_quote "${task_id}") $(sh_quote "${worker_id}") $(sh_quote "${sha}") $(sh_quote "${size}") $(sh_quote "${token}")"
        printf '资源任务 %s：上传到 PO0（%s bytes，超时 %s 秒）...\n' "${task_id}" "${size}" "${upload_timeout}"
        upload_response="$(progress_cat "${output}" "${size}" | run_with_optional_timeout "${upload_timeout}" ssh "${ssh_args[@]}" "${user}@${host}" "${remote_cmd}" 2>&1)"
        upload_rc=$?
        if [[ "${upload_rc}" -ne 0 ]]; then
            if [[ "${upload_rc}" == "124" ]]; then
                reason="PO0 上传资源文件超时（${upload_timeout} 秒）"
            else
                reason="PO0 上传资源文件失败（退出码 ${upload_rc}）：${upload_response}"
            fi
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            printf '%s\n' "${reason}" >&2
            ((processed++))
            ((failed++))
            continue
        fi
        if [[ "${upload_response}" != *"OK|"* ]]; then
            reason="PO0 返回了无法识别的上传响应：${upload_response}"
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            printf '%s\n' "${reason}" >&2
            ((processed++))
            ((failed++))
            continue
        fi
        printf '资源任务 %s：PO0 已接收，开始校验/导入（超时 %s 秒）...\n' "${task_id}" "${complete_timeout}"
        remote_cmd="bash $(sh_quote "${script}") --resource-task-complete $(sh_quote "${task_id}") $(sh_quote "${worker_id}") $(sh_quote "${sha}") $(sh_quote "${size}") $(sh_quote "${token}")"
        complete_response="$(run_with_optional_timeout "${complete_timeout}" ssh "${control_ssh_args[@]}" "${user}@${host}" "${remote_cmd}" 2>&1)"
        complete_rc=$?
        if [[ "${complete_rc}" -ne 0 ]]; then
            if [[ "${complete_rc}" == "124" ]]; then
                reason="PO0 校验或导入超时（${complete_timeout} 秒）"
            else
                reason="PO0 校验或导入失败（退出码 ${complete_rc}）：${complete_response}"
            fi
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            printf '%s\n' "${reason}" >&2
            ((processed++))
            ((failed++))
            continue
        fi
        if [[ "${complete_response}" != *"OK|"* ]]; then
            reason="PO0 返回了无法识别的完成响应：${complete_response}"
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            printf '%s\n' "${reason}" >&2
            ((processed++))
            ((failed++))
            continue
        fi
        update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "成功" "${complete_response##*OK|}" || true
        rm -rf -- "${work}"
        printf '资源任务完成：%s\n' "${complete_response##*OK|}"
        ((processed++))
    done
}

run_resource_targets() {
    local line endpoint_key script_for_key label seen=";" ok=0 fail=0 skipped=0 disabled=0 duplicate=0
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        label="${TARGET_LABEL:-${TARGET_PO0_HOST}}"
        if [[ "${TARGET_ENABLED}" != "1" ]]; then
            ((disabled++))
            continue
        fi
        if [[ -z "${TARGET_RESOURCE_TOKEN}" ]]; then
            printf '资源任务：%s 未配置 Token，跳过。\n' "${label}"
            ((skipped++))
            continue
        fi
        script_for_key="${TARGET_PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}"
        endpoint_key="${TARGET_PO0_USER:-root}@${TARGET_PO0_HOST}:${TARGET_PO0_PORT:-22}:${script_for_key}:${TARGET_RESOURCE_TOKEN}"
        if [[ "${seen}" == *";${endpoint_key};"* ]]; then
            printf '资源任务：%s 与前面目标使用同一 PO0/token，跳过重复轮询。\n' "${label}"
            ((duplicate++))
            continue
        fi
        seen+="${endpoint_key};"
        printf '资源任务：轮询 %s -> %s@%s:%s\n' "${label}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}"
        if run_resource_endpoint "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${TARGET_RESOURCE_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}"; then
            ((ok++))
        else
            ((fail++))
        fi
    done < "${CONFIG_FILE}"
    printf '资源任务轮询完成：成功/无任务 %s，失败 %s，未配置 Token 跳过 %s，停用跳过 %s，重复跳过 %s。\n' "${ok}" "${fail}" "${skipped}" "${disabled}" "${duplicate}"
    prune_resource_events "${RESOURCE_EVENTS_KEEP}" || true
    [[ "${fail}" == "0" ]]
}

run_all_client_jobs() {
    local failed=0
    run_resource_targets || failed=1
    run_config_targets || failed=1
    return "${failed}"
}

self_report_targets_env() {
    local line source ttl extra count=0
    if [[ -n "${SELF_REPORT_TARGETS}" ]]; then
        printf '%s\n' "${SELF_REPORT_TARGETS}" | tr ';' '\n'
        return 0
    fi
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" ]] || continue
        [[ -n "${TARGET_CLIENT_IP_TOKEN}" ]] || continue
        source="${TARGET_CLIENT_IP_SOURCE:-${SELF_REPORT_SOURCE}}"
        ttl="$(normalize_report_ttl_seconds "${TARGET_CLIENT_IP_TTL:-${SELF_REPORT_TTL_SECONDS}}" "${SELF_REPORT_TTL_SECONDS:-43200}")"
        extra="${TARGET_REPORT_SSH_EXTRA_ARGS:-${TARGET_SSH_EXTRA_ARGS}}"
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${source}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${TARGET_CLIENT_IP_TOKEN}" "${ttl:-43200}" "${extra}"
        count=$((count + 1))
    done < "${CONFIG_FILE}"
    if [[ "${count}" == "0" && -n "${PO0_HOST}" && -n "${CLIENT_IP_TOKEN}" ]]; then
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${SELF_REPORT_SOURCE}" "${PO0_HOST}" "${PO0_PORT:-22}" "${PO0_USER:-root}" "${PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${CLIENT_IP_TOKEN}" "$(normalize_report_ttl_seconds "${SELF_REPORT_TTL_SECONDS}" 43200)" "${SSH_EXTRA_ARGS}"
    fi
}

has_config_self_report_target() {
    local line
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" ]] || continue
        [[ -n "${TARGET_PO0_HOST}" && -n "${TARGET_CLIENT_IP_TOKEN}" ]] || continue
        return 0
    done < "${CONFIG_FILE}"
    return 1
}

webauth_targets_env() {
    local line source ttl extra count=0
    if [[ -n "${WEBAUTH_TARGETS}" ]]; then
        printf '%s\n' "${WEBAUTH_TARGETS}" | tr ';' '\n'
        return 0
    fi
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" ]] || continue
        [[ -n "${TARGET_WEBAUTH_TOKEN}" ]] || continue
        source="${TARGET_WEBAUTH_SOURCE:-${WEBAUTH_SOURCE}}"
        ttl="$(normalize_report_ttl_seconds "${TARGET_WEBAUTH_TTL:-${WEBAUTH_TTL_SECONDS}}" "${WEBAUTH_TTL_SECONDS:-43200}")"
        extra="${TARGET_REPORT_SSH_EXTRA_ARGS:-${TARGET_SSH_EXTRA_ARGS}}"
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${source}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${TARGET_WEBAUTH_TOKEN}" "${ttl:-43200}" "${extra}"
        count=$((count + 1))
    done < "${CONFIG_FILE}"
    if [[ "${count}" == "0" && -n "${PO0_HOST}" && -n "${WEBAUTH_TOKEN}" ]]; then
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${WEBAUTH_SOURCE}" "${PO0_HOST}" "${PO0_PORT:-22}" "${PO0_USER:-root}" "${PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${WEBAUTH_TOKEN}" "$(normalize_report_ttl_seconds "${WEBAUTH_TTL_SECONDS}" 43200)" "${SSH_EXTRA_ARGS}"
    fi
}
