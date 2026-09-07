worker_retirement_backup_dir() {
    printf '%s/pre-retirement-v1\n' "$(path_dirname "${SETTINGS_FILE}")"
}

ensure_worker_retirement_backup() {
    local dir src
    dir="$(worker_retirement_backup_dir)"
    [[ ! -f "${dir}/complete" ]] || return 0
    mkdir -p "${dir}" || return 1
    chmod 700 "${dir}" || return 1
    [[ ! -f "${SETTINGS_FILE}" || -f "${dir}/settings.env" ]] || cp -p "${SETTINGS_FILE}" "${dir}/settings.env" || return 1
    [[ ! -f "${CONFIG_FILE}" || -f "${dir}/targets.tsv" ]] || cp -p "${CONFIG_FILE}" "${dir}/targets.tsv" || return 1
    src="$(script_source_path)"
    [[ ! -f "${src}" || -f "${dir}/po0-lan-client.sh" ]] || cp -p "${src}" "${dir}/po0-lan-client.sh" || return 1
    [[ ! -f "${UPDATE_KEYS_FILE}" || -f "${dir}/update-keys.txt" ]] || cp -p "${UPDATE_KEYS_FILE}" "${dir}/update-keys.txt" || return 1
    [[ ! -f "${CADDYFILE_PATH}" || -f "${dir}/Caddyfile" ]] || cp -p "${CADDYFILE_PATH}" "${dir}/Caddyfile" || return 1
    if [[ ! -f "${dir}/crontab" ]]; then crontab -l > "${dir}/crontab" 2>/dev/null || : > "${dir}/crontab"; fi
    chmod 600 "${dir}/"* || return 1
    printf '1\n' > "${dir}/complete" || return 1
    printf '旧配置和任务备份：%s\n' "${dir}" >&2
}

migrate_worker_retired_state() {
    local dir begin end next service unit snippet
    ensure_worker_retirement_backup || return 1
    persist_update_keys || return 1
    dir="$(worker_retirement_backup_dir)"
    [[ ! -f "${dir}/retired" ]] || { printf '旧后台功能已迁移。\n'; return 0; }
    begin="# PO0_LAN_CLIENT_BEGIN ${CONFIG_FILE}"
    end="# PO0_LAN_CLIENT_END ${CONFIG_FILE}"
    next="${dir}/crontab.next"
    if command -v crontab >/dev/null 2>&1; then
        crontab -l > "${dir}/crontab.current" 2>/dev/null || : > "${dir}/crontab.current"
        awk -v begin="${begin}" -v end="${end}" '$0==begin { skip=1; next } $0==end { skip=0; next } !skip {print} END {if(skip) exit 2}' "${dir}/crontab.current" > "${next}" || return 1
        cmp -s "${dir}/crontab.current" "${next}" || crontab "${next}" || return 1
    fi
    for service in po0-lan-self-report.service po0-lan-webauth.service; do
        unit="/etc/systemd/system/${service}"
        if [[ -f "${unit}" ]] && grep -Fq -- "--config '${CONFIG_FILE}'" "${unit}"; then
            cp -p "${unit}" "${dir}/${service}" || return 1
            systemctl disable --now "${service}" || return 1
            rm -f -- "${unit}" || return 1
            systemctl daemon-reload || return 1
        fi
    done
    snippet="${SELF_REPORT_CADDY_SNIPPET:-/etc/caddy/conf.d/po0-self-report.caddy}"
    if [[ "${snippet}" != "${MANAGER_UPDATE_CADDY_SNIPPET}" && -f "${snippet}" ]] && grep -Fq 'Managed by po0-lan-client' "${snippet}"; then
        cp -p "${snippet}" "${dir}/self-report.caddy" || return 1
        mv -- "${snippet}" "${snippet}.retired" || return 1
        if ! caddy validate --config "${CADDYFILE_PATH}"; then
            mv -- "${snippet}.retired" "${snippet}"
            return 1
        fi
        systemctl reload caddy || return 1
    fi
    save_local_settings || return 1
    printf '1\n' > "${dir}/retired" || return 1
    printf '旧接收与轮询已退役；更新镜像保留。官方设置仍在备份中，可执行迁移到官方客户端。\n'
}

migrate_worker_official() {
    local reporter="${1:-}" dir
    [[ -n "${reporter}" ]] || { printf '请指定同机新版官方客户端路径。\n' >&2; return 1; }
    [[ -f "${reporter}" && -x "${reporter}" ]] || { printf '官方客户端不可执行。\n' >&2; return 1; }
    ensure_worker_retirement_backup || return 1
    dir="$(worker_retirement_backup_dir)"
    [[ ! -f "${dir}/official-migrated" ]] || { printf '官方配置已迁移。\n'; return 0; }
    # The importer validates conflicts and preserves the original schedule state.
    "${reporter}" --import-worker-official "${dir}" || return 1
    migrate_worker_retired_state || return 1
    "${reporter}" --activate-worker-official "${dir}" || return 1
    printf '1\n' > "${dir}/official-migrated" || return 1
    printf '官方配置已交给同机客户端；Worker 只负责更新。\n'
}

worker_backup_export() {
    local dest="${1:-}" dir
    dir="$(path_dirname "${SETTINGS_FILE}")"
    [[ -n "${dest}" ]] || dest="${dir}/update-backup-$(date '+%Y%m%d_%H%M%S')-$$.tar.gz"
    [[ ! -e "${dest}" ]] || { printf '备份文件已存在。\n' >&2; return 1; }
    ensure_worker_retirement_backup || return 1
    save_local_settings || return 1
    (umask 077; tar -czf "${dest}" -C "${dir}" "$(basename "${SETTINGS_FILE}")" update-keys.txt) || return 1
    printf '更新配置备份：%s\n' "${dest}"
}

worker_backup_import() {
    local archive="${1:-}" py
    [[ -f "$archive" ]] || { printf '请指定新版更新配置备份。\n' >&2; return 1; }
    if have_cmd python3; then py=python3; elif have_cmd python; then py=python; else printf '需要 Python 3。\n' >&2; return 1; fi
    ensure_worker_retirement_backup || return 1
    "$py" - "$archive" "$SETTINGS_FILE" "$UPDATE_KEYS_FILE" <<'PY'
import os, pathlib, re, shlex, sys, tarfile, tempfile
archive, settings, keys = sys.argv[1:]
destinations = [pathlib.Path(settings), pathlib.Path(keys)]
allowed_keys = {'CONFIG_FILE', 'INSTALL_PATH', 'MANAGER_UPDATE_LISTEN', 'MANAGER_UPDATE_DOMAIN', 'MANAGER_UPDATE_BACKEND', 'MANAGER_UPDATE_CADDY_SNIPPET', 'CADDYFILE_PATH'}
staged = []
backups = []
try:
    with tarfile.open(archive, 'r:gz') as tar:
        members = tar.getmembers()
        expected = {destinations[0].name, 'update-keys.txt'}
        if len(members) != 2 or {m.name for m in members} != expected: raise ValueError()
        if any(not m.isfile() or m.size > 65536 for m in members): raise ValueError()
        raw_settings = tar.extractfile(destinations[0].name).read().decode('utf-8')
        raw_keys = tar.extractfile('update-keys.txt').read().decode('utf-8')
    values = {}
    for line in raw_settings.splitlines():
        if not line.strip() or line.lstrip().startswith('#'): continue
        fields = shlex.split(line, comments=True)
        if len(fields) != 1 or '=' not in fields[0]: raise ValueError()
        key, value = fields[0].split('=', 1)
        if key not in allowed_keys or key in values or '\x00' in value: raise ValueError()
        values[key] = value
    tokens = list(dict.fromkeys(line.strip() for line in raw_keys.splitlines() if line.strip()))
    if any(re.search(r'\s|\x00', token) for token in tokens): raise ValueError()
    payloads = ['# Restored update settings.\n' + ''.join(key + '=' + shlex.quote(value) + '\n' for key, value in values.items()), ''.join(token + '\n' for token in tokens)]
    for dest, payload in zip(destinations, payloads):
        if dest.is_symlink(): raise ValueError()
        fd, name = tempfile.mkstemp(prefix='.po0-update-restore-', dir=dest.parent)
        with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as f: f.write(payload)
        os.chmod(name, 0o600)
        staged.append(name)
        backups.append(dest.read_bytes() if dest.exists() else None)
    replaced = 0
    try:
        for name, dest in zip(staged, destinations):
            os.replace(name, dest); replaced += 1
    except Exception:
        for dest, data in zip(destinations[:replaced], backups):
            if data is None: dest.unlink(missing_ok=True)
            else: dest.write_bytes(data); os.chmod(dest, 0o600)
        raise
except Exception:
    sys.stderr.write('更新备份检查或恢复失败；只接受新版普通文件备份。\n')
    sys.exit(1)
finally:
    for name in staged:
        pathlib.Path(name).unlink(missing_ok=True)
PY
    [[ $? == 0 ]] || return 1
    load_local_settings || return 1
    printf '更新配置已恢复；核对入口和配对后安装 / 更新镜像服务。\n'
}
