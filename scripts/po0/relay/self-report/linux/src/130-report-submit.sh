report_detail_output_enabled() {
    if declare -F report_detail_enabled >/dev/null 2>&1; then
        report_detail_enabled
    else
        return 0
    fi
}

# The Worker lane has its own attempt clock.  It is intentionally separate
# from the official firewall state so a ten-minute official wake-up cannot
# turn the existing hourly Worker report into a ten-minute report.
worker_state_file() {
    if [[ -n "${XDG_STATE_HOME:-}" ]]; then
        printf '%s\n' "${XDG_STATE_HOME}/po0-outbound-ip-report/worker.state"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.local/state/po0-outbound-ip-report/worker.state"
    else
        printf '%s\n' "${TMPDIR:-/tmp}/po0-outbound-ip-report-$(id -u 2>/dev/null || printf 0)/worker.state"
    fi
}

worker_now() {
    if declare -F official_now >/dev/null 2>&1; then
        official_now
    else
        date +%s
    fi
}

worker_interval_seconds() {
    local minutes="${CRON_MINUTES:-60}"
    [[ "${minutes}" =~ ^[0-9]+$ && "${minutes}" -ge 1 ]] || minutes="60"
    if declare -F cron_minutes_to_seconds >/dev/null 2>&1; then
        cron_minutes_to_seconds "${minutes}"
    else
        printf '%s\n' "$((10#${minutes} * 60))"
    fi
}

worker_last_attempt_at() {
    local state
    state="$(worker_state_file)"
    [[ -r "${state}" ]] || return 1
    sed -n 's/^last_attempt_at=\([0-9][0-9]*\)$/\1/p' "${state}" | head -n 1
}

worker_due() {
    local now last interval
    [[ "${SCHEDULED_RUN:-0}" == "1" ]] || return 0
    [[ "${FORCE_REPORT:-0}" == "1" ]] && return 0
    interval="$(worker_interval_seconds)"
    last="$(worker_last_attempt_at 2>/dev/null || true)"
    [[ "${last}" =~ ^[0-9]+$ ]] || return 0
    now="$(worker_now)"
    (( now < last || now - last >= interval ))
}

worker_mark_attempt() {
    local state dir tmp old_umask now
    state="$(worker_state_file)"
    dir="$(dirname "${state}")"
    mkdir -p "${dir}" 2>/dev/null || return 1
    chmod 700 "${dir}" 2>/dev/null || return 1
    [[ -d "${dir}" && ! -L "${dir}" ]] || return 1
    now="$(worker_now)"
    old_umask="$(umask)"
    umask 077
    if ! tmp="$(mktemp "${dir%/}/.po0-worker-state.XXXXXX" 2>/dev/null)"; then
        umask "${old_umask}"
        return 1
    fi
    if [[ ! -f "${tmp}" || -L "${tmp}" ]] || ! chmod 600 "${tmp}" 2>/dev/null; then
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    fi
    if ! {
        printf 'last_attempt_at=%s\n' "${now}"
        printf 'last_status=attempted\n'
    } > "${tmp}"; then
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    fi
    if ! mv -f "${tmp}" "${state}"; then
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    fi
    umask "${old_umask}"
    chmod 600 "${state}" 2>/dev/null || true
    return 0
}

REPORT_LOCK_DIR=""
REPORT_LOCK_HELD="0"

report_run_lock_path() {
    local dir tmp_root uid owner current_uid mode
    if [[ -n "${XDG_RUNTIME_DIR:-}" && "${XDG_RUNTIME_DIR}" != "/" ]]; then
        dir="${XDG_RUNTIME_DIR}/po0-outbound-ip-report"
    elif [[ -n "${XDG_STATE_HOME:-}" && "${XDG_STATE_HOME}" != "/" ]]; then
        dir="${XDG_STATE_HOME}/po0-outbound-ip-report"
    elif [[ -n "${HOME:-}" ]]; then
        dir="${HOME}/.local/state/po0-outbound-ip-report"
    else
        tmp_root="${TMPDIR:-/tmp}"
        [[ -n "${tmp_root}" && "${tmp_root}" != "/" ]] || tmp_root="/tmp"
        uid="$(id -u 2>/dev/null || printf 0)"
        dir="${tmp_root%/}/po0-outbound-ip-report-${uid}"
    fi
    while [[ "${dir}" == */ && "${dir}" != "/" ]]; do
        dir="${dir%/}"
    done
    [[ -n "${dir}" && "${dir}" != "/" ]] || return 1
    # Reuse the official lane's owner/mode/symlink checks when that lane is
    # present.  This keeps the lock path subject to the same security contract
    # and lets platform-specific tests mock the one filesystem primitive.  The
    # fallback is for the legacy Worker-only source subset, where 125 is not
    # included in the manifest.
    if declare -F official_secure_state_dir >/dev/null 2>&1; then
        official_secure_state_dir "${dir}" || return 1
    else
        case "$(uname -s 2>/dev/null || true)" in
            MINGW*|MSYS*|CYGWIN*)
                # The Worker-only test/source subset does not include 125's
                # secure-state helper. Git Bash cannot apply POSIX mode bits
                # to NTFS, so retain symlink/ownership-by-location checks and
                # let the platform-specific test inject the mode primitive.
                [[ ! -L "${dir}" ]] || return 1
                mkdir -p "${dir}" 2>/dev/null || return 1
                [[ -d "${dir}" && ! -L "${dir}" ]] || return 1
                ;;
            *)
                [[ ! -L "${dir}" ]] || return 1
                mkdir -p "${dir}" 2>/dev/null || return 1
                [[ -d "${dir}" && ! -L "${dir}" ]] || return 1
                owner="$(stat -c '%u' "${dir}" 2>/dev/null || true)"
                current_uid="$(id -u 2>/dev/null || true)"
                [[ "${owner}" =~ ^[0-9]+$ && "${current_uid}" =~ ^[0-9]+$ && "${owner}" == "${current_uid}" ]] || return 1
                chmod 700 "${dir}" 2>/dev/null || return 1
                mode="$(stat -c '%a' "${dir}" 2>/dev/null || true)"
                [[ "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
                mode="${mode: -3}"
                [[ "${mode}" == "700" ]] || return 1
                ;;
        esac
    fi
    printf '%s/.po0-outbound-ip-report.lock\n' "${dir%/}"
}

report_run_lock_release() {
    local lock="${REPORT_LOCK_DIR:-}"
    if [[ "${REPORT_LOCK_HELD:-0}" == "1" && -n "${lock}" && -d "${lock}" && ! -L "${lock}" ]]; then
        if [[ -f "${lock}/pid" && ! -L "${lock}/pid" ]]; then
            rm -f -- "${lock}/pid" 2>/dev/null || true
        fi
        rmdir -- "${lock}" 2>/dev/null || true
    fi
    REPORT_LOCK_HELD="0"
    REPORT_LOCK_DIR=""
}

report_run_lock_acquire() {
    local lock pid attempt
    lock="$(report_run_lock_path 2>/dev/null || true)"
    [[ -n "${lock}" ]] || return 1
    for attempt in 1 2; do
        if mkdir -- "${lock}" 2>/dev/null; then
            if ! printf '%s\n' "$$" > "${lock}/pid"; then
                rmdir -- "${lock}" 2>/dev/null || true
                return 1
            fi
            chmod 600 "${lock}/pid" 2>/dev/null || true
            REPORT_LOCK_DIR="${lock}"
            REPORT_LOCK_HELD="1"
            # Do not capture or replace the caller's traps here.  In Bash a
            # command substitution around `trap -p` can execute an inherited
            # EXIT trap in its helper shell, unexpectedly deleting the
            # caller's temporary directory before the report starts.  Normal
            # returns explicitly release this lock; an interrupted process
            # leaves a pid marker that the next invocation safely reaps when
            # the pid is dead.
            return 0
        fi
        [[ -L "${lock}" ]] && return 1
        if [[ -f "${lock}/pid" && ! -L "${lock}/pid" ]]; then
            pid="$(sed -n '1p' "${lock}/pid" 2>/dev/null || true)"
            if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
                return 2
            fi
            rm -f -- "${lock}/pid" 2>/dev/null || return 2
            rmdir -- "${lock}" 2>/dev/null || return 2
        else
            # A directory without our non-symlink pid marker is treated as
            # busy; never remove an unrecognized pre-existing directory.
            return 2
        fi
    done
    return 2
}

worker_report_once() {
    worker_channel_requested || return 0
    local wan_targets wan l3_device ip response curl_rc report_source report_identity
    local http_code success_message label total=0 success_count=0 failure_count=0
    local curl_args=()
    validate_worker_url || { self_report_incomplete "LAN Worker URL 未通过检查。"; return 1; }
    validate_router_probe_url || { self_report_incomplete "上游路由器 WAN 探针 URL 未通过检查。"; return 1; }
    command -v curl >/dev/null 2>&1 || {
        echo "缺少 curl，无法上报到 LAN Worker。" >&2
        self_report_incomplete "缺少 curl，无法发起上报。"
        return 1
    }
    WANS="$(normalize_wan_selection_list "${WANS:-}")"
    validate_wan_selection || {
        self_report_incomplete "WAN 选择配置无效。"
        return 1
    }
    prepare_router_probe_batch
    wan_targets="$(resolve_report_wans)" || {
        if [[ -n "${ROUTER_PROBE_URL}" ]]; then
            self_report_incomplete "上游路由器探针没有返回可用 WAN。"
        else
            self_report_incomplete "--wan all 需要 OpenWrt、ubus、uci 和至少一个已启用的 mwan3 WAN。"
        fi
        return 1
    }
    while IFS= read -r wan; do
        [[ -n "${wan}" ]] || continue
        total=$((total + 1))
        if [[ "${wan}" == "__default__" ]]; then
            wan=""
            l3_device=""
            label="当前默认路由"
            report_source="$(normalize_report_token "${SOURCE_ID}" "$(default_source_id)")"
            report_identity="$(normalize_report_token "${IDENTITY}" "${report_source}")"
        else
            if [[ -n "${ROUTER_PROBE_URL}" ]]; then
                l3_device=""
                label="上游路由器 WAN ${wan}"
            else
                l3_device="$(openwrt_wan_l3_device "${wan}")" || {
                    printf 'OpenWrt WAN %s 不存在、未启用或没有可用的三层设备。\n' "${wan}" >&2
                    failure_count=$((failure_count + 1))
                    continue
                }
                label="WAN ${wan}（${l3_device}）"
            fi
            report_source="$(wan_scoped_report_token "${SOURCE_ID}" "${wan}" "$(default_source_id)")"
            report_identity="$(wan_scoped_report_token "${IDENTITY}" "${wan}" "${report_source}")"
        fi
        if [[ -n "${ROUTER_PROBE_URL}" && -n "${wan}" ]]; then
            ip="$(detect_outbound_ipv4_via_router "${wan}")"
        else
            ip="$(detect_outbound_ipv4 "${l3_device}")"
        fi || {
            printf '未能通过%s探测到公网出口 IPv4。\n' "${label}" >&2
            failure_count=$((failure_count + 1))
            continue
        }
        report_detail_output_enabled && echo "上报${label}的公网出口 IPv4 ${ip} 到 LAN Worker：${WORKER_URL}"
        curl_args=(-sS --get --connect-timeout 10 --max-time 30)
        if [[ -n "${SECRET:-}" ]]; then
            curl_args+=(-H "X-PO0-Token: ${SECRET}")
        fi
        curl_args+=(--data-urlencode "source=${report_source}")
        curl_args+=(--data-urlencode "ip=${ip}")
        curl_args+=(--data-urlencode "identity=${report_identity}")
        curl_args+=(-w $'\n%{http_code}')
        curl_args+=("${WORKER_URL}")
        response=""
        if response="$(curl "${curl_args[@]}")"; then
            http_code="${response##*$'\n'}"
            response="${response%$'\n'*}"
            if [[ "${http_code}" == 2* ]]; then
                if [[ -n "${response}" ]] && report_detail_output_enabled; then printf '%s\n' "${response}"; fi
                success_message="$(self_report_append_response_target_success "${label}的公网出口 IPv4 ${ip} 已被 LAN Worker 接收。" "${response}")"
                self_report_completed "${success_message}"
                success_count=$((success_count + 1))
            else
                if [[ -n "${response}" ]] && report_detail_output_enabled; then printf '%s\n' "${response}" >&2; fi
                self_report_incomplete "${label}的上报未被 LAN Worker 确认（HTTP ${http_code}）。"
                failure_count=$((failure_count + 1))
            fi
        else
            curl_rc=$?
            if [[ -n "${response}" ]] && report_detail_output_enabled; then printf '%s\n' "${response}" >&2; fi
            self_report_incomplete "${label}的上报未被 LAN Worker 确认（curl exit ${curl_rc}）。"
            failure_count=$((failure_count + 1))
        fi
    done <<< "${wan_targets}"
    if (( total == 0 )); then
        self_report_incomplete "没有找到需要上报的 WAN。"
        return 1
    fi
    if (( failure_count > 0 )); then
        self_report_incomplete "WAN 上报结束：成功 ${success_count} 条，失败 ${failure_count} 条。"
        return 1
    fi
    if [[ -n "${WANS}" ]]; then
        self_report_completed "WAN 上报结束：成功 ${success_count} 条，失败 0 条。"
    fi
}

report_once() {
    local worker_enabled=0 official_enabled=0 lock_rc
    local worker_rc=0 official_rc=0 mode="${REPORT_MODE:-all}"
    case "${mode}" in
        all|worker|official) ;;
        *)
            self_report_incomplete "上报通道模式无效。"
            return 1
            ;;
    esac
    if [[ "${mode}" != "official" ]] && worker_channel_requested; then
        worker_enabled=1
    fi
    if [[ "${mode}" != "worker" ]] && declare -F official_channel_enabled >/dev/null 2>&1 && official_channel_enabled; then
        official_enabled=1
    fi
    if (( worker_enabled == 0 && official_enabled == 0 )); then
        self_report_incomplete "未启用任何上报通道。"
        return 1
    fi
    if skip_report_for_wifi_ssid_if_needed; then
        return 0
    fi
    report_run_lock_acquire
    lock_rc=$?
    if (( lock_rc == 2 )); then
        self_report_completed "已有上报正在执行，本轮跳过。"
        return 0
    elif (( lock_rc != 0 )); then
        self_report_incomplete "上报互斥状态不可用，本轮未执行。"
        return 1
    fi
    # Keep the official lane first so a Worker failure cannot prevent the
    # firewall status check; the two return codes remain independent.
    if (( official_enabled == 1 )); then
        official_report_once || official_rc=$?
    fi
    if (( worker_enabled == 1 )); then
        if worker_due; then
            if worker_mark_attempt; then
                worker_report_once || worker_rc=$?
            else
                worker_rc=1
                self_report_incomplete "现有通道独立状态保存失败，未执行 Worker 上报。"
            fi
        fi
    fi
    if (( worker_rc != 0 || official_rc != 0 )); then
        if (( worker_enabled == 1 && official_enabled == 1 )); then
            if (( worker_rc != 0 && official_rc != 0 )); then
                self_report_incomplete "上报结束：官方通道失败，现有通道也失败。"
            elif (( official_rc != 0 )); then
                self_report_incomplete "上报结束：官方通道失败，现有通道已独立执行。"
            else
                self_report_incomplete "上报结束：现有通道失败，官方通道已独立执行。"
            fi
        elif (( official_enabled == 1 )); then
            self_report_incomplete "上报结束：官方通道失败。"
        else
            self_report_incomplete "上报结束：现有通道失败。"
        fi
        report_run_lock_release
        return 1
    fi
    report_run_lock_release
    return 0
}
