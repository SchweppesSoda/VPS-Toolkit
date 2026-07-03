#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/bin:/bin:${PATH:-}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP_DIRS=()
cleanup() {
    local dir
    for dir in "${TMP_DIRS[@]}"; do
        rm -rf "${dir}"
    done
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_no_refresh() {
    "$@" || fail "expected no refresh: $*"
}

assert_refresh() {
    if "$@"; then
        fail "expected refresh: $*"
    fi
}

run_linux_cases() {
    local tmp_root cron_file dest run_cmd job call_log output
    tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/po0-linux-refresh-test.XXXXXX")"
    TMP_DIRS+=("${tmp_root}")

    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/linux/src/010-core-string-path-config.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/linux/src/020-ui-rendering.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/linux/src/030-version-and-script-metadata.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/linux/src/040-prompt-and-input-helpers.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/linux/src/050-config-device-defaults.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/linux/src/060-worker-url-interval-state.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/linux/src/080-install-and-upgrade.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/linux/src/090-cron-schedule-management.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/linux/src/120-schedule-status-control.sh"

    command -v linux_schedule_refresh_current >/dev/null 2>&1 || fail "missing linux_schedule_refresh_current"

    CONFIG_FILE="${tmp_root}/settings.env"
    LOG_FILE="${tmp_root}/report.log"
    CRON_MINUTES="60"
    SCHEDULE_PAUSED="0"
    dest="${tmp_root}/po0-outbound-ip-report"
    cron_file="${tmp_root}/crontab"
    call_log="${tmp_root}/run-updated.log"

    self_report_log_path() {
        printf '%s\n' "${LOG_FILE}"
    }

    crontab() {
        case "${1:-}" in
            -l) cat "${cron_file}" ;;
            *) fail "unexpected crontab call: $*" ;;
        esac
    }

    run_updated_script() {
        printf '%s\n' "$*" >> "${call_log}"
        return "${RUN_UPDATED_STATUS:-0}"
    }

    run_cmd="bash $(sh_quote "${dest}") --config $(sh_quote "${CONFIG_FILE}") >$(sh_quote "$(self_report_log_path)") 2>&1"
    job="$(build_cron_job "${CRON_MINUTES}" "${run_cmd}")"
    {
        cron_begin_marker
        printf '# paused=0\n'
        printf '# interval_minutes=60\n'
        printf '%s\n' "${job}"
        cron_end_marker
    } > "${cron_file}"
    assert_no_refresh linux_schedule_refresh_current "${dest}"
    : > "${call_log}"
    output="$(refresh_schedule_after_script_update "${dest}" 2>&1)"
    [[ ! -s "${call_log}" ]] || fail "linux current entrypoint should not call run_updated_script"
    [[ "${output}" == *"未刷新"* ]] || fail "linux current entrypoint should print no-refresh message"

    sed "s#${dest}#${tmp_root}/po0-self-report#" "${cron_file}" > "${cron_file}.legacy"
    mv "${cron_file}.legacy" "${cron_file}"
    assert_refresh linux_schedule_refresh_current "${dest}"
    : > "${call_log}"
    RUN_UPDATED_STATUS=0 output="$(refresh_schedule_after_script_update "${dest}" 2>&1)"
    [[ "$(cat "${call_log}")" == "${dest} --install-cron" ]] || fail "linux stale entrypoint should call --install-cron"
    [[ "${output}" == *"已刷新定时上报到标准脚本路径"* ]] || fail "linux stale entrypoint should print refreshed message"

    : > "${call_log}"
    RUN_UPDATED_STATUS=1 output="$(refresh_schedule_after_script_update "${dest}" 2>&1)"
    [[ "$(cat "${call_log}")" == "${dest} --install-cron" ]] || fail "linux failed entrypoint should still call --install-cron"
    [[ "${output}" == *"自动刷新 cron 失败"* ]] || fail "linux failed entrypoint should print warning"
    unset RUN_UPDATED_STATUS
}

run_macos_cases() {
    local tmp_root dest plist call_log output
    tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/po0-macos-refresh-test.XXXXXX")"
    TMP_DIRS+=("${tmp_root}")

    HOME="${tmp_root}/home"
    mkdir -p "${HOME}/Library/LaunchAgents"

    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/macos/src/010-core-string-path-config.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/macos/src/020-ui-rendering.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/macos/src/030-version-and-script-metadata.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/macos/src/040-prompt-and-input-helpers.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/macos/src/050-config-device-defaults.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/macos/src/060-worker-url-interval-state.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/macos/src/080-install-and-upgrade.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/macos/src/090-cron-block-helpers.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/macos/src/100-launchd-scheduler.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/macos/src/110-scheduler-install-remove.sh"
    # shellcheck source=/dev/null
    source "${repo_root}/scripts/po0/relay/self-report/macos/src/140-schedule-status-control.sh"

    command -v macos_schedule_refresh_current >/dev/null 2>&1 || fail "missing macos_schedule_refresh_current"

    is_macos() { return 0; }
    launchctl() { return 0; }
    crontab() { return 1; }

    CONFIG_FILE="${tmp_root}/settings.env"
    LOG_FILE="${tmp_root}/report.log"
    CRON_MINUTES="60"
    SCHEDULE_PAUSED="0"
    NOTIFY="0"
    dest="${tmp_root}/po0-outbound-ip-report-macos.sh"
    plist="$(launchd_plist_path)"
    call_log="${tmp_root}/run-updated.log"

    self_report_log_path() {
        printf '%s\n' "${LOG_FILE}"
    }

    run_updated_script() {
        printf '%s\n' "$*" >> "${call_log}"
        return "${RUN_UPDATED_STATUS:-0}"
    }

    write_launchd_plist "${plist}" "${dest}" "$(cron_minutes_to_seconds "${CRON_MINUTES}")"
    assert_no_refresh macos_schedule_refresh_current "${dest}"
    : > "${call_log}"
    output="$(refresh_schedule_after_script_update "${dest}" 2>&1)"
    [[ ! -s "${call_log}" ]] || fail "macOS current entrypoint should not call run_updated_script"
    [[ "${output}" == *"未刷新"* ]] || fail "macOS current entrypoint should print no-refresh message"

    grep -v -- '--scheduled-run' "${plist}" > "${plist}.stale"
    mv "${plist}.stale" "${plist}"
    assert_refresh macos_schedule_refresh_current "${dest}"
    : > "${call_log}"
    RUN_UPDATED_STATUS=0 output="$(refresh_schedule_after_script_update "${dest}" 2>&1)"
    [[ "$(cat "${call_log}")" == "${dest} --install-launchd" ]] || fail "macOS stale entrypoint should call --install-launchd"
    [[ "${output}" == *"已刷新定时上报到标准脚本路径"* ]] || fail "macOS stale entrypoint should print refreshed message"

    : > "${call_log}"
    RUN_UPDATED_STATUS=1 output="$(refresh_schedule_after_script_update "${dest}" 2>&1)"
    [[ "$(cat "${call_log}")" == "${dest} --install-launchd" ]] || fail "macOS failed entrypoint should still call --install-launchd"
    [[ "${output}" == *"自动刷新定时上报失败"* ]] || fail "macOS failed entrypoint should print warning"
    unset RUN_UPDATED_STATUS
}

run_linux_cases
run_macos_cases
printf 'Self-report refresh policy tests passed.\n'
