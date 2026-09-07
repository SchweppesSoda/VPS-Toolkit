full_backup_default_path() {
    printf '%s/po0-relay-backup-%s-%s.tar.gz\n' "${BACKUP_DIR}" "$(date '+%Y%m%d_%H%M%S')" "$$"
}

absolute_output_path() {
    case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$(pwd -P)" "$1" ;; esac
}

do_full_backup_export() {
    local output="${1:-}" work file
    ensure_layout || return 1
    [[ -f "${NFT_CONF}" ]] || { err "请先生成转发配置再备份。"; return 1; }
    [[ -n "${output}" ]] || output="$(full_backup_default_path)"
    output="$(absolute_output_path "${output}")"
    [[ ! -e "${output}" ]] || { err "备份文件已存在，拒绝覆盖。"; return 1; }
    mkdir -p "$(dirname "${output}")" || return 1
    make_temp_dir "${BACKUP_DIR}" "relay-backup" || return 1
    work="${TEMP_DIR_RESULT}"
    chmod 700 "${work}" || return 1
    mkdir -p "${work}/files/conf-dir" || return 1
    printf 'format=po0-relay-backup-v2\nversion=%s\n' "${SCRIPT_VERSION}" > "${work}/manifest.env"
    for file in "${NFT_CONF}" "${SETTINGS_FILE}" "${RULES_FILE}" "${UPDATE_TOKEN_FILE}"; do
        [[ ! -f "${file}" ]] || cp -p -- "${file}" "${work}/files/conf-dir/" || return 1
    done
    (umask 077; tar -czf "${output}" -C "${work}" .) || return 1
    success "转发配置和更新配对已备份：${output}"
}

validate_full_backup_tar_members() {
    local archive="$1" list line
    list="$(tar -tzf "${archive}")" || return 1
    [[ "$(printf '%s\n' "$list" | sort | uniq -d)" == '' ]] || { err "备份包含重复成员。"; return 1; }
    for line in ./manifest.env ./files/conf-dir/po0-relay.env ./files/conf-dir/po0-relay.rules ./files/conf-dir/po0-relay.conf; do
        printf '%s\n' "$list" | grep -Fxq "$line" || { err "备份缺少必要转发文件。"; return 1; }
    done
    # Reject links/devices as well as unexpected paths before extraction.
    if tar -tvzf "${archive}" | grep -Ev '^[-d]' >/dev/null; then
        err "备份包含非普通文件或目录。"; return 1
    fi
    while IFS= read -r line; do
        case "${line}" in
            ./|./manifest.env|./files/|./files/conf-dir/|./files/conf-dir/po0-relay.env|./files/conf-dir/po0-relay.conf|./files/conf-dir/po0-relay.rules|./files/conf-dir/po0-relay-resource-task.token) ;;
            *) err "备份不是新版转发备份；完整旧版备份请使用固定归档版恢复。"; return 1 ;;
        esac
    done <<< "${list}"
}
