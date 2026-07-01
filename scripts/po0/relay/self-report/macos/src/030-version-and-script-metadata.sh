self_report_completed() {
    printf '%bPO0 Outbound IP Report 已完成：%s%b\n' "${C_GREEN}" "$1" "${C_RESET}"
}

self_report_incomplete() {
    printf '%bPO0 Outbound IP Report 未完成：%s%b\n' "${C_RED}" "$1" "${C_RESET}" >&2
}

script_file_var() {
    local file="$1"
    local name="$2"
    awk -F= -v key="${name}" '
        $1 == key {
            value=$0
            sub("^[^=]*=", "", value)
            gsub(/^[[:space:]]*"/, "", value)
            gsub(/"[[:space:]]*$/, "", value)
            print value
            exit
        }
    ' "${file}" 2>/dev/null || true
}

script_file_changelog() {
    local file="$1"
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

current_script_source_file() {
    local source="${BASH_SOURCE[0]:-}" dir base abs_dir
    case "${source}" in
        ""|"-"|"/dev/stdin"|/dev/fd/*|/proc/self/fd/*) return 1 ;;
    esac
    [[ -f "${source}" ]] || return 1
    if command -v readlink >/dev/null 2>&1; then
        readlink -f "${source}" 2>/dev/null && return 0
    fi
    if command -v realpath >/dev/null 2>&1; then
        realpath "${source}" 2>/dev/null && return 0
    fi
    case "${source}" in
        /*) printf '%s\n' "${source}" ;;
        *)
            dir="${source%/*}"
            base="${source##*/}"
            [[ "${dir}" == "${source}" ]] && dir="."
            if abs_dir="$(cd -P -- "${dir}" 2>/dev/null && pwd -P)"; then
                printf '%s/%s\n' "${abs_dir}" "${base}"
            else
                printf '%s\n' "${source}"
            fi
            ;;
    esac
}

current_script_path() {
    local source="${BASH_SOURCE[0]:-}" path
    if path="$(current_script_source_file)"; then
        printf '%s\n' "${path}"
        return 0
    fi
    case "${source}" in
        ""|"-"|"bash"|"main"|"/dev/stdin"|/dev/fd/*|/proc/self/fd/*)
            printf '标准输入（bash -s / curl | bash，未落盘）\n'
            ;;
        *)
            printf '未知（%s 不可读）\n' "${source}"
            ;;
    esac
}

script_build_label() {
    if [[ "${SCRIPT_VERSION}" == *"+"* ]]; then
        printf '%s\n' "${SCRIPT_VERSION#*+}"
    else
        printf '未标识\n'
    fi
}

show_version() {
    printf '%s\n' \
        "脚本名称：${SCRIPT_NAME}" \
        "版本：${SCRIPT_VERSION}" \
        "构建标识：$(script_build_label)" \
        "发布日期：${SCRIPT_RELEASE_DATE}" \
        "执行来源：$(current_script_path)" \
        "默认安装路径：$(default_install_path)" \
        "配置文件：${CONFIG_FILE}" \
        "定时上报：$(cron_status_summary)" \
        "通知模式：$(notify_status_label)" \
        "下载 URL：${DOWNLOAD_URL}"
}

show_changelog() {
    local changelog script_file=""
    script_file="$(current_script_source_file || true)"
    if [[ -n "${script_file}" ]] && changelog="$(script_file_changelog "${script_file}")"; then
        printf '%s\n' "${changelog}"
    else
        printf '当前脚本未提供更新内容。\n'
    fi
}
