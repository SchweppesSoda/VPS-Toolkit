install_manager_self() {
    local target="${1:-${MANAGER_INSTALL_PATH}}"
    local source tmp
    source="$(current_script_path 2>/dev/null || true)"
    if [[ -n "${source}" && "${source}" == "${target}" && -f "${target}" ]]; then
        chmod 0755 "${target}" 2>/dev/null || true
        printf '%s\n' "${target}"
        return 0
    fi
    mkdir -p "$(dirname "${target}")" || return 1
    tmp="${target}.tmp.$$"
    if [[ -n "${source}" ]] && ! is_transient_script_path "${source}"; then
        cp -- "${source}" "${tmp}" || return 1
    else
        err "当前脚本来自 stdin/临时路径，不能可靠落盘。请先把 nftables-relay-manager.sh 上传到 ${target} 后再运行。"
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    fi
    chmod 0755 "${tmp}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    mv -f -- "${tmp}" "${target}" || return 1
    printf '%s\n' "${target}"
}

ensure_persistent_manager_script() {
    local source
    source="$(current_script_path 2>/dev/null || true)"
    if [[ -n "${source}" ]] && ! is_transient_script_path "${source}"; then
        printf '%s\n' "${source}"
        return 0
    fi
    warn "当前主控脚本来自临时路径，安装 cron 前需要先落盘。" >&2
    install_manager_self "${MANAGER_INSTALL_PATH}"
}
