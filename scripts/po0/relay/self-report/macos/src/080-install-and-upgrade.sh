default_install_path() {
    if [[ -n "${INSTALL_PATH}" ]]; then
        printf '%s\n' "${INSTALL_PATH}"
    elif [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf '%s\n' "/usr/local/sbin/po0-self-report"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.local/bin/po0-self-report"
    else
        printf '%s\n' "./po0-self-report"
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
    printf '%s\n' "${dest}"
}

upgrade_self_from_download() {
    local reopen_mode="${1:-}" dest dir tmp new_version changelog chmod_message
    dest="$(default_install_path)"
    dir="$(dirname "${dest}")"
    mkdir -p "${dir}" || return 1
    if command -v mktemp >/dev/null 2>&1; then
        tmp="$(mktemp "${dir}/.po0-self-report.XXXXXX")" || return 1
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
    if ! grep -q 'po0-outbound-ip-report-macos.sh' "${tmp}" || ! grep -q 'PO0 自上报客户端（macOS）' "${tmp}"; then
        rm -f "${tmp}" 2>/dev/null || true
        printf '更新文件校验失败：下载到的脚本不是 Self-report macOS 客户端。\n' >&2
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
    printf '已更新 Self-report 客户端脚本：%s\n' "${dest}"
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
    if [[ "${reopen_mode}" == "--reopen-menu" ]]; then
        read_prompt "更新完成。按回车打开新版菜单..." >/dev/null || true
        printf '正在重新打开新版菜单：%s --menu\n' "${dest}"
        exec "${BASH:-bash}" "${dest}" --config "${CONFIG_FILE}" --install-path "${dest}" --menu
        printf '重新打开新版脚本失败，请手动执行：%s --menu\n' "${dest}" >&2
        return 1
    fi
}
