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
