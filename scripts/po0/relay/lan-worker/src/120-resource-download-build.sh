progress_cat() {
    local file="$1"
    local total="${2:-0}"
    local block_size=262144 blocks idx sent percent
    if command -v pv >/dev/null 2>&1 && [[ "${total}" =~ ^[0-9]+$ && "${total}" -gt 0 ]]; then
        pv -f -p -t -e -r -b -s "${total}" "${file}"
        return $?
    fi
    if ! [[ "${total}" =~ ^[0-9]+$ ]] || [[ "${total}" -le 0 ]]; then
        cat "${file}"
        return $?
    fi
    blocks=$(((total + block_size - 1) / block_size))
    idx=0
    while [[ "${idx}" -lt "${blocks}" ]]; do
        dd if="${file}" bs="${block_size}" skip="${idx}" count=1 2>/dev/null || return 1
        sent=$(((idx + 1) * block_size))
        [[ "${sent}" -gt "${total}" ]] && sent="${total}"
        percent=$((sent * 100 / total))
        printf '\r上传进度：%3s%% %s/%s bytes' "${percent}" "${sent}" "${total}" >&2
        idx=$((idx + 1))
    done
    printf '\n' >&2
}

iplist_parallel_jobs() {
    local jobs="${IPLIST_JOBS:-16}"
    [[ "${jobs}" =~ ^[0-9]+$ ]] || jobs=16
    (( jobs >= 1 )) || jobs=1
    (( jobs <= 50 )) || jobs=50
    printf '%s\n' "${jobs}"
}

relative_iplist_data_path() {
    local url="$1"
    case "${url}" in
        */iplist/data/cncity/*.txt)
            printf '%s\n' "data/cncity/${url#*/iplist/data/cncity/}"
            ;;
        */data/cncity/*.txt)
            printf '%s\n' "data/cncity/${url#*/data/cncity/}"
            ;;
        *)
            return 1
            ;;
    esac
}

xargs_supports_parallel() {
    command -v xargs >/dev/null 2>&1 || return 1
    printf 'test\0' | xargs -0 -n 1 -P 1 sh -c ':' _ >/dev/null 2>&1
}

build_iplist_resource() {
    local output="$1"
    local work doc urls queue url rel supported=0 jobs
    work="$(mktemp -d "${TMPDIR:-/tmp}/po0-iplist-worker.XXXXXX")" || return 1
    doc="${work}/docs/cncity.md"
    urls="${work}/urls.txt"
    queue="${work}/download-queue.bin"
    mkdir -p "${work}/docs" "${work}/data/cncity" || {
        rm -rf -- "${work}"
        return 1
    }
    fetch_to_file "https://raw.githubusercontent.com/metowolf/iplist/refs/heads/master/docs/cncity.md" "${doc}" || {
        rm -rf -- "${work}"
        return 1
    }
    grep -Eo 'https?://[^|[:space:]]+\.txt' "${doc}" | sort -u > "${urls}"
    [[ -s "${urls}" ]] || {
        rm -rf -- "${work}"
        return 1
    }
    : > "${queue}" || {
        rm -rf -- "${work}"
        return 1
    }
    while IFS= read -r url; do
        rel="$(relative_iplist_data_path "${url}")" || continue
        ((supported++))
        printf '%s\0%s\0%s\0%s\0' "${supported}" "${rel}" "${url}" "${work}/${rel}" >> "${queue}"
    done < "${urls}"
    [[ "${supported}" -gt 0 ]] || {
        rm -rf -- "${work}"
        return 1
    }
    jobs="$(iplist_parallel_jobs)"
    printf 'iplist 数据下载：%s 个文件，并发 %s\n' "${supported}" "${jobs}"
    if [[ "${jobs}" -gt 1 ]] && xargs_supports_parallel; then
        TOTAL_SUPPORTED="${supported}" xargs -0 -n 4 -P "${jobs}" bash -c '
idx="$1"
rel="$2"
url="$3"
output="$4"
mkdir -p "$(dirname "${output}")"
printf "[%s/%s] %s\n" "${idx}" "${TOTAL_SUPPORTED}" "${rel}"
if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 180 "${url}" -o "${output}"
elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=180 "${url}" -O "${output}"
else
    echo "系统缺少 curl 或 wget。" >&2
    exit 1
fi
' _ < "${queue}" || {
            rm -rf -- "${work}"
            return 1
        }
    else
        [[ "${jobs}" -gt 1 ]] && printf '当前 xargs 不支持并发参数，退回逐个下载。\n' >&2
        while IFS= read -r -d '' _idx && IFS= read -r -d '' rel && IFS= read -r -d '' url && IFS= read -r -d '' _output; do
            printf '[%s/%s] %s\n' "${_idx}" "${supported}" "${rel}"
            mkdir -p "${work}/${rel%/*}" || {
                rm -rf -- "${work}"
                return 1
            }
            fetch_to_file "${url}" "${work}/${rel}" || {
                rm -rf -- "${work}"
                return 1
            }
        done < "${queue}"
    fi
    tar -czf "${output}" -C "${work}" docs data || {
        rm -rf -- "${work}"
        return 1
    }
    rm -rf -- "${work}"
}

sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${file}" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${file}" | awk '{print $1}'
    else
        return 1
    fi
}
