load_local_settings() {
    local keep_config="${CONFIG_FILE}" keep_settings="${SETTINGS_FILE}"
    # This protected local settings file was created by the previous client.
    [[ ! -r "${SETTINGS_FILE}" ]] || . "${SETTINGS_FILE}" || return 1
    CONFIG_FILE="${keep_config}"
    SETTINGS_FILE="${keep_settings}"
    UPDATE_KEYS_FILE="$(path_dirname "${SETTINGS_FILE}")/update-keys.txt"
}

manager_update_tokens_env() {
    if [[ -f "${UPDATE_KEYS_FILE}" ]]; then
        awk 'NF && !seen[$0]++ { print }' "${UPDATE_KEYS_FILE}"
        return
    fi
    # Only this migration reader knows the former 20-column target format.
    {
        [[ -z "${RESOURCE_TOKEN:-}" ]] || printf '%s\n' "${RESOURCE_TOKEN}"
        [[ ! -r "${CONFIG_FILE}" ]] || awk -F '|' '$1 == "1" && $11 != "" { print $11 }' "${CONFIG_FILE}"
    } | tr -d '\r' | awk 'NF && !seen[$0]++ { print }'
}

persist_update_keys() {
    local tmp
    [[ ! -f "${UPDATE_KEYS_FILE}" ]] || return 0
    mkdir -p "$(path_dirname "${UPDATE_KEYS_FILE}")" || return 1
    tmp="${UPDATE_KEYS_FILE}.tmp.$$"
    (umask 077; manager_update_tokens_env > "${tmp}") || return 1
    mv -- "${tmp}" "${UPDATE_KEYS_FILE}"
}

save_local_settings() {
    local tmp name
    ensure_worker_retirement_backup || return 1
    persist_update_keys || return 1
    tmp="${SETTINGS_FILE}.tmp.$$"
    (umask 077
      printf '# Managed by po0-lan-client. Update service settings.\n'
      for name in CONFIG_FILE INSTALL_PATH MANAGER_UPDATE_LISTEN MANAGER_UPDATE_DOMAIN MANAGER_UPDATE_BACKEND MANAGER_UPDATE_CADDY_SNIPPET CADDYFILE_PATH; do
          write_env_assignment "${name}" "${!name}"
      done
    ) > "${tmp}" || return 1
    chmod 600 "${tmp}" || return 1
    mv -f -- "${tmp}" "${SETTINGS_FILE}"
}

configure_update_keys() {
    local key tmp count=0
    ensure_worker_retirement_backup || return 1
    tmp="${UPDATE_KEYS_FILE}.tmp.$$"
    (umask 077; : > "${tmp}") || return 1
    printf '逐行填写与 PO0 配对的更新密钥，空行结束；直接空行保留，单独 - 清空。\n'
    while key="$(read_prompt "更新密钥: ")"; do
        [[ -n "${key}" ]] || break
        if [[ "${key}" == '-' && "${count}" == 0 ]]; then count=1; break; fi
        [[ "${key}" != *[$'\r\n\t ']* ]] || { printf '密钥不能含空白。\n' >&2; rm -f -- "${tmp}"; return 1; }
        printf '%s\n' "${key}" >> "${tmp}"
        count=$((count+1))
    done
    if [[ "${count}" == 0 ]]; then rm -f -- "${tmp}"; return 0; fi
    mv -f -- "${tmp}" "${UPDATE_KEYS_FILE}" || return 1
    printf '更新密钥已保存；安装 / 更新服务后生效。\n'
}

ensure_caddyfile_import() {
    local dir line
    dir="$(path_dirname "${MANAGER_UPDATE_CADDY_SNIPPET}")"
    mkdir -p "${dir}" "$(path_dirname "${CADDYFILE_PATH}")" || return 1
    [[ -f "${CADDYFILE_PATH}" ]] || : > "${CADDYFILE_PATH}" || return 1
    line="import ${dir%/}/*.caddy"
    if ! awk '{$1=$1; print}' "${CADDYFILE_PATH}" | grep -Fxq "${line}"; then
        printf '\n# PO0 update service\n%s\n' "${line}" >> "${CADDYFILE_PATH}" || return 1
    fi
}
