canonical_install_path() {
    if [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf '%s\n' "/usr/local/sbin/po0-outbound-ip-report"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.local/bin/po0-outbound-ip-report"
    else
        printf '%s\n' "./po0-outbound-ip-report"
    fi
}

legacy_install_path() {
    if [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf '%s\n' "/usr/local/sbin/po0-self-report"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.local/bin/po0-self-report"
    else
        printf '%s\n' "./po0-self-report"
    fi
}

default_install_path() {
    if [[ -n "${INSTALL_PATH}" ]]; then
        printf '%s\n' "${INSTALL_PATH}"
    else
        canonical_install_path
    fi
}

path_dir_in_path() {
    local dir="$1" rest item
    [[ -n "${dir}" ]] || return 1
    rest="${PATH:-}"
    while true; do
        case "${rest}" in
            *:*)
                item="${rest%%:*}"
                rest="${rest#*:}"
                ;;
            *)
                item="${rest}"
                rest=""
                ;;
        esac
        [[ "${item}" == "${dir}" ]] && return 0
        [[ -n "${rest}" ]] || break
    done
    return 1
}

shell_path_export_line() {
    local dir="$1" rel
    if [[ -n "${HOME:-}" ]]; then
        case "${dir}" in
            "${HOME}"/*)
                rel="${dir#"${HOME}/"}"
                printf 'export PATH="$HOME/%s:$PATH"\n' "${rel}"
                return 0
                ;;
        esac
    fi
    printf 'export PATH="%s:$PATH"\n' "${dir}"
}

shell_path_profile_path() {
    [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]] && return 1
    [[ -n "${HOME:-}" ]] || return 1
    printf '%s\n' "${HOME}/.zprofile"
}

shell_profile_has_path_dir() {
    local profile="$1" dir="$2" line
    [[ -f "${profile}" ]] || return 1
    line="$(shell_path_export_line "${dir}")"
    grep -Fqx "${line}" "${profile}" 2>/dev/null
}

append_shell_path_profile() {
    local profile="$1" dir="$2" line
    line="$(shell_path_export_line "${dir}")"
    shell_profile_has_path_dir "${profile}" "${dir}" && return 0
    mkdir -p "$(path_dirname "${profile}")" || return 1
    {
        if [[ -s "${profile}" ]]; then
            printf '\n'
        fi
        printf '# PO0 Outbound IP Report command\n'
        printf '%s\n' "${line}"
    } >> "${profile}"
}

ensure_install_path_visible() {
    local dest="$1" prompt_mode="${2:-0}" dir profile line
    dir="$(path_dirname "${dest}")"
    case "${dir}" in
        /*) ;;
        *) return 0 ;;
    esac
    path_dir_in_path "${dir}" && return 0

    profile="$(shell_path_profile_path 2>/dev/null || true)"
    line="$(shell_path_export_line "${dir}")"
    printf '提示：已安装 PO0 Outbound IP Report 命令：%s\n' "${dest}" >&2
    printf '提示：当前终端 PATH 尚未包含安装目录：%s\n' "${dir}" >&2
    printf '本次可直接运行：%s --menu\n' "${dest}" >&2
    if [[ -n "${profile}" ]]; then
        printf '如需直接运行 po0-outbound-ip-report，可将以下行加入 %s：\n%s\n' "${profile}" "${line}" >&2
    else
        printf '如需直接运行 po0-outbound-ip-report，请把 %s 加入当前用户 shell PATH。\n' "${dir}" >&2
    fi

    [[ "${prompt_mode}" == "1" ]] || return 0
    [[ -n "${profile}" ]] || return 0
    [[ -r /dev/tty && -w /dev/tty ]] || return 0
    if prompt_yes_no "是否现在写入 ${profile}" "y"; then
        append_shell_path_profile "${profile}" "${dir}" || {
            printf '写入 PATH 配置失败：%s\n' "${profile}" >&2
            return 1
        }
        printf '已写入 PATH 配置：%s\n' "${profile}" >&2
        printf '请重新打开终端，或执行：source %s\n' "${profile}" >&2
    fi
}

is_legacy_install_path() {
    local path="$1" legacy
    legacy="$(legacy_install_path)"
    [[ "${path}" == "${legacy}" || "${path##*/}" == "po0-self-report" ]]
}

same_path() {
    local left="$1" right="$2"
    [[ -n "${left}" && -n "${right}" ]] || return 1
    [[ "${left}" == "${right}" ]] && return 0
    [[ -e "${left}" && -e "${right}" && "${left}" -ef "${right}" ]]
}

remove_legacy_command_path() {
    local dest="$1" legacy
    legacy="$(legacy_install_path)"
    [[ -n "${legacy}" && -n "${dest}" ]] || return 0
    same_path "${legacy}" "${dest}" && return 0
    [[ -e "${legacy}" || -L "${legacy}" ]] || return 0
    rm -f -- "${legacy}" 2>/dev/null || {
        printf 'Warning: failed to remove legacy command path: %s\n' "${legacy}" >&2
        return 1
    }
}

migrate_legacy_file_to_canonical() {
    local legacy="$1" canonical="$2" mode="${3:-}"
    [[ -n "${legacy}" && -n "${canonical}" ]] || return 0
    same_path "${legacy}" "${canonical}" && return 0
    [[ -e "${legacy}" || -L "${legacy}" ]] || return 0
    mkdir -p "$(dirname "${canonical}")" 2>/dev/null || return 1
    if [[ ! -e "${canonical}" ]]; then
        mv -f -- "${legacy}" "${canonical}" 2>/dev/null || {
            cp -p -- "${legacy}" "${canonical}" 2>/dev/null && rm -f -- "${legacy}" 2>/dev/null
        } || return 1
    else
        rm -f -- "${legacy}" 2>/dev/null || return 1
    fi
    [[ -n "${mode}" ]] && chmod "${mode}" "${canonical}" 2>/dev/null || true
}

merge_legacy_log_to_canonical() {
    local legacy="$1" canonical="$2"
    [[ -n "${legacy}" && -n "${canonical}" ]] || return 0
    same_path "${legacy}" "${canonical}" && return 0
    [[ -e "${legacy}" || -L "${legacy}" ]] || return 0
    mkdir -p "$(dirname "${canonical}")" 2>/dev/null || return 1
    if [[ ! -e "${canonical}" ]]; then
        mv -f -- "${legacy}" "${canonical}" 2>/dev/null || {
            cp -p -- "${legacy}" "${canonical}" 2>/dev/null && rm -f -- "${legacy}" 2>/dev/null
        } || return 1
        return 0
    fi
    if [[ -s "${legacy}" ]]; then
        {
            printf '\n# migrated from %s at %s\n' "${legacy}" "$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || true)"
            cat "${legacy}"
        } >> "${canonical}" 2>/dev/null || return 1
    fi
    rm -f -- "${legacy}" 2>/dev/null || return 1
}

cleanup_legacy_self_report_artifacts() {
    local dest="${1:-$(default_install_path)}" failed=0
    if [[ "${CONFIG_FILE_EXPLICIT:-0}" != "1" ]]; then
        migrate_legacy_file_to_canonical "$(legacy_config_file)" "$(canonical_config_file)" "600" || failed=1
    fi
    merge_legacy_log_to_canonical "$(legacy_self_report_log_path)" "$(self_report_log_path)" || failed=1
    migrate_legacy_file_to_canonical "$(legacy_ip_check_state_file)" "$(ip_check_state_file)" || failed=1
    remove_legacy_command_path "${dest}" || failed=1
    return "${failed}"
}

run_updated_script() {
    local dest="$1"
    shift
    if [[ "${CONFIG_FILE_EXPLICIT:-0}" == "1" ]]; then
        "${BASH:-bash}" "${dest}" --config "${CONFIG_FILE}" "$@"
    else
        "${BASH:-bash}" "${dest}" "$@"
    fi
}

exec_updated_script() {
    local dest="$1"
    shift
    if [[ "${CONFIG_FILE_EXPLICIT:-0}" == "1" ]]; then
        exec "${BASH:-bash}" "${dest}" --config "${CONFIG_FILE}" "$@"
    else
        exec "${BASH:-bash}" "${dest}" "$@"
    fi
}

install_self() {
    local dest dir source
    dest="$(default_install_path)"
    dir="$(dirname "${dest}")"
    source="${BASH_SOURCE[0]}"
    mkdir -p "${dir}" || return 1
    if [[ -r "${source}" && "${source}" != /dev/fd/* && "${source}" != /proc/* && "${source}" != /dev/stdin ]]; then
        if [[ -e "${dest}" && "${source}" -ef "${dest}" ]]; then
            :
        else
            cp "${source}" "${dest}" || return 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --max-time 120 "${DOWNLOAD_URL}" -o "${dest}" || return 1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 120 -O "${dest}" "${DOWNLOAD_URL}" || return 1
    else
        echo "缺少 curl/wget，无法把管道运行的脚本落盘。" >&2
        return 1
    fi
    chmod 755 "${dest}" || true
    cleanup_legacy_self_report_artifacts "${dest}" || true
    ensure_install_path_visible "${dest}" "${PO0_PATH_PROMPT:-0}" || true
    printf '%s\n' "${dest}"
}

refresh_schedule_after_script_update() {
    local dest="$1"
    if cron_managed_block_exists || { launchd_supported && { [[ -f "$(launchd_plist_path)" ]] || legacy_launchd_plist_exists; }; }; then
        if macos_schedule_refresh_current "${dest}"; then
            printf '定时上报已指向标准脚本路径，未刷新：%s\n' "${dest}"
        elif run_updated_script "${dest}" --install-launchd >/dev/null 2>&1; then
            printf '已刷新定时上报到标准脚本路径：%s\n' "${dest}"
        else
            printf '警告：脚本已更新，但自动刷新定时上报失败；请运行 %s --install-launchd。\n' "${dest}" >&2
        fi
    fi
}

invoke_legacy_path_self_heal() {
    local reopen_menu="${1:-0}" source dest
    source="$(current_script_source_file 2>/dev/null || true)"
    [[ -n "${source}" ]] || return 1
    is_legacy_install_path "${source}" || return 1
    dest="$(default_install_path)"
    [[ "${dest}" != "${source}" ]] || return 1
    install_self >/dev/null || return 1
    refresh_schedule_after_script_update "${dest}" || true
    printf '已迁移 PO0 Outbound IP Report 客户端脚本到标准安装路径：%s\n' "${dest}"
    if [[ "${reopen_menu}" == "1" ]]; then
        printf '正在从标准安装路径重新打开新版菜单：%s --menu\n' "${dest}"
        exec_updated_script "${dest}" --menu
    fi
    return 0
}

upgrade_self_from_download() {
    local reopen_mode="${1:-}" dest dir tmp new_version changelog chmod_message
    dest="$(default_install_path)"
    dir="$(dirname "${dest}")"
    mkdir -p "${dir}" || return 1
    if command -v mktemp >/dev/null 2>&1; then
        tmp="$(mktemp "${dir}/.po0-outbound-ip-report.XXXXXX")" || return 1
    else
        tmp="${dest}.tmp.$$"
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --max-time 120 "${DOWNLOAD_URL}" -o "${tmp}" || {
            rm -f "${tmp}" 2>/dev/null || true
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 120 -O "${tmp}" "${DOWNLOAD_URL}" || {
            rm -f "${tmp}" 2>/dev/null || true
            return 1
        }
    else
        rm -f "${tmp}" 2>/dev/null || true
        printf '无法更新：系统缺少 curl/wget。\n' >&2
        return 1
    fi
    if ! grep -q 'po0-outbound-ip-report-macos.sh' "${tmp}" || ! grep -q 'PO0 自上报客户端（macOS）' "${tmp}" || ! grep -q '^SCRIPT_NAME="po0-outbound-ip-report"' "${tmp}"; then
        rm -f "${tmp}" 2>/dev/null || true
        printf '更新文件校验失败：下载到的脚本不是 PO0 Outbound IP Report macOS 客户端。\n' >&2
        return 1
    fi
    if awk '/^default_install_path\(\)/{flag=1} flag{print; if ($0 ~ /^}/) exit}' "${tmp}" | grep -q 'po0-self-report'; then
        rm -f "${tmp}" 2>/dev/null || true
        printf '更新文件校验失败：下载脚本默认安装路径仍指向 po0-self-report。\n' >&2
        return 1
    fi
    if ! bash -n "${tmp}"; then
        rm -f "${tmp}" 2>/dev/null || true
        printf '更新文件校验失败：下载到的脚本未通过 bash -n。\n' >&2
        return 1
    fi
    new_version="$(script_file_var "${tmp}" "SCRIPT_VERSION")"
    changelog="$(script_file_changelog "${tmp}")"
    mv -f "${tmp}" "${dest}" || {
        rm -f "${tmp}" 2>/dev/null || true
        return 1
    }
    if chmod 755 "${dest}" 2>/dev/null; then
        chmod_message="已设置执行权限：chmod 755 ${dest}"
    else
        chmod_message="警告：已更新，但自动设置执行权限失败；请手动执行 chmod 755 ${dest}"
    fi
    cleanup_legacy_self_report_artifacts "${dest}" || true
    if [[ "${reopen_mode}" == "--reopen-menu" ]]; then
        ensure_install_path_visible "${dest}" "1" || true
    else
        ensure_install_path_visible "${dest}" "0" || true
    fi
    printf '已更新 PO0 Outbound IP Report 客户端脚本：%s\n' "${dest}"
    printf '下载 URL：%s\n' "${DOWNLOAD_URL}"
    printf '%s\n' "${chmod_message}"
    if [[ -n "${new_version}" ]]; then
        if [[ "${new_version}" == "${SCRIPT_VERSION}" ]]; then
            printf '版本：%s（与当前执行脚本相同）\n' "${new_version}"
        else
            printf '版本：%s -> %s\n' "${SCRIPT_VERSION}" "${new_version}"
        fi
    else
        printf '版本：无法读取新脚本版本。\n'
    fi
    if [[ -n "${changelog}" ]]; then
        printf '更新内容：\n%s\n' "${changelog}"
    else
        printf '更新内容：新脚本未提供更新说明。\n'
    fi
    refresh_schedule_after_script_update "${dest}" || true
    if [[ "${reopen_mode}" == "--reopen-menu" ]]; then
        read_prompt "更新完成。按回车打开新版菜单..." >/dev/null || true
        printf '正在重新打开新版菜单：%s --menu\n' "${dest}"
        exec_updated_script "${dest}" --menu
        printf '重新打开新版脚本失败，请手动执行：%s --menu\n' "${dest}" >&2
        return 1
    fi
}
