remove_file_if_exists() {
    local label="$1"
    local path="$2"
    [[ -n "${path}" ]] || return 0
    if [[ -e "${path}" || -L "${path}" ]]; then
        if rm -f -- "${path}"; then
            printf '已删除%s：%s\n' "${label}" "${path}"
        else
            printf '删除%s失败：%s\n' "${label}" "${path}" >&2
            return 1
        fi
    else
        printf '%s不存在：%s\n' "${label}" "${path}"
    fi
}

remove_cron_for_uninstall() {
    if command -v crontab >/dev/null 2>&1 || launchd_supported; then
        remove_cron
    else
        echo "未找到 crontab 命令，且当前环境不能使用 macOS launchd，跳过定时上报删除。"
    fi
}

uninstall_self_report_interactive() {
    local install_path log_path remove_data errors=0
    install_path="$(default_install_path)"
    log_path="$(self_report_log_path)"
    echo "卸载会删除本脚本管理的定时上报和本机安装脚本。"
    echo "本机安装脚本：${install_path}"
    echo "配置文件和日志默认保留，后续可选择是否一起删除。"
    if ! prompt_yes_no "确认卸载 self-report 客户端" "n"; then
        echo "已取消。"
        return 2
    fi
    remove_cron_for_uninstall || errors=1
    remove_file_if_exists "本机脚本" "${install_path}" || errors=1
    if prompt_yes_no "是否同时删除配置文件和日志" "n"; then
        remove_data="1"
    else
        remove_data="0"
    fi
    if [[ "${remove_data}" == "1" ]]; then
        remove_file_if_exists "配置文件" "${CONFIG_FILE}" || errors=1
        remove_file_if_exists "日志文件" "${log_path}" || errors=1
    else
        echo "已保留配置文件：${CONFIG_FILE}"
        echo "已保留日志文件：${log_path}"
    fi
    if [[ "${errors}" == "1" ]]; then
        self_report_incomplete "卸载已执行，但有项目删除失败。"
        return 1
    fi
    self_report_completed "卸载已完成。"
}
