append_manager_update_query() {
    local url="$1"
    local nonce="$2"
    local token_id="$3"
    if [[ "${url}" == *"?"* ]]; then
        printf '%s&nonce=%s&token_id=%s\n' "${url}" "${nonce}" "${token_id}"
    else
        printf '%s?nonce=%s&token_id=%s\n' "${url}" "${nonce}" "${token_id}"
    fi
}

http_header_value() {
    local headers="$1"
    local name="$2"
    awk -v name="$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]')" '
        BEGIN { FS=":" }
        {
            key=tolower($1)
            if (key == name) {
                sub(/^[^:]*:[[:space:]]*/, "", $0)
                sub(/\r$/, "", $0)
                value=$0
            }
        }
        END {
            if (value != "") print value
        }
    ' "${headers}"
}

validate_manager_update_candidate() {
    local file="$1"
    local name version
    [[ -s "${file}" ]] || { err "下载到的 manager 脚本为空。"; return 1; }
    name="$(script_file_var "${file}" "SCRIPT_NAME" 2>/dev/null || true)"
    [[ "${name}" == "${SCRIPT_NAME}" ]] || {
        err "下载到的脚本不是 ${SCRIPT_NAME}：SCRIPT_NAME=${name:-missing}"
        return 1
    }
    version="$(script_file_var "${file}" "SCRIPT_VERSION" 2>/dev/null || true)"
    [[ -n "${version}" ]] || { err "下载到的脚本缺少 SCRIPT_VERSION。"; return 1; }
    script_changelog_lines "${file}" >/dev/null || {
        err "下载到的脚本缺少 CHANGELOG 更新内容。"
        return 1
    }
    bash -n "${file}" || {
        err "下载到的脚本未通过 bash -n。"
        return 1
    }
}

install_manager_update_candidate() {
    local candidate="$1"
    local old_version="$2"
    local new_version="$3"
    local target="${MANAGER_INSTALL_PATH}"
    local backup changelog line
    mkdir -p "$(dirname "${target}")" "${BACKUP_DIR}" || return 1
    if [[ -f "${target}" ]]; then
        backup="${BACKUP_DIR}/nftables-relay-manager.sh.${old_version}.$(date '+%Y%m%d_%H%M%S')"
        cp -p -- "${target}" "${backup}" 2>/dev/null || {
            err "备份当前 manager 脚本失败：${target}"
            return 1
        }
    fi
    chmod 0755 "${candidate}" || return 1
    mv -f -- "${candidate}" "${target}" || return 1
    printf 'PO0 manager 已更新：%s\n' "${target}"
    if [[ -n "${backup:-}" ]]; then
        printf '旧脚本备份：%s\n' "${backup}"
    fi
    if [[ "${old_version}" == "${new_version}" ]]; then
        printf '版本：%s（与当前执行脚本相同）\n' "${new_version}"
    else
        printf '版本：%s -> %s\n' "${old_version}" "${new_version}"
    fi
    changelog="$(script_changelog_lines "${target}" 2>/dev/null || true)"
    if [[ -n "${changelog}" ]]; then
        printf '更新内容：\n'
        while IFS= read -r line || [[ -n "${line}" ]]; do
            printf '  %s\n' "${line}"
        done <<< "${changelog}"
    fi
}

do_upgrade_manager_from_lan() {
    local raw_url="${1:-}" url token token_id nonce request_url headers tmp
    local header_sha header_size header_version header_nonce header_sig actual_sha actual_size expected_sig message candidate_version
    ensure_layout || return 1
    load_settings 1
    [[ -n "${raw_url}" ]] || raw_url="${MANAGER_UPDATE_URL}"
    url="$(normalize_manager_update_url "${raw_url}")" || {
        err "缺少 LAN Worker manager 更新 HTTP URL。"
        return 1
    }
    token="$(resource_task_token_value 2>/dev/null || true)"
    [[ -n "${token}" ]] || {
        err "资源任务 Token 尚未生成，无法校验 LAN Worker HTTP 更新响应。"
        return 1
    }
    command -v curl >/dev/null 2>&1 || {
        err "系统缺少 curl，无法从 LAN Worker 拉取 manager 更新。"
        return 1
    }
    command -v sha256sum >/dev/null 2>&1 || {
        err "系统缺少 sha256sum，无法校验 manager 更新。"
        return 1
    }
    token_id="$(sha256_string "${token}")" || {
        err "系统缺少 SHA-256 工具，无法生成 token_id。"
        return 1
    }
    nonce="$(random_update_nonce)"
    request_url="$(append_manager_update_query "${url}" "${nonce}" "${token_id}")"
    make_temp_file "${MANAGER_INSTALL_PATH}.headers" || return 1
    headers="${TEMP_FILE_RESULT}"
    make_temp_file "${MANAGER_INSTALL_PATH}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    printf '从 LAN Worker 拉取 PO0 manager：%s\n' "${url}"
    curl -fsSL --connect-timeout 15 --max-time 120 -D "${headers}" -o "${tmp}" "${request_url}" || {
        err "从 LAN Worker 拉取 manager 更新失败。"
        return 1
    }
    header_sha="$(http_header_value "${headers}" "X-PO0-Manager-SHA256")"
    header_size="$(http_header_value "${headers}" "X-PO0-Manager-Size")"
    header_version="$(http_header_value "${headers}" "X-PO0-Manager-Version")"
    header_nonce="$(http_header_value "${headers}" "X-PO0-Manager-Nonce")"
    header_sig="$(http_header_value "${headers}" "X-PO0-Manager-HMAC")"
    [[ "${header_nonce}" == "${nonce}" ]] || { err "更新响应 nonce 不匹配。"; return 1; }
    [[ "${header_sha}" =~ ^[A-Fa-f0-9]{64}$ ]] || { err "更新响应缺少有效 SHA-256。"; return 1; }
    [[ "${header_size}" =~ ^[0-9]+$ ]] || { err "更新响应缺少有效 size。"; return 1; }
    [[ -n "${header_version}" ]] || { err "更新响应缺少版本号。"; return 1; }
    [[ "${header_sig}" =~ ^[A-Fa-f0-9]{64}$ ]] || { err "更新响应缺少有效 HMAC。"; return 1; }
    actual_sha="$(sha256_file_full "${tmp}")" || return 1
    actual_size="$(wc -c < "${tmp}" | tr -d '[:space:]')"
    [[ "${actual_sha}" == "${header_sha}" && "${actual_size}" == "${header_size}" ]] || {
        err "更新脚本 SHA-256 或 size 与响应头不一致。"
        return 1
    }
    message="${nonce}|${header_sha}|${header_size}|${header_version}"
    expected_sig="$(hmac_sha256_hex "${token}" "${message}")" || {
        err "系统缺少 openssl 或 python，无法校验 HMAC。"
        return 1
    }
    [[ "${expected_sig}" == "${header_sig}" ]] || {
        err "更新响应 HMAC 校验失败，已拒绝安装。"
        return 1
    }
    validate_manager_update_candidate "${tmp}" || return 1
    candidate_version="$(script_file_var "${tmp}" "SCRIPT_VERSION" 2>/dev/null)" || return 1
    [[ "${header_version}" == "${candidate_version}" ]] || {
        err "更新响应版本号与脚本 SCRIPT_VERSION 不一致。"
        return 1
    }
    install_manager_update_candidate "${tmp}" "${SCRIPT_VERSION}" "${candidate_version}" || return 1
    if [[ -r /dev/tty && -w /dev/tty ]]; then
        if confirm_yes "是否使用更新后的脚本刷新专用受限 SSH wrapper"; then
            bash "${MANAGER_INSTALL_PATH}" --refresh-report-key-wrapper
        fi
    fi
}

current_script_changelog() {
    local script_path
    script_path="$(current_script_path 2>/dev/null || true)"
    script_changelog_lines "${script_path}"
}

script_build_label() {
    local version="${1:-${SCRIPT_VERSION}}"
    if [[ "${version}" == *"+"* ]]; then
        printf '%s\n' "${version#*+}"
    else
        printf '未标识\n'
    fi
}

do_show_version() {
    local script_path build_label
    script_path="$(current_script_path 2>/dev/null || true)"
    build_label="$(script_build_label)"
    print_panel_section "脚本版本"
    print_panel_row "脚本名称" "${SCRIPT_NAME}"
    print_panel_row "版本" "${SCRIPT_VERSION}"
    print_panel_row "构建标识" "${build_label}"
    print_panel_row "发布日期" "${SCRIPT_RELEASE_DATE}"
    print_panel_row "当前脚本" "${script_path:-unknown}"
    print_panel_row "默认安装路径" "${MANAGER_INSTALL_PATH}"
    print_panel_row "下载 URL" "${MANAGER_DOWNLOAD_URL}"
}

do_show_changelog() {
    local changes line build_label
    changes="$(current_script_changelog 2>/dev/null || true)"
    build_label="$(script_build_label)"
    printf '%s\n' \
        "script_name=${SCRIPT_NAME}" \
        "version=${SCRIPT_VERSION}" \
        "build=${build_label}" \
        "release_date=${SCRIPT_RELEASE_DATE}" \
        "changes:"
    if [[ -n "${changes}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            printf '  %s\n' "${line}"
        done <<< "${changes}"
    else
        printf '  未提供当前版本更新内容。\n'
    fi
}

do_show_version_panel() {
    local changes line
    print_title "脚本版本"
    print_panel_section "版本信息"
    print_panel_row "脚本名称" "${SCRIPT_NAME}"
    print_panel_row "版本" "${C_GREEN}${SCRIPT_VERSION}${C_RESET}"
    print_panel_row "构建标识" "$(script_build_label)"
    print_panel_row "发布日期" "${SCRIPT_RELEASE_DATE}"
    print_panel_row "安装路径" "${MANAGER_INSTALL_PATH}"
    print_panel_row "下载 URL" "${MANAGER_DOWNLOAD_URL}"
    print_panel_section "当前版本更新内容"
    changes="$(current_script_changelog 2>/dev/null || true)"
    if [[ -n "${changes}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            print_panel_note "${line}"
        done <<< "${changes}"
    else
        print_panel_note "未提供当前版本更新内容"
    fi
}

do_upgrade_manager_from_lan_interactive() {
    local reopen_mode="${1:-}" prompt_label url
    prompt_label="LAN Worker manager 更新 HTTP URL（非 80 端口请加 :端口）"
    load_settings 1
    if [[ -n "${MANAGER_UPDATE_URL}" ]]; then
        url="$(prompt_with_default "${prompt_label}" "${MANAGER_UPDATE_URL}")"
    else
        url="$(read_prompt "${prompt_label}: ")" || return 1
    fi
    [[ -n "$(trim "${url}")" ]] || { err "更新 URL 不能为空。"; return 1; }
    url="$(normalize_manager_update_url "${url}")" || return 1
    MANAGER_UPDATE_URL="${url}"
    save_settings || return 1
    do_upgrade_manager_from_lan "${url}" || return 1
    if [[ "${reopen_mode}" == "--reopen-menu" ]]; then
        read_prompt "更新完成。按回车打开新版菜单..." >/dev/null || true
        printf '正在重新打开新版菜单：%s\n' "${MANAGER_INSTALL_PATH}"
        exec "${BASH:-bash}" "${MANAGER_INSTALL_PATH}"
        printf '重新打开新版脚本失败，请手动执行：bash %s\n' "${MANAGER_INSTALL_PATH}" >&2
        return 1
    fi
}

do_manage_version_update() {
    local choice
    while true; do
        menu_clear_screen
        do_show_version_panel
        print_menu_section "更新"
        print_menu_pair 1 "从 LAN Worker HTTP 更新 manager" 2 "显示当前版本更新内容"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-2]: " || return 0
        case "${choice}" in
            1) do_upgrade_manager_from_lan_interactive --reopen-menu || pause_before_return ;;
            2) do_show_changelog; pause_before_return ;;
            0) return 0 ;;
            "") ;;
            *) err "无效选择。"; pause_before_return ;;
        esac
    done
}
