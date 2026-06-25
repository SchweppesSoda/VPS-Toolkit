cleanup_temp_files() {
    local tmp
    for tmp in "${TEMP_FILES[@]}"; do
        [[ -e "${tmp}" ]] && rm -f -- "${tmp}" 2>/dev/null || true
    done
    for tmp in "${TEMP_DIRS[@]}"; do
        [[ -d "${tmp}" ]] && rm -rf -- "${tmp}" 2>/dev/null || true
    done
}

trap cleanup_temp_files EXIT
trap 'cleanup_temp_files; exit 130' INT
trap 'cleanup_temp_files; exit 143' TERM

make_temp_file() {
    local target="$1"
    local dir base tmp
    dir="$(dirname "${target}")"
    base="$(basename "${target}")"
    tmp="$(mktemp "${dir}/${base}.tmp.XXXXXX")" || return 1
    TEMP_FILES+=("${tmp}")
    TEMP_FILE_RESULT="${tmp}"
}

make_temp_dir() {
    local parent="$1"
    local prefix="$2"
    local tmp
    mkdir -p "${parent}" || return 1
    tmp="$(mktemp -d "${parent}/${prefix}.XXXXXX")" || return 1
    TEMP_DIRS+=("${tmp}")
    TEMP_DIR_RESULT="${tmp}"
}

dynamic_state_lock() {
    [[ "${DYNAMIC_STATE_LOCK_HELD:-0}" == "1" ]] && return 0
    mkdir -p "${CONF_DIR}" || return 1
    exec 8>"${DYNAMIC_STATE_LOCK_FILE}" || return 1
    if command -v flock >/dev/null 2>&1; then
        flock -w 15 8 || {
            err "动态来源状态文件正忙，请稍后重试。"
            exec 8>&- 2>/dev/null || true
            return 1
        }
    fi
    DYNAMIC_STATE_LOCK_HELD=1
}

dynamic_state_unlock() {
    [[ "${DYNAMIC_STATE_LOCK_HELD:-0}" == "1" ]] || return 0
    if command -v flock >/dev/null 2>&1; then
        flock -u 8 2>/dev/null || true
    fi
    exec 8>&- 2>/dev/null || true
    DYNAMIC_STATE_LOCK_HELD=0
}

with_dynamic_state_lock() {
    local rc
    if [[ "${DYNAMIC_STATE_LOCK_HELD:-0}" == "1" ]]; then
        "$@"
        return $?
    fi
    dynamic_state_lock || return 1
    "$@"
    rc=$?
    dynamic_state_unlock
    return "${rc}"
}
