manager_update_token_value() {
    [[ -s "${UPDATE_TOKEN_FILE}" ]] || return 1
    tr -d '\r\n' < "${UPDATE_TOKEN_FILE}"
}

configure_update_key() {
    local key tmp
    ensure_layout || return 1
    key="$(read_prompt "更新密钥（须与 Worker 一致；回车保留）: ")" || return 1
    [[ -n "${key}" ]] || return 0
    [[ "${key}" != *[$'\r\n\t ']* ]] || { err "更新密钥不能包含空白。"; return 1; }
    make_temp_file "${UPDATE_TOKEN_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    chmod 600 "${tmp}" || return 1
    printf '%s\n' "${key}" > "${tmp}" || return 1
    mv -f -- "${tmp}" "${UPDATE_TOKEN_FILE}" || return 1
    success "更新密钥已保存。"
}

relay_retirement_guard() {
    # Never convert an existing input/source filter into an unfiltered relay.
    local runtime=""
    if [[ "${ENABLE_SRC_ALLOWLIST:-0}" != "0" || "${MANAGE_INPUT_FIREWALL:-0}" != "0" ]]; then
        err "旧配置仍启用自建白名单或入站保护；请用归档版核实并退出旧保护后再迁移。"
        return 1
    fi
    if [[ -r "${NFT_CONF}" ]] && grep -Eq 'chain input_guard|ip saddr @po0_src|set po0_src' "${NFT_CONF}"; then
        err "旧托管配置仍包含保护规则；已停止转换，现有规则保持不变。"
        return 1
    fi
    if command -v nft >/dev/null 2>&1; then
        runtime="$(nft list table ip "${NAT_TABLE}" 2>/dev/null || true)"
        if printf '%s\n' "${runtime}" | grep -Eq 'chain input_guard|ip saddr @po0_src|set po0_src'; then
            err "运行中的 PO0 托管表仍有旧保护规则；已停止转换。"
            return 1
        fi
    fi
}

manager_migration_check() {
    load_settings 1
    relay_retirement_guard || return 1
    printf '迁移检查通过：转发可保留，更新密钥%s。\n' "$(if manager_update_token_value >/dev/null; then printf '已存在'; else printf '尚未配置'; fi)"
}

migrate_retired_manager_state() {
    local archive stage before after service file name
    manager_migration_check || return 1
    [[ ! -f "${CONF_DIR}/.po0-relay-retired-v1" ]] || { info "已完成旧功能迁移。"; return 0; }
    ensure_layout || return 1
    make_temp_dir "${BACKUP_DIR}" "pre-retirement" || return 1
    stage="${TEMP_DIR_RESULT}"
    archive="${BACKUP_DIR}/pre-retirement-$(date '+%Y%m%d_%H%M%S')-$$.tar.gz"
    # Back up the old state before changing schedules or credentials.
    tar --exclude='./backups' --exclude='./po0-ipdb-venv' -czf "${archive}" -C "${CONF_DIR}" . || return 1
    chmod 600 "${archive}" || return 1
    tar -tzf "${archive}" >/dev/null || return 1
    printf '迁移前配置备份：%s\n' "${archive}"
    before="${stage}/crontab.before"
    after="${stage}/crontab.after"
    if command -v crontab >/dev/null 2>&1; then
        crontab -l > "${before}" 2>/dev/null || : > "${before}"
        cp "${before}" "${archive}.crontab" || return 1
        chmod 600 "${archive}.crontab" || return 1
        awk '
          /^# BEGIN PO0 nftables dynamic allowlist cleanup$/ { skip=1; next }
          /^# END PO0 nftables dynamic allowlist cleanup$/ { skip=0; next }
          /^# BEGIN PO0 nftables resource task scheduler$/ { skip=1; next }
          /^# END PO0 nftables resource task scheduler$/ { skip=0; next }
          !skip { print }
          END { if (skip) exit 2 }
        ' "${before}" > "${after}" || return 1
        cmp -s "${before}" "${after}" || crontab "${after}" || return 1
    fi
    service="/etc/systemd/system/nftables-relay-learn.service"
    if [[ -f "${service}" ]] && grep -Fq 'nftables-relay-learn' "${service}"; then
        cp -p "${service}" "${archive}.learn.service" || return 1
        systemctl disable --now nftables-relay-learn.service || return 1
        rm -f -- "${service}" || return 1
        systemctl daemon-reload || return 1
    fi
    # Backed-up data remains available locally, outside the active configuration.
    mkdir -p "${BACKUP_DIR}/retired-state" || return 1
    chmod 700 "${BACKUP_DIR}/retired-state" || return 1
    for file in "${CONF_DIR}"/po0-relay-* "${CONF_DIR}"/po0-report-key-wrapper "${CONF_DIR}"/po0-report-key-denied.log "${CONF_DIR}"/po0-iplist "${CONF_DIR}"/qqwry.ipdb; do
        [[ -e "${file}" ]] || continue
        name="$(basename "${file}")"
        case "${name}" in
            po0-relay.env|po0-relay.conf|po0-relay.rules|po0-relay-resource-task.token) continue ;;
            po0-relay-allowlist-*|po0-relay-src-allowlist.txt|po0-relay-custom-src-allowlist.txt|po0-relay-ddns-*|po0-relay-client-ip-*|po0-relay-ssh-*|po0-relay-webauth-*|po0-relay-auto-pending.tsv|po0-relay-resource-*|po0-relay-learn*|po0-relay-block*|po0-relay-dynamic-state.lock|po0-report-key-wrapper|po0-report-key-denied.log|po0-iplist|qqwry.ipdb)
                [[ ! -e "${BACKUP_DIR}/retired-state/${name}" ]] || { err "归档目标已存在：${name}"; return 1; }
                mv -- "${file}" "${BACKUP_DIR}/retired-state/" || return 1 ;;
        esac
    done
    save_settings || return 1
    printf '%s\n' "${archive}" > "${CONF_DIR}/.po0-relay-retired-v1" || return 1
    success "旧后台任务已停用，转发规则和更新配对保留；未重新应用 nftables。"
}
