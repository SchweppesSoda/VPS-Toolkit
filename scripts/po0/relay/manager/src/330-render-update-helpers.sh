do_render() {
    local render_dir render_conf render_cache
    make_temp_dir "${TMPDIR:-/tmp}" "po0-relay-render" || return 1
    render_dir="${TEMP_DIR_RESULT}"
    render_conf="${render_dir}/po0-relay.conf"
    render_cache="${render_dir}/po0-relay-src-allowlist.txt"
    write_nft_conf "${render_conf}" "${render_cache}" || return 1
    cat "${render_conf}"
}

script_changelog_lines() {
    local file="${1:-}"
    local line in_block=0 found=0
    [[ -r "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "# CHANGELOG_BEGIN" ]]; then
            in_block=1
            continue
        fi
        if [[ "${line}" == "# CHANGELOG_END" ]]; then
            break
        fi
        [[ "${in_block}" == "1" ]] || continue
        line="${line#\# }"
        line="${line#\#}"
        line="$(trim "${line}")"
        [[ -n "${line}" ]] || continue
        found=1
        printf '%s\n' "${line}"
    done < "${file}"
    [[ "${found}" == "1" ]]
}

script_file_var() {
    local file="$1"
    local name="$2"
    local line value
    [[ -r "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" == "${name}="* ]] || continue
        value="${line#*=}"
        value="${value%\"}"
        value="${value#\"}"
        printf '%s\n' "${value}"
        return 0
    done < "${file}"
    return 1
}

sha256_file_full() {
    local file="$1"
    command -v sha256sum >/dev/null 2>&1 || return 1
    sha256sum "${file}" 2>/dev/null | awk '{ print $1 }'
}

sha256_string() {
    local value="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "${value}" | sha256sum | awk '{ print $1 }'
    elif command -v openssl >/dev/null 2>&1; then
        printf '%s' "${value}" | openssl dgst -sha256 2>/dev/null | awk '{ print $NF }'
    else
        return 1
    fi
}

hmac_sha256_hex() {
    local key="$1"
    local message="$2"
    local py
    if command -v openssl >/dev/null 2>&1; then
        printf '%s' "${message}" | openssl dgst -sha256 -hmac "${key}" 2>/dev/null | awk '{ print $NF }'
        return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        py="python3"
    elif command -v python >/dev/null 2>&1; then
        py="python"
    else
        return 1
    fi
    HMAC_KEY="${key}" HMAC_MESSAGE="${message}" "${py}" - <<'PY'
import hashlib
import hmac
import os
print(hmac.new(os.environ["HMAC_KEY"].encode(), os.environ["HMAC_MESSAGE"].encode(), hashlib.sha256).hexdigest())
PY
}

random_update_nonce() {
    local nonce
    if command -v openssl >/dev/null 2>&1; then
        nonce="$(openssl rand -hex 16 2>/dev/null || true)"
    fi
    if [[ -z "${nonce:-}" && -r /dev/urandom ]]; then
        nonce="$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
    fi
    [[ -n "${nonce:-}" ]] || nonce="$(date -u '+%Y%m%dT%H%M%SZ')-$RANDOM"
    printf '%s\n' "${nonce}"
}

normalize_manager_update_url() {
    local url="$1"
    url="$(trim "${url}")"
    [[ -n "${url}" ]] || return 1
    case "${url}" in
        http://*|https://*) ;;
        *) url="http://${url}" ;;
    esac
    case "${url}" in
        http://*) ;;
        https://*)
            err "PO0 到 LAN Worker 的 manager 更新入口必须使用 HTTP，不允许 HTTPS：${url}"
            return 1
            ;;
        *)
            err "manager 更新 URL 必须使用 http://"
            return 1
            ;;
    esac
    case "${url}" in
        *\?*)
            err "manager 更新 URL 不需要查询参数；脚本会自动追加 nonce 和 token_id。"
            return 1
            ;;
    esac
    case "${url}" in
        */po0-manager-update/nftables-relay-manager.sh)
            ;;
        */)
            url="${url}po0-manager-update/nftables-relay-manager.sh"
            ;;
        *)
            url="${url}/po0-manager-update/nftables-relay-manager.sh"
            ;;
    esac
    printf '%s\n' "${url}"
}
