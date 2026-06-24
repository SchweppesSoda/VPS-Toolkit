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

full_backup_default_path() {
    local prefix="" stamp
    validate_node_name "${NODE_NAME}" || NODE_NAME=""
    [[ -n "${NODE_NAME}" ]] && prefix="${NODE_NAME}-"
    stamp="$(date '+%Y%m%d_%H%M%S')"
    printf '%s/%spo0-manager-full-backup-%s.tar.gz\n' "${BACKUP_DIR}" "${prefix}" "${stamp}"
}

absolute_output_path() {
    local path="$1"
    case "${path}" in
        /*)
            printf '%s\n' "${path}"
            ;;
        *)
            printf '%s/%s\n' "$(pwd -P)" "${path#./}"
            ;;
    esac
}

po0_backup_copy_file() {
    local src="$1"
    local dst="$2"
    [[ -r "${src}" ]] || return 1
    mkdir -p "$(dirname "${dst}")" || return 1
    cp -p -- "${src}" "${dst}" || return 1
}

write_cron_block_to_file() {
    local begin="$1"
    local end="$2"
    local output="$3"
    local line in_block=0 found=0
    command -v crontab >/dev/null 2>&1 || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "${begin}" ]]; then
            in_block=1
            found=1
        fi
        [[ "${in_block}" == "1" ]] && printf '%s\n' "${line}"
        if [[ "${line}" == "${end}" ]]; then
            in_block=0
        fi
    done < <(crontab -l 2>/dev/null || true) > "${output}"
    [[ "${found}" == "1" ]]
}

discover_report_keys_to_file() {
    local output="$1"
    local auth user home line scope public_part raw seen="|"
    : > "${output}" || return 1
    while IFS=: read -r user _ _ _ _ home _ || [[ -n "${user}${home}" ]]; do
        [[ -n "${user}" && -n "${home}" ]] || continue
        auth="${home}/.ssh/authorized_keys"
        [[ -r "${auth}" ]] || continue
        case "${seen}" in
            *"|${auth}|"*) continue ;;
        esac
        seen+="${auth}|"
        while IFS= read -r line || [[ -n "${line}" ]]; do
            [[ "${line}" == *"po0-report:scope="* ]] || continue
            public_part="$(report_key_public_part "${line}" || true)"
            [[ -n "${public_part}" ]] || continue
            scope="${line#*po0-report:scope=}"
            scope="${scope%%,*}"
            scope="$(normalize_report_key_scope "${scope}")"
            raw="${line//|/ }"
            printf '%s|%s|%s|%s\n' "${user}" "${scope}" "${public_part}" "${raw}" >> "${output}"
        done < "${auth}"
    done < <(getent passwd 2>/dev/null || cat /etc/passwd 2>/dev/null || true)
    for auth in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
        [[ -r "${auth}" ]] || continue
        case "${seen}" in
            *"|${auth}|"*) continue ;;
        esac
        seen+="${auth}|"
        case "${auth}" in
            /root/*)
                user="root"
                ;;
            /home/*/.ssh/authorized_keys)
                user="${auth#/home/}"
                user="${user%%/*}"
                ;;
            *)
                continue
                ;;
        esac
        while IFS= read -r line || [[ -n "${line}" ]]; do
            [[ "${line}" == *"po0-report:scope="* ]] || continue
            public_part="$(report_key_public_part "${line}" || true)"
            [[ -n "${public_part}" ]] || continue
            scope="${line#*po0-report:scope=}"
            scope="${scope%%,*}"
            scope="$(normalize_report_key_scope "${scope}")"
            raw="${line//|/ }"
            printf '%s|%s|%s|%s\n' "${user}" "${scope}" "${public_part}" "${raw}" >> "${output}"
        done < "${auth}"
    done
}

write_system_state_to_stage() {
    local dir="$1"
    mkdir -p "${dir}" || return 1
    {
        printf 'manager_install_path=%s\n' "${MANAGER_INSTALL_PATH}"
        printf 'main_conf=%s\n' "${MAIN_CONF}"
        printf 'sysctl_conf=%s\n' "${SYSCTL_CONF}"
        printf 'nftables_active=%s\n' "$(systemctl is-active nftables 2>/dev/null || true)"
        printf 'nftables_enabled=%s\n' "$(systemctl is-enabled nftables 2>/dev/null || true)"
        printf 'learn_service_active=%s\n' "$(systemctl is-active "${LEARN_SERVICE_NAME}" 2>/dev/null || true)"
        printf 'learn_service_enabled=%s\n' "$(systemctl is-enabled "${LEARN_SERVICE_NAME}" 2>/dev/null || true)"
    } > "${dir}/system-state.env"
    write_cron_block_to_file "$(resource_task_cron_begin_marker)" "$(resource_task_cron_end_marker)" "${dir}/resource-task-cron.managed" || true
    write_cron_block_to_file "$(dynamic_allowlist_cron_begin_marker)" "$(dynamic_allowlist_cron_end_marker)" "${dir}/dynamic-allowlist-cron.managed" || true
    discover_report_keys_to_file "${dir}/report-keys.tsv" || true
    po0_backup_copy_file "${MAIN_CONF}" "${dir}/nftables.conf" || true
    po0_backup_copy_file "${SYSCTL_CONF}" "${dir}/sysctl.conf" || true
    po0_backup_copy_file "${LEARN_SERVICE_FILE}" "${dir}/nftables-relay-learn.service" || true
    po0_backup_copy_file "${LEARN_RUNNER}" "${dir}/nftables-relay-learn" || true
}

do_full_backup_export() {
    local output="${1:-}" work script_path old_umask local_status
    command -v tar >/dev/null 2>&1 || { err "缺少 tar，无法创建完整备份。"; return 1; }
    ensure_layout || return 1
    load_settings 1
    [[ -n "${output}" ]] || output="$(full_backup_default_path)"
    output="$(absolute_output_path "${output}")"
    mkdir -p "$(dirname "${output}")" || return 1
    make_temp_dir "${BACKUP_DIR}" "po0-full-backup" || return 1
    work="${TEMP_DIR_RESULT}"
    chmod 700 "${work}" 2>/dev/null || true
    old_umask="$(umask)"
    umask 077
    (
        mkdir -p "${work}/files/conf-dir" "${work}/system" "${work}/scripts" || exit 1
        {
            printf 'format=po0-manager-full-backup-v1\n'
            printf 'script_name=%s\n' "${SCRIPT_NAME}"
            printf 'script_version=%s\n' "${SCRIPT_VERSION}"
            printf 'created_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
            printf 'conf_dir=%s\n' "${CONF_DIR}"
            printf 'manager_install_path=%s\n' "${MANAGER_INSTALL_PATH}"
            printf 'contains_secrets=1\n'
        } > "${work}/manifest.env" || exit 1
        tar -cf - \
            --exclude './backups' \
            --exclude './po0-ipdb-venv' \
            --exclude '*.lock' \
            -C "${CONF_DIR}" . | tar -xf - -C "${work}/files/conf-dir" || exit 1
        write_system_state_to_stage "${work}/system" || exit 1
        script_path="$(current_script_path 2>/dev/null || true)"
        [[ -n "${script_path}" && -r "${script_path}" ]] && po0_backup_copy_file "${script_path}" "${work}/scripts/nftables-relay-manager.sh" || true
        (cd "${work}" && tar -czf "${output}" .) || exit 1
    )
    local_status=$?
    umask "${old_umask}"
    [[ "${local_status}" == "0" ]] || return 1
    chmod 600 "${output}" 2>/dev/null || true
    success "PO0 完整备份已导出：${output}"
    info "备份包默认包含 token、动态状态、resource inbox、Egern/Worker public key 信息和脚本快照；已尝试设置 chmod 600。"
}

validate_full_backup_tar_members() {
    local archive="$1" list line
    list="$(mktemp "${TMPDIR:-/tmp}/po0-full-backup-list.XXXXXX")" || return 1
    TEMP_FILES+=("${list}")
    tar -tzf "${archive}" > "${list}" || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            ""|/*|../*|*/../*)
                err "备份包包含不安全路径：${line}"
                return 1
                ;;
        esac
    done < "${list}"
}

backup_current_conf_dir_before_restore() {
    local path
    mkdir -p "${BACKUP_DIR}" || return 1
    path="${BACKUP_DIR}/pre-full-restore-$(date '+%Y%m%d_%H%M%S').tar.gz"
    tar -czf "${path}" \
        --exclude './backups' \
        --exclude './po0-ipdb-venv' \
        --exclude '*.lock' \
        -C "${CONF_DIR}" . 2>/dev/null || true
    chmod 600 "${path}" 2>/dev/null || true
    info "恢复前已备份当前 ${CONF_DIR}：${path}"
}

restore_file_from_full_backup() {
    local src="$1"
    local dst="$2"
    local mode="${3:-600}"
    local backup
    [[ -f "${src}" ]] || return 0
    if [[ "${PO0_FULL_RESTORE_DRY_RUN:-0}" == "1" ]]; then
        printf '[dry-run] restore %s -> %s\n' "${src}" "${dst}"
        return 0
    fi
    mkdir -p "$(dirname "${dst}")" || return 1
    if [[ -e "${dst}" ]]; then
        backup="${dst}.bak.$(date '+%Y%m%d_%H%M%S')"
        cp -p -- "${dst}" "${backup}" 2>/dev/null || true
    fi
    cp -p -- "${src}" "${dst}" || return 1
    chmod "${mode}" "${dst}" 2>/dev/null || true
}

restore_conf_dir_from_full_backup() {
    local work="$1"
    [[ -d "${work}/files/conf-dir" ]] || { err "备份包缺少 files/conf-dir。"; return 1; }
    if [[ "${PO0_FULL_RESTORE_DRY_RUN:-0}" == "1" ]]; then
        printf '[dry-run] restore files/conf-dir -> %s\n' "${CONF_DIR}"
        return 0
    fi
    mkdir -p "${CONF_DIR}" || return 1
    backup_current_conf_dir_before_restore || true
    tar -cf - -C "${work}/files/conf-dir" . | tar -xf - -C "${CONF_DIR}" || return 1
    chmod 700 "${RESOURCE_INBOX_DIR}" 2>/dev/null || true
    ensure_report_key_wrapper || return 1
}

full_backup_manifest_value() {
    local manifest="$1"
    local key="$2"
    local line
    [[ -r "${manifest}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" == "${key}="* ]] || continue
        printf '%s\n' "${line#*=}"
        return 0
    done < "${manifest}"
    return 1
}

rewrite_manager_cron_block_for_current_path() {
    local block="$1"
    local old_path="$2"
    local current_path="$3"
    local line
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "${old_path}" ]] && line="${line//${old_path}/${current_path}}"
        printf '%s\n' "${line}"
    done < "${block}"
}

cron_block_bash_script_path() {
    local block line value
    for block in "$@"; do
        [[ -r "${block}" ]] || continue
        while IFS= read -r line || [[ -n "${line}" ]]; do
            [[ -n "${line}" && "${line}" != \#* ]] || continue
            case "${line}" in
                *" bash '"*)
                    value="${line#* bash \'}"
                    value="${value%%\'*}"
                    [[ -n "${value}" ]] && { printf '%s\n' "${value}"; return 0; }
                    ;;
                *" bash "*)
                    value="${line#* bash }"
                    value="${value%% *}"
                    [[ -n "${value}" ]] && { printf '%s\n' "${value}"; return 0; }
                    ;;
            esac
        done < "${block}"
    done
    return 1
}

restore_managed_cron_blocks_from_full_backup() {
    local work="$1" tmp restored=0 old_path script_path
    command -v crontab >/dev/null 2>&1 || { err "缺少 crontab，无法恢复 cron。"; return 1; }
    if [[ "${PO0_FULL_RESTORE_DRY_RUN:-0}" == "1" ]]; then
        printf '[dry-run] restore PO0 managed cron blocks\n'
        return 0
    fi
    old_path="$(cron_block_bash_script_path "${work}/system/resource-task-cron.managed" "${work}/system/dynamic-allowlist-cron.managed" 2>/dev/null || true)"
    [[ -n "${old_path}" ]] || old_path="$(full_backup_manifest_value "${work}/system/system-state.env" "manager_install_path" 2>/dev/null || true)"
    script_path="$(ensure_persistent_manager_script)" || return 1
    tmp="${CONF_DIR}/po0-full-cron.restore.$$"
    {
        crontab -l 2>/dev/null | write_resource_task_cron_without_managed_block | write_dynamic_allowlist_cron_without_managed_block || true
        if [[ -s "${work}/system/resource-task-cron.managed" ]]; then
            rewrite_manager_cron_block_for_current_path "${work}/system/resource-task-cron.managed" "${old_path}" "${script_path}"
            restored=1
        fi
        if [[ -s "${work}/system/dynamic-allowlist-cron.managed" ]]; then
            rewrite_manager_cron_block_for_current_path "${work}/system/dynamic-allowlist-cron.managed" "${old_path}" "${script_path}"
            restored=1
        fi
    } > "${tmp}" || return 1
    crontab "${tmp}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    rm -f -- "${tmp}" 2>/dev/null || true
    [[ "${restored}" == "1" ]] && success "已恢复 PO0 managed cron block。" || info "备份包没有 PO0 managed cron block。"
}

restore_nftables_system_from_full_backup() {
    local work="$1"
    restore_file_from_full_backup "${work}/system/nftables.conf" "${MAIN_CONF}" 644 || return 1
    restore_file_from_full_backup "${work}/system/sysctl.conf" "${SYSCTL_CONF}" 644 || return 1
    if [[ "${PO0_FULL_RESTORE_DRY_RUN:-0}" == "1" ]]; then
        printf '[dry-run] enable/apply nftables and sysctl\n'
        return 0
    fi
    enable_ip_forward || true
    if [[ -f "${MAIN_CONF}" ]]; then
        apply_full_config || return 1
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now nftables 2>/dev/null || warn "无法自动启用 nftables 服务，请手动检查。"
    fi
    success "已恢复 /etc/nftables.conf、sysctl 并尝试应用 nftables。"
}

restore_systemd_from_full_backup() {
    local work="$1"
    if [[ "${PO0_FULL_RESTORE_DRY_RUN:-0}" == "1" ]]; then
        printf '[dry-run] regenerate PO0 systemd services\n'
        return 0
    fi
    if [[ -f "${work}/system/nftables-relay-learn.service" || -f "${work}/system/nftables-relay-learn" ]]; then
        enable_learning_service || return 1
        success "已用当前脚本重新生成并启用学习服务：${LEARN_SERVICE_NAME}"
    else
        info "备份包没有学习服务快照，跳过 systemd 学习服务恢复。"
    fi
}

restore_report_keys_from_full_backup() {
    local work="$1" file user scope public_part raw restored=0
    file="${work}/system/report-keys.tsv"
    [[ -s "${file}" ]] || { info "备份包没有 PO0 受限 authorized_keys 记录。"; return 0; }
    if [[ "${PO0_FULL_RESTORE_DRY_RUN:-0}" == "1" ]]; then
        printf '[dry-run] restore PO0 restricted authorized_keys from %s\n' "${file}"
        return 0
    fi
    ensure_report_key_wrapper || return 1
    while IFS='|' read -r user scope public_part raw || [[ -n "${user}${scope}${public_part}" ]]; do
        [[ -n "${user}" && -n "${scope}" && -n "${public_part}" ]] || continue
        install_report_public_key "${user}" "${scope}" "${public_part}" || return 1
        restored=1
    done < "${file}"
    [[ "${restored}" == "1" ]] && success "已恢复 PO0 受限 authorized_keys 条目。" || info "没有可恢复的 PO0 受限 key。"
}
