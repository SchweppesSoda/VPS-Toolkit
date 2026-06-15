#!/usr/bin/env bash
set -euo pipefail

OUT_FILE="${1:-${HOME}/Desktop/iplist.tar.gz}"
PARALLEL="${IPLIST_JOBS:-${2:-8}}"
DOC_URL="https://raw.githubusercontent.com/metowolf/iplist/refs/heads/master/docs/cncity.md"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/po0-iplist.XXXXXX")"
URL_LIST="${WORK_DIR}/urls.txt"
QUEUE_FILE="${WORK_DIR}/download-queue.bin"

if ! [[ "${PARALLEL}" =~ ^[0-9]+$ ]] || [[ "${PARALLEL}" -lt 1 ]]; then
    echo "Parallel job count must be a positive integer" >&2
    exit 1
fi

cleanup() {
    rm -rf -- "${WORK_DIR}"
}
trap cleanup EXIT

mkdir -p "${WORK_DIR}/docs" "${WORK_DIR}/data"

fetch() {
    local url="$1"
    local output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --connect-timeout 10 --max-time 60 "${url}" -o "${output}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "${url}" -O "${output}"
    else
        echo "curl or wget is required" >&2
        return 1
    fi
}

relative_data_path() {
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

fetch "${DOC_URL}" "${WORK_DIR}/docs/cncity.md"

grep -Eo 'https?://[^|[:space:]]+\.txt' "${WORK_DIR}/docs/cncity.md" | sort -u > "${URL_LIST}"
if [[ ! -s "${URL_LIST}" ]]; then
    echo "No data URLs found in cncity.md" >&2
    exit 1
fi

idx=0
supported=0
: > "${QUEUE_FILE}"
while IFS= read -r url; do
    ((idx+=1))
    rel="$(relative_data_path "${url}")" || {
        echo "Skip unsupported URL: ${url}" >&2
        continue
    }
    ((supported+=1))
    printf '%s\0%s\0%s\0%s\0' "${supported}" "${rel}" "${url}" "${WORK_DIR}/${rel}" >> "${QUEUE_FILE}"
done < "${URL_LIST}"

if [[ "${supported}" -eq 0 ]]; then
    echo "No supported data/cncity URLs found in cncity.md" >&2
    exit 1
fi

TOTAL_SUPPORTED="${supported}" xargs -0 -n 4 -P "${PARALLEL}" bash -c '
idx="$1"
rel="$2"
url="$3"
output="$4"
mkdir -p "$(dirname "${output}")"
printf "[%s/%s] %s\n" "${idx}" "${TOTAL_SUPPORTED}" "${rel}"
if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 10 --max-time 60 "${url}" -o "${output}"
elif command -v wget >/dev/null 2>&1; then
    wget -q "${url}" -O "${output}"
else
    echo "curl or wget is required" >&2
    exit 1
fi
' _ < "${QUEUE_FILE}"

mkdir -p "$(dirname "${OUT_FILE}")"
tar -czf "${OUT_FILE}" -C "${WORK_DIR}" docs data
printf 'Created: %s\n' "${OUT_FILE}"
