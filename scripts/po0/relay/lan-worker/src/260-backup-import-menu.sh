restore_systemd_from_stage() {
    local work="$1" restored=0
    if [[ "${RESTORE_DRY_RUN}" == "1" ]]; then
        printf '[dry-run] regenerate LAN Worker systemd services from restored settings\n'
        return 0
    fi
    if [[ -f "${work}/system/po0-lan-self-report.service" ]]; then
        install_self_report_service || return 1
        restored=1
    fi
    if [[ -f "${work}/system/po0-lan-webauth.service" ]]; then
        install_webauth_service || return 1
        restored=1
    fi
    if [[ -f "${work}/system/po0-lan-manager-update.service" ]]; then
        install_manager_update_mirror_service || return 1
        restored=1
    fi
    [[ "${restored}" == "1" ]] || printf '备份包没有 LAN Worker systemd service 快照。\n'
}

lan_backup_import() {
    local archive="$1" work local_status
    [[ -n "${archive}" ]] || { printf '缺少备份包路径。\n' >&2; return 1; }
    [[ -r "${archive}" ]] || { printf '无法读取备份包：%s\n' "${archive}" >&2; return 1; }
    have_cmd tar || { printf '缺少 tar，无法导入备份包。\n' >&2; return 1; }
    validate_backup_tar_members "${archive}" || return 1
    work="$(mktemp -d "${TMPDIR:-/tmp}/po0-lan-restore.XXXXXX")" || return 1
    chmod 700 "${work}" 2>/dev/null || true
    tar -xzf "${archive}" -C "${work}" || {
        rm -rf "${work}" 2>/dev/null || true
        return 1
    }
    [[ -f "${work}/manifest.env" ]] || {
        rm -rf "${work}" 2>/dev/null || true
        printf '备份包缺少 manifest.env。\n' >&2
        return 1
    }
    local_status=0
    if lan_state_lock; then
        restore_file_from_stage "${work}/files/config/targets.tsv" "${CONFIG_FILE}" 600 || local_status=1
        restore_file_from_stage "${work}/files/config/settings.env" "${SETTINGS_FILE}" 600 || local_status=1
        restore_file_from_stage "${work}/files/state/stats.tsv" "${STATS_FILE}" 600 || local_status=1
        restore_file_from_stage "${work}/files/state/resource-stats.tsv" "${RESOURCE_STATS_FILE}" 600 || local_status=1
        restore_file_from_stage "${work}/files/state/resource-events.tsv" "${RESOURCE_EVENTS_FILE}" 600 || local_status=1
        lan_state_unlock
    else
        local_status=1
    fi
    restore_config_ssh_keys_from_stage "${work}" || local_status=1
    restore_identity_files_from_stage "${work}" || local_status=1
    if [[ "${local_status}" == "0" && "${RESTORE_DRY_RUN}" != "1" ]]; then
        load_local_settings || local_status=1
    fi
    if [[ "${RESTORE_CRON}" == "1" ]]; then
        restore_managed_cron_from_stage "${work}" || local_status=1
    fi
    if [[ "${RESTORE_CADDY}" == "1" ]]; then
        restore_caddy_from_stage "${work}" || local_status=1
    fi
    if [[ "${RESTORE_SYSTEMD}" == "1" ]]; then
        restore_systemd_from_stage "${work}" || local_status=1
    fi
    rm -rf "${work}" 2>/dev/null || true
    [[ "${local_status}" == "0" ]] || return 1
    if [[ "${RESTORE_DRY_RUN}" == "1" ]]; then
        printf 'LAN Worker 备份 dry-run 完成，未写入文件：%s\n' "${archive}"
    else
        printf 'LAN Worker 备份已导入：%s\n' "${archive}"
    fi
    if [[ "${RESTORE_CRON}${RESTORE_SYSTEMD}${RESTORE_CADDY}" == "000" ]]; then
        printf '默认仅恢复配置、状态和密钥；cron/systemd/Caddy 未恢复。需要时加 --restore-cron、--restore-systemd、--restore-caddy 或 --restore-all。\n'
    fi
}

backup_restore_interactive() {
    local choice path flags
    print_menu_section "LAN Worker 备份 / 恢复"
    print_menu_item 1 "导出完整备份"
    print_menu_item 2 "导入：只恢复配置、状态和密钥"
    print_menu_item 3 "导入：恢复全部（含 cron/systemd/Caddy）"
    print_menu_item 0 "返回"
    print_menu_footer
    read_menu_choice_or_return choice "请选择操作 [0-3]: " || return 0
    case "${choice}" in
        1)
            path="$(prompt_default "备份输出路径" "$(lan_backup_default_path)")"
            lan_backup_export "${path}"
            ;;
        2)
            path="$(prompt_default "备份包路径" "")"
            [[ -n "${path}" ]] || return 0
            RESTORE_CRON="0" RESTORE_SYSTEMD="0" RESTORE_CADDY="0"
            lan_backup_import "${path}"
            ;;
        3)
            path="$(prompt_default "备份包路径" "")"
            [[ -n "${path}" ]] || return 0
            printf '即将恢复 cron、systemd service 和 Caddy snippet；这会修改本机运行入口。\n'
            prompt_yes_no "确认继续" "n" || return 0
            RESTORE_CRON="1" RESTORE_SYSTEMD="1" RESTORE_CADDY="1"
            lan_backup_import "${path}"
            ;;
        0)
            return 0
            ;;
        *)
            printf '无效选择。\n' >&2
            return 1
            ;;
    esac
}
