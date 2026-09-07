
# The Worker lane has its own attempt clock.  It is intentionally separate
# from the official firewall state so a ten-minute official wake-up cannot
# turn the existing hourly Worker report into a ten-minute report.

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

report_once() {
    local lock_rc official_rc=0
    [[ "${REPORT_MODE:-official}" != worker ]] || { printf '自建上报已退役。\n'; return 0; }
    if [[ "${SCHEDULED_RUN:-0}" == 1 ]]; then
        schedule_paused && return 0
        channel_auto_enabled official || return 0
        if [[ "${NETWORK_CHANGED:-0}" == 1 ]]; then
            case "${OFFICIAL_NETWORK_ENABLED:-1}" in 0|false|no|off) return 0 ;; esac
        else
            case "${OFFICIAL_TIMER_ENABLED:-1}" in 0|false|no|off) return 0 ;; esac
        fi
    fi
    official_channel_enabled || { self_report_completed '尚未配置官方上报目标，本轮跳过。'; return 0; }
    skip_report_for_wifi_ssid_if_needed && return 0
    report_run_lock_acquire; lock_rc=$?
    if (( lock_rc == 2 )); then self_report_completed '已有上报正在执行，本轮跳过。'; return 0; fi
    (( lock_rc == 0 )) || { self_report_incomplete '上报互斥状态不可用，本轮未执行。'; return 1; }
    official_report_once || official_rc=$?
    report_run_lock_release
    return "$official_rc"
}
