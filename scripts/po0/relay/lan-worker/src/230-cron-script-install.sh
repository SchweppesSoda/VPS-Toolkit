normalize_cron_minutes() {
    local minutes="${1:-}"
    local max="${2:-1440}"
    minutes="$(trim "${minutes}")"
    [[ "${max}" =~ ^[0-9]+$ && "${max}" -ge 1 ]] || max=1440
    [[ "${minutes}" =~ ^[0-9]+$ && "${minutes}" -ge 1 && "${minutes}" -le "${max}" ]] || return 1
    printf '%s\n' "${minutes}"
}

normalize_interval_seconds_to_minutes() {
    local seconds="${1:-}"
    local max_minutes="${2:-1440}"
    local max_seconds
    seconds="$(trim "${seconds}")"
    [[ "${max_minutes}" =~ ^[0-9]+$ && "${max_minutes}" -ge 1 ]] || max_minutes=1440
    max_seconds=$((max_minutes * 60))
    [[ "${seconds}" =~ ^[0-9]+$ ]] || return 1
    (( seconds >= 60 && seconds <= max_seconds )) || return 1
    (( seconds % 60 == 0 )) || return 1
    printf '%s\n' "$((seconds / 60))"
}

cron_minutes_to_seconds() {
    local minutes="${1:-}"
    [[ "${minutes}" =~ ^[0-9]+$ && "${minutes}" -ge 1 ]] || minutes=60
    printf '%s\n' "$((10#${minutes} * 60))"
}

cron_interval_label() {
    local minutes="$1"
    if (( minutes == 1440 )); then
        printf '每天'
    elif (( minutes > 1440 && minutes % 1440 == 0 )); then
        printf '每 %s 天' "$((minutes / 1440))"
    elif (( minutes == 60 )); then
        printf '每小时'
    elif (( minutes > 60 && minutes % 60 == 0 )); then
        printf '每 %s 小时' "$((minutes / 60))"
    else
        printf '每 %s 分钟' "${minutes}"
    fi
}

build_worker_cron_job() {
    local minutes="$1"
    local action="$2"
    local script_path="$3"
    local log_path="$4"
    local run_cmd schedule hours
    run_cmd="bash $(sh_quote "${script_path}") --config $(sh_quote "${CONFIG_FILE}") ${action}"
    if (( minutes < 60 )); then
        schedule="*/${minutes} * * * *"
        printf '%s %s >%s 2>&1\n' "${schedule}" "${run_cmd}" "$(sh_quote "${log_path}")"
    elif (( minutes == 60 )); then
        printf '0 * * * * %s >%s 2>&1\n' "${run_cmd}" "$(sh_quote "${log_path}")"
    elif (( minutes < 1440 && minutes % 60 == 0 )); then
        hours=$((minutes / 60))
        printf '0 */%s * * * %s >%s 2>&1\n' "${hours}" "${run_cmd}" "$(sh_quote "${log_path}")"
    elif (( minutes == 1440 )); then
        printf '0 0 * * * %s >%s 2>&1\n' "${run_cmd}" "$(sh_quote "${log_path}")"
    elif (( minutes % 60 == 0 )); then
        hours=$((minutes / 60))
        printf '0 * * * * now=$(date +\%%s); if [ $((now / 3600 \%% %s)) -eq 0 ]; then %s >%s 2>&1; fi\n' "${hours}" "${run_cmd}" "$(sh_quote "${log_path}")"
    else
        printf '* * * * now=$(date +\%%s); if [ $((now / 60 \%% %s)) -eq 0 ]; then %s >%s 2>&1; fi\n' "${minutes}" "${run_cmd}" "$(sh_quote "${log_path}")"
    fi
}

print_cron_example() {
    local requested_ddns_minutes="${1:-}"
    local requested_resource_minutes="${2:-}"
    local script_path resource_minutes ddns_minutes resource_label ddns_label
    if ! resource_minutes="$(normalize_cron_minutes "${requested_resource_minutes:-${RESOURCE_CRON_MINUTES}}" "${RESOURCE_CRON_MAX_MINUTES}")"; then
        resource_minutes="$(normalize_cron_minutes "${RESOURCE_CRON_MINUTES}" "${RESOURCE_CRON_MAX_MINUTES}" 2>/dev/null || printf '1440')"
    fi
    if ! ddns_minutes="$(normalize_cron_minutes "${requested_ddns_minutes:-${DDNS_CRON_MINUTES}}" "${DDNS_CRON_MAX_MINUTES}")"; then
        ddns_minutes="$(normalize_cron_minutes "${DDNS_CRON_MINUTES}" "${DDNS_CRON_MAX_MINUTES}" 2>/dev/null || printf '60')"
    fi
    resource_label="$(cron_interval_label "${resource_minutes}")"
    ddns_label="$(cron_minutes_to_seconds "${ddns_minutes}") 秒"
    script_path="$(script_self_path)"
    printf '%s\n' \
        "本机资源任务领取示例（${resource_label}检查 PO0 pending 任务）：" \
        "$(build_worker_cron_job "${resource_minutes}" "--run-resource" "${script_path}" "/tmp/po0-lan-resource.log")" \
        "本机 DDNS resolver 示例（${ddns_label}解析并上报 DDNS）：" \
        "$(build_worker_cron_job "${ddns_minutes}" "--run-ddns" "${script_path}" "/tmp/po0-lan-ddns.log")"
    if official_channel_enabled; then
        printf '%s\n' \
            "本机官方防火墙示例（每 10 分钟只检查本机默认出口）：" \
            "$(build_worker_cron_job 10 "--run-official-firewall --scheduled-run" "${script_path}" "/tmp/po0-lan-official-firewall.log")"
    fi
}

managed_cron_job_for_action() {
    local action="$1"
    local begin end line in_block=0
    have_cmd crontab || return 1
    begin="$(cron_begin_marker)"
    end="$(cron_end_marker)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "${begin}" ]]; then
            in_block=1
            continue
        fi
        if [[ "${line}" == "${end}" ]]; then
            in_block=0
            continue
        fi
        [[ "${in_block}" == "1" ]] || continue
        [[ "${line}" == *" ${action}"* || "${line}" == *" ${action} "* ]] || continue
        printf '%s\n' "${line}"
        return 0
    done < <(crontab -l 2>/dev/null || true)
    return 1
}

default_install_path() {
    if [[ -n "${INSTALL_PATH}" ]]; then
        printf '%s\n' "${INSTALL_PATH}"
    elif [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf '%s\n' "/usr/local/sbin/po0-lan-client"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.local/bin/po0-lan-client"
    else
        printf '%s\n' "./po0-lan-client"
    fi
}

script_source_path() {
    local script="${BASH_SOURCE[0]}"
    if [[ "${script}" != */* ]]; then
        script="$(command -v "${script}" 2>/dev/null || printf '%s' "${script}")"
    fi
    case "${script}" in
        /*)
            printf '%s\n' "${script}"
            ;;
        *)
            printf '%s/%s\n' "$(pwd -P)" "${script}"
            ;;
    esac
}

is_transient_script_path() {
    case "$1" in
        /dev/fd/*|/proc/self/fd/*|/proc/*/fd/*|/dev/stdin|*/bash|*/sh)
            return 0
            ;;
    esac
    [[ -r "$1" ]] || return 0
    return 1
}

script_self_path() {
    local script
    script="$(script_source_path)"
    if ! is_transient_script_path "${script}"; then
        printf '%s\n' "${script}"
        return 0
    fi
    default_install_path
}

install_self() {
    local src dest dir
    src="$(script_source_path)"
    dest="$(default_install_path)"
    dir="$(path_dirname "${dest}")"
    mkdir -p "${dir}" || return 1
    if ! is_transient_script_path "${src}" && [[ -r "${src}" && "${src}" != */bash && "${src}" != */sh ]]; then
        if [[ -e "${dest}" ]] && [[ "${src}" -ef "${dest}" ]]; then
            :
        else
            cp "${src}" "${dest}" || return 1
        fi
    elif have_cmd curl; then
        curl -fsSL --connect-timeout 15 --max-time 180 "${DOWNLOAD_URL}" -o "${dest}" || return 1
    elif have_cmd wget; then
        wget -q --timeout=180 -O "${dest}" "${DOWNLOAD_URL}" || return 1
    else
        printf '无法落盘：当前脚本不可复制，且系统缺少 curl/wget。\n' >&2
        return 1
    fi
    chmod 755 "${dest}" 2>/dev/null || true
    printf '%s\n' "${dest}"
}

upgrade_self_from_download() {
    local reopen_mode="${1:-}"
    local dest dir tmp legacy_scp_cmd legacy_scp_var old_version new_version changelog chmod_message
    old_version="${SCRIPT_VERSION}"
    dest="$(default_install_path)"
    dir="$(path_dirname "${dest}")"
    mkdir -p "${dir}" || return 1
    tmp="${dest}.tmp.$$"
    if have_cmd curl; then
        curl -fsSL --connect-timeout 15 --max-time 180 "${DOWNLOAD_URL}" -o "${tmp}" || {
            rm -f -- "${tmp}" 2>/dev/null || true
            return 1
        }
    elif have_cmd wget; then
        wget -q --timeout=180 -O "${tmp}" "${DOWNLOAD_URL}" || {
            rm -f -- "${tmp}" 2>/dev/null || true
            return 1
        }
    else
        printf '无法更新：系统缺少 curl/wget。\n' >&2
        return 1
    fi
    legacy_scp_cmd="scp .*"
    legacy_scp_cmd+="upload_path"
    legacy_scp_var="scp"
    legacy_scp_var+="_args"
    if grep -q -- "${legacy_scp_cmd}" "${tmp}" || grep -q -- "${legacy_scp_var}" "${tmp}" || ! grep -q -- '--resource-task-upload' "${tmp}"; then
        rm -f -- "${tmp}" 2>/dev/null || true
        printf '更新文件校验失败：下载到的脚本不是 manager stdin 上传版。\n' >&2
        return 1
    fi
    new_version="$(script_file_var "${tmp}" "SCRIPT_VERSION" 2>/dev/null || true)"
    changelog="$(script_file_changelog "${tmp}" 2>/dev/null || true)"
    chmod 755 "${tmp}" 2>/dev/null || true
    mv -f "${tmp}" "${dest}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    if chmod 755 "${dest}" 2>/dev/null; then
        chmod_message="已设置执行权限：chmod 755 ${dest}"
    else
        chmod_message="警告：已更新，但自动设置执行权限失败；请手动执行 chmod 755 ${dest}"
    fi
    printf '已更新本机命令：%s\n' "${dest}"
    printf '%s\n' "${chmod_message}"
    if [[ -n "${new_version}" ]]; then
        if [[ "${new_version}" == "${old_version}" ]]; then
            printf '版本：%s（与当前执行脚本相同）\n' "${new_version}"
        else
            printf '版本：%s -> %s\n' "${old_version}" "${new_version}"
        fi
    fi
    if [[ -n "${changelog}" ]]; then
        printf '更新内容：\n%s\n' "${changelog}"
    else
        printf '更新内容：新脚本未提供更新说明；请运行 --version 查看当前状态。\n'
    fi
    if [[ "${reopen_mode}" == "--reopen-menu" ]]; then
        read_prompt "更新完成。按回车打开新版菜单..." >/dev/null || true
        printf '正在重新打开新版菜单：%s --menu\n' "${dest}"
        exec "${BASH:-bash}" "${dest}" --config "${CONFIG_FILE}" --install-path "${dest}" --menu
        printf '重新打开新版脚本失败，请手动执行：%s --menu\n' "${dest}" >&2
        return 1
    fi
}

ensure_persistent_script() {
    local script
    script="$(script_source_path)"
    if ! is_transient_script_path "${script}"; then
        printf '%s\n' "${script}"
        return 0
    fi
    install_self
}

show_local_script_status() {
    local current install_path cron_summary
    current="$(script_source_path)"
    install_path="$(default_install_path)"
    print_panel_section "本机脚本"
    print_panel_row "脚本名称" "${SCRIPT_NAME}"
    print_panel_row "版本" "${SCRIPT_VERSION}"
    print_panel_row "发布日期" "${SCRIPT_RELEASE_DATE}"
    print_panel_row "当前脚本" "${current}"
    print_panel_row "默认安装路径" "${install_path}"
    print_panel_row "下载 URL" "${DOWNLOAD_URL}"
    cron_summary="$(cron_status_summary)"
    print_panel_row "本机轮询器" "${cron_summary}"
}

cron_begin_marker() {
    printf '# PO0_LAN_CLIENT_BEGIN %s\n' "${CONFIG_FILE}"
}

cron_end_marker() {
    printf '# PO0_LAN_CLIENT_END %s\n' "${CONFIG_FILE}"
}

write_cron_without_managed_block() {
    local begin end line in_block=0
    begin="$(cron_begin_marker)"
    end="$(cron_end_marker)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "${begin}" ]]; then
            in_block=1
            continue
        fi
        if [[ "${line}" == "${end}" ]]; then
            in_block=0
            continue
        fi
        [[ "${in_block}" == "1" ]] && continue
        printf '%s\n' "${line}"
    done
}

count_enabled_worker_targets() {
    local kind="$1"
    local line count=0
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" ]] || continue
        case "${kind}" in
            ddns)
                [[ "${TARGET_REPORT_MODE}" == "ddns" && -n "${TARGET_DOMAIN}" && -n "${TARGET_DDNS_RESOLVE_DOMAIN}" ]] && count=$((count + 1))
                ;;
            resource)
                [[ -n "${TARGET_RESOURCE_TOKEN}" ]] && count=$((count + 1))
                ;;
        esac
    done < "${CONFIG_FILE}"
    printf '%s\n' "${count}"
}
