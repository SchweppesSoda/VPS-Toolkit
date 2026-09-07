do_full_backup_import() {
    local archive="${1:-}" work file saved_conf saved_settings saved_cache name dest failed=0
    local -a restored=()
    [[ -f "${archive}" ]] || { err "请指定备份文件。"; return 1; }
    validate_full_backup_tar_members "${archive}" || return 1
    make_temp_dir "${BACKUP_DIR}" "relay-restore" || return 1
    work="${TEMP_DIR_RESULT}"
    tar -xzf "${archive}" -C "${work}" || return 1
    grep -Fxq 'format=po0-relay-backup-v2' "${work}/manifest.env" || { err "备份格式不匹配。"; return 1; }
    saved_conf="${NFT_CONF}"
    saved_settings="${SETTINGS_FILE}"
    saved_cache="${SETTINGS_CACHE_READY}"
    NFT_CONF="${work}/files/conf-dir/po0-relay.conf"
    SETTINGS_FILE="${work}/files/conf-dir/po0-relay.env"
    load_settings 1
    if ! relay_retirement_guard; then
        NFT_CONF="${saved_conf}"; SETTINGS_FILE="${saved_settings}"; load_settings 1
        return 1
    fi
    NFT_CONF="${saved_conf}"; SETTINGS_FILE="${saved_settings}"; load_settings 1
    if [[ "${PO0_FULL_RESTORE_DRY_RUN:-0}" == "1" ]]; then
        printf '备份检查通过；将只恢复转发配置和更新配对，不启动旧任务、不应用规则。\n'
        return 0
    fi
    do_full_backup_export || return 1
    mkdir -p "${work}/before" "${work}/next" || return 1
    # Stage every candidate first; retain before-images for ordinary I/O failure.
    # This is not a multi-file crash-atomic write.
    for file in "${work}/files/conf-dir/"*; do
        [[ -f "${file}" ]] || continue
        name="$(basename "$file")"; dest="${CONF_DIR}/${name}"
        [[ ! -L "$dest" ]] || { err "恢复目标不能是符号链接。"; return 1; }
        [[ ! -f "$dest" ]] || cp -p -- "$dest" "${work}/before/$name" || return 1
        cp -p -- "$file" "${work}/next/$name" || return 1
        chmod 600 "${work}/next/$name" || return 1
    done
    for file in "${work}/next/"*; do
        name="$(basename "$file")"
        if ! mv -f -- "$file" "${CONF_DIR}/${name}"; then failed=1; break; fi
        restored+=("$name")
    done
    if [[ "$failed" == 1 ]]; then
        for name in "${restored[@]}"; do
            if [[ -f "${work}/before/$name" ]]; then cp -p -- "${work}/before/$name" "${CONF_DIR}/$name" || err "请从恢复前备份还原 $name。"
            else rm -f -- "${CONF_DIR}/$name" || true; fi
        done
        err "恢复未完成；已尝试还原本次写入。"; return 1
    fi
    load_settings 1
    RULES_CACHE_READY=0
    success "配置已恢复；核对规则后使用安装 / 应用转发使其生效。"
}

do_full_backup_restore_interactive() {
    local choice path
    print_menu_item 1 "导出备份"
    print_menu_item 2 "恢复新版备份（不应用规则）"
    print_menu_item 0 "返回"
    read_menu_choice_or_return choice "请选择 [0-2]: " || return
    case "${choice}" in
        1) do_full_backup_export ;;
        2) path="$(read_prompt "备份文件路径: ")" && do_full_backup_import "${path}" ;;
    esac
    pause_before_return
}

print_cli_usage() {
    cat <<'EOF'
PO0 转发管理
  --version / --changelog             查看版本和更新内容
  --render                           生成托管转发配置，不应用
  --backup-export [文件]              备份转发配置及更新密钥
  --backup-import 文件                恢复新版备份，不应用规则
  --upgrade-manager-from-lan [URL]    从 Worker 校验并更新脚本
  --configure-update-key             配置与 Worker 配对的更新密钥
  --migration-check                  检查旧保护是否已退出
  --migrate-retired-state             备份并停用旧后台功能，保留转发
无参数进入菜单。旧白名单、上报和资源任务命令已退役。
EOF
}
