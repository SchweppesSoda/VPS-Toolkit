#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(git rev-parse --show-toplevel)" && pwd -P)"
output_dir="${1:-${repo_root}/.tmp/po0-assets}"

case "${output_dir}" in
    /*) ;;
    [A-Za-z]:/*) output_dir="$(cd "$(dirname "${output_dir}")" && pwd -P)/$(basename "${output_dir}")" ;;
    *) output_dir="${PWD}/${output_dir}" ;;
esac
output_dir="$(mkdir -p "$(dirname "${output_dir}")" && cd "$(dirname "${output_dir}")" && pwd -P)/$(basename "${output_dir}")"
tmp_root="$(cd "${repo_root}/.tmp" 2>/dev/null || { mkdir -p "${repo_root}/.tmp"; cd "${repo_root}/.tmp"; } && pwd -P)"

case "${output_dir}" in
    "${tmp_root}/po0-"*) ;;
    *)
        printf 'Output directory must be inside repo .tmp and start with po0-: %s\n' "${output_dir}" >&2
        exit 1
        ;;
esac

normalize_text() {
    perl -0pe 's/\A\xEF\xBB\xBF//; s/\r\n?/\n/g; s/\n+\z//'
}

manifest_entries() {
    local manifest="$1"
    awk '{
        sub(/\r$/, "")
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        if ($0 != "" && $0 !~ /^#/) print $0
    }' "${manifest}"
}

join_manifest() {
    local manifest="$1" output="$2" require_shebang="${3:-1}" bom="${4:-0}" index=0 entry source content
    if [[ "${bom}" == "1" ]]; then
        printf '\357\273\277' > "${output}"
    else
        : > "${output}"
    fi
    while IFS= read -r entry; do
        source="${repo_root}/${entry}"
        [[ -f "${source}" ]] || { printf 'Manifest entry not found: %s\n' "${entry}" >&2; exit 1; }
        content="$(normalize_text < "${source}")"
        if (( index > 0 )); then
            content="$(printf '%s' "${content}" | perl -0pe 's/\A#![^\n]*\n//')"
            printf '\n\n' >> "${output}"
        fi
        printf '%s' "${content}" >> "${output}"
        index=$((index + 1))
    done < <(manifest_entries "${manifest}")
    [[ "${index}" -gt 0 ]] || { printf 'Manifest has no entries: %s\n' "${manifest}" >&2; exit 1; }
    printf '\n' >> "${output}"
    [[ "${require_shebang}" != "1" ]] || head -n 1 "${output}" | grep -q '^#!' || {
        printf 'Built shell asset must start with a shebang: %s\n' "${output}" >&2
        exit 1
    }
}

write_checksums() {
    local dir="$1"
    (
        cd "${dir}"
        find . -maxdepth 1 -type f ! -name checksums.txt -printf '%f\n' |
            sort |
            while IFS= read -r file; do
                printf '%s  %s\n' "$(sha256sum "${file}" | awk '{print $1}')" "${file}"
            done
    ) > "${dir}/checksums.txt"
}

rm -rf "${output_dir}"
mkdir -p "${output_dir}"

join_manifest "${repo_root}/tools/po0/manifests/manager.txt" "${output_dir}/nftables-relay-manager.sh" 1 0
join_manifest "${repo_root}/tools/po0/manifests/lan-worker.txt" "${output_dir}/po0-lan-client.sh" 1 0
join_manifest "${repo_root}/tools/po0/manifests/wan-probe-openwrt.txt" "${output_dir}/po0-wan-probe.sh" 1 0
join_manifest "${repo_root}/tools/po0/manifests/self-report-linux.txt" "${output_dir}/po0-outbound-ip-report.sh" 1 0
join_manifest "${repo_root}/tools/po0/manifests/self-report-macos.txt" "${output_dir}/po0-outbound-ip-report-macos.sh" 1 0
join_manifest "${repo_root}/tools/po0/manifests/self-report-windows.txt" "${output_dir}/po0-outbound-ip-report.ps1" 0 1
write_checksums "${output_dir}"

printf 'Built PO0 assets in %s\n' "${output_dir}"
