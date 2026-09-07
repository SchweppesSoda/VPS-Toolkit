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
    if [[ "$(script_file_var "${tmp}" SCRIPT_NAME)" != "${SCRIPT_NAME}" ]] || ! bash -n "${tmp}" || ! script_file_changelog "${tmp}" >/dev/null; then
        rm -f -- "${tmp}"
        printf '更新文件身份或语法校验失败。\n' >&2
        return 1
    fi
    ensure_worker_retirement_backup || return 1
    [[ ! -f "${dest}" ]] || cp -p "${dest}" "${dest}.pre-update" || return 1
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
