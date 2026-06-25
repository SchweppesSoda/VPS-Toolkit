lan_backup_default_path() {
    local dir stamp
    dir="$(path_dirname "${CONFIG_FILE}")/backups"
    stamp="$(date '+%Y%m%d_%H%M%S')"
    printf '%s/po0-lan-client-backup-%s.tar.gz\n' "${dir}" "${stamp}"
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

copy_file_to_stage() {
    local src="$1"
    local dst="$2"
    [[ -r "${src}" ]] || return 1
    mkdir -p "$(path_dirname "${dst}")" || return 1
    cp -p "${src}" "${dst}" || return 1
}

expand_identity_path() {
    local path="$1"
    case "${path}" in
        "~/"*)
            printf '%s/%s\n' "${HOME:-}" "${path#~/}"
            ;;
        *)
            printf '%s\n' "${path}"
            ;;
    esac
}

emit_identity_paths_from_extra() {
    local extra="$1"
    local -a parts=()
    local i token next
    [[ -n "${extra}" ]] || return 0
    read -r -a parts <<< "${extra}"
    for ((i = 0; i < ${#parts[@]}; i++)); do
        token="${parts[$i]}"
        next="${parts[$((i + 1))]:-}"
        case "${token}" in
            -i)
                [[ -n "${next}" ]] && printf '%s\n' "$(expand_identity_path "${next}")"
                i=$((i + 1))
                ;;
            -i*)
                [[ "${token}" != "-i" ]] && printf '%s\n' "$(expand_identity_path "${token#-i}")"
                ;;
            IdentityFile=*)
                printf '%s\n' "$(expand_identity_path "${token#IdentityFile=}")"
                ;;
            -o)
                case "${next}" in
                    IdentityFile=*)
                        printf '%s\n' "$(expand_identity_path "${next#IdentityFile=}")"
                        i=$((i + 1))
                        ;;
                esac
                ;;
            -oIdentityFile=*)
                printf '%s\n' "$(expand_identity_path "${token#-oIdentityFile=}")"
                ;;
        esac
    done
}

lan_backup_collect_identity_files() {
    local line path seen=","
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        while IFS= read -r path || [[ -n "${path}" ]]; do
            path="$(trim "${path}")"
            [[ -n "${path}" && -r "${path}" ]] || continue
            case "${seen}" in
                *,"${path}",*) continue ;;
            esac
            seen+="${path},"
            printf '%s\n' "${path}"
        done < <({
            emit_identity_paths_from_extra "${TARGET_SSH_EXTRA_ARGS}"
            emit_identity_paths_from_extra "${TARGET_REPORT_SSH_EXTRA_ARGS}"
        } || true)
    done < "${CONFIG_FILE}"
}

write_managed_cron_block_to_file() {
    local output="$1"
    local begin end line in_block=0 found=0
    command -v crontab >/dev/null 2>&1 || return 1
    begin="$(cron_begin_marker)"
    end="$(cron_end_marker)"
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

lan_backup_export() {
    local output="${1:-}" work config_dir script_path rel name path idx old_umask local_status
    have_cmd tar || { printf '缺少 tar，无法创建备份包。\n' >&2; return 1; }
    ensure_config_file || return 1
    ensure_stats_file || return 1
    ensure_resource_stats_file || return 1
    ensure_resource_events_file || return 1
    save_local_settings || return 1
    [[ -n "${output}" ]] || output="$(lan_backup_default_path)"
    output="$(absolute_output_path "${output}")"
    mkdir -p "$(path_dirname "${output}")" || return 1
    work="$(mktemp -d "${TMPDIR:-/tmp}/po0-lan-backup.XXXXXX")" || return 1
    chmod 700 "${work}" 2>/dev/null || true
    old_umask="$(umask)"
    umask 077
    (
        mkdir -p "${work}/files/config" "${work}/files/state" "${work}/files/secrets/config-ssh-keys" "${work}/files/secrets/identity-files" "${work}/system" "${work}/scripts" || exit 1
        {
            printf 'format=po0-lan-client-backup-v1\n'
            printf 'script_name=%s\n' "${SCRIPT_NAME}"
            printf 'script_version=%s\n' "${SCRIPT_VERSION}"
            printf 'created_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
            printf 'config_file=%s\n' "${CONFIG_FILE}"
            printf 'settings_file=%s\n' "${SETTINGS_FILE}"
            printf 'stats_file=%s\n' "${STATS_FILE}"
            printf 'resource_stats_file=%s\n' "${RESOURCE_STATS_FILE}"
            printf 'resource_events_file=%s\n' "${RESOURCE_EVENTS_FILE}"
            printf 'install_path=%s\n' "$(default_install_path)"
            printf 'contains_secrets=1\n'
        } > "${work}/manifest.env" || exit 1
        copy_file_to_stage "${CONFIG_FILE}" "${work}/files/config/targets.tsv" || exit 1
        copy_file_to_stage "${SETTINGS_FILE}" "${work}/files/config/settings.env" || exit 1
        copy_file_to_stage "${STATS_FILE}" "${work}/files/state/stats.tsv" || true
        copy_file_to_stage "${RESOURCE_STATS_FILE}" "${work}/files/state/resource-stats.tsv" || true
        copy_file_to_stage "${RESOURCE_EVENTS_FILE}" "${work}/files/state/resource-events.tsv" || true
        config_dir="$(path_dirname "${CONFIG_FILE}")"
        for path in "${config_dir}"/ssh-key-*; do
            [[ -f "${path}" && -r "${path}" ]] || continue
            name="${path##*/}"
            copy_file_to_stage "${path}" "${work}/files/secrets/config-ssh-keys/${name}" || exit 1
        done
        idx=0
        : > "${work}/files/secrets/identity-files.tsv" || exit 1
        while IFS= read -r path || [[ -n "${path}" ]]; do
            [[ -n "${path}" && -r "${path}" ]] || continue
            idx=$((idx + 1))
            name="$(safe_filename_token "${idx}-${path##*/}")"
            rel="files/secrets/identity-files/${name}"
            copy_file_to_stage "${path}" "${work}/${rel}" || exit 1
            printf '%s|%s\n' "${rel}" "${path}" >> "${work}/files/secrets/identity-files.tsv"
        done < <(lan_backup_collect_identity_files || true)
        write_managed_cron_block_to_file "${work}/system/crontab.managed" || true
        copy_file_to_stage "/etc/systemd/system/po0-lan-webauth.service" "${work}/system/po0-lan-webauth.service" || true
        copy_file_to_stage "/etc/systemd/system/po0-lan-self-report.service" "${work}/system/po0-lan-self-report.service" || true
        copy_file_to_stage "/etc/systemd/system/po0-lan-manager-update.service" "${work}/system/po0-lan-manager-update.service" || true
        copy_file_to_stage "${SELF_REPORT_CADDY_SNIPPET}" "${work}/system/po0-self-report.caddy" || true
        copy_file_to_stage "${MANAGER_UPDATE_CADDY_SNIPPET}" "${work}/system/po0-manager-update.caddy" || true
        copy_file_to_stage "${CADDYFILE_PATH}" "${work}/system/Caddyfile" || true
        script_path="$(script_source_path)"
        copy_file_to_stage "${script_path}" "${work}/scripts/po0-lan-client.sh" || true
        (cd "${work}" && tar -czf "${output}" .) || exit 1
    )
    local_status=$?
    umask "${old_umask}"
    rm -rf "${work}" 2>/dev/null || true
    [[ "${local_status}" == "0" ]] || return 1
    chmod 600 "${output}" 2>/dev/null || true
    printf 'LAN Worker 备份已导出：%s\n' "${output}"
    printf '备份包包含 Token、SSH 私钥和 SELF_REPORT_SECRET；已尝试设置 chmod 600。\n'
}

validate_backup_tar_members() {
    local archive="$1" list line
    list="$(mktemp "${TMPDIR:-/tmp}/po0-lan-backup-list.XXXXXX")" || return 1
    tar -tzf "${archive}" > "${list}" || {
        rm -f -- "${list}" 2>/dev/null || true
        return 1
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            ""|/*|../*|*/../*)
                rm -f -- "${list}" 2>/dev/null || true
                printf '备份包包含不安全路径：%s\n' "${line}" >&2
                return 1
                ;;
        esac
    done < "${list}"
    rm -f -- "${list}" 2>/dev/null || true
}

restore_file_from_stage() {
    local src="$1"
    local dst="$2"
    local mode="${3:-600}"
    local backup
    [[ -f "${src}" ]] || return 0
    if [[ "${RESTORE_DRY_RUN}" == "1" ]]; then
        printf '[dry-run] restore %s -> %s\n' "${src}" "${dst}"
        return 0
    fi
    mkdir -p "$(path_dirname "${dst}")" || return 1
    if [[ -e "${dst}" ]]; then
        backup="${dst}.bak.$(date '+%Y%m%d_%H%M%S')"
        cp -p "${dst}" "${backup}" 2>/dev/null || true
    fi
    cp -p "${src}" "${dst}" || return 1
    chmod "${mode}" "${dst}" 2>/dev/null || true
}

restore_config_ssh_keys_from_stage() {
    local work="$1"
    local config_dir path name
    config_dir="$(path_dirname "${CONFIG_FILE}")"
    if [[ "${RESTORE_DRY_RUN}" != "1" ]]; then
        mkdir -p "${config_dir}" || return 1
    fi
    for path in "${work}/files/secrets/config-ssh-keys/"*; do
        [[ -f "${path}" ]] || continue
        name="${path##*/}"
        restore_file_from_stage "${path}" "${config_dir}/${name}" 600 || return 1
    done
}

restore_identity_files_from_stage() {
    local work="$1"
    local map="${work}/files/secrets/identity-files.tsv"
    local rel path
    [[ -f "${map}" ]] || return 0
    while IFS='|' read -r rel path || [[ -n "${rel}${path}" ]]; do
        [[ -n "${rel}" && -n "${path}" ]] || continue
        restore_file_from_stage "${work}/${rel}" "${path}" 600 || return 1
    done < "${map}"
}

backup_manifest_value() {
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

rewrite_lan_cron_block_for_current_paths() {
    local block="$1"
    local old_config="$2"
    local old_script="$3"
    local current_script="$4"
    local line
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "${old_config}" ]] && line="${line//${old_config}/${CONFIG_FILE}}"
        [[ -n "${old_script}" ]] && line="${line//${old_script}/${current_script}}"
        printf '%s\n' "${line}"
    done < "${block}"
}

cron_block_bash_script_path() {
    local block="$1" line value
    [[ -r "${block}" ]] || return 1
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
    return 1
}

restore_managed_cron_from_stage() {
    local work="$1"
    local block="${work}/system/crontab.managed"
    local tmp old_config old_script script_path
    [[ -s "${block}" ]] || { printf '备份包没有 LAN Worker managed cron block。\n'; return 0; }
    command -v crontab >/dev/null 2>&1 || { printf '缺少 crontab，无法恢复 cron。\n' >&2; return 1; }
    if [[ "${RESTORE_DRY_RUN}" == "1" ]]; then
        printf '[dry-run] restore managed cron block\n'
        return 0
    fi
    old_config="$(backup_manifest_value "${work}/manifest.env" "config_file" 2>/dev/null || true)"
    old_script="$(cron_block_bash_script_path "${block}" 2>/dev/null || true)"
    [[ -n "${old_script}" ]] || old_script="$(backup_manifest_value "${work}/manifest.env" "install_path" 2>/dev/null || true)"
    script_path="$(ensure_persistent_script)" || return 1
    tmp="${CONFIG_FILE}.cron.restore.$$"
    {
        crontab -l 2>/dev/null | write_cron_without_managed_block || true
        rewrite_lan_cron_block_for_current_paths "${block}" "${old_config}" "${old_script}" "${script_path}"
    } > "${tmp}" || return 1
    crontab "${tmp}" || {
        rm -f "${tmp}" 2>/dev/null || true
        return 1
    }
    rm -f "${tmp}" 2>/dev/null || true
    printf '已恢复 LAN Worker managed cron block。\n'
}

restore_caddy_from_stage() {
    local work="$1"
    local restored=0
    if [[ -f "${work}/system/po0-self-report.caddy" ]]; then
        restore_file_from_stage "${work}/system/po0-self-report.caddy" "${SELF_REPORT_CADDY_SNIPPET}" 644 || return 1
        restored=1
    fi
    if [[ -f "${work}/system/po0-manager-update.caddy" ]]; then
        restore_file_from_stage "${work}/system/po0-manager-update.caddy" "${MANAGER_UPDATE_CADDY_SNIPPET}" 644 || return 1
        restored=1
    fi
    [[ "${restored}" == "1" ]] || { printf '备份包没有 LAN Worker Caddy snippet。\n'; return 0; }
    if [[ "${RESTORE_DRY_RUN}" == "1" ]]; then
        printf '[dry-run] ensure Caddyfile import and reload caddy\n'
        return 0
    fi
    ensure_caddyfile_import || return 1
    if have_cmd caddy; then
        caddy validate --config "${CADDYFILE_PATH}" || return 1
    fi
    if have_cmd systemctl; then
        systemctl reload caddy 2>/dev/null || systemctl restart caddy || return 1
    fi
    printf '已恢复 LAN Worker Caddy snippet 并刷新 Caddy。\n'
}
