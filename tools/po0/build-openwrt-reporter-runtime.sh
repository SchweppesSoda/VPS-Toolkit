#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
manifest="${repo_root}/packaging/openwrt/po0-outbound-ip-report/runtime-manifest.txt"
output="${1:?Output path is required}"
tmp="${output}.tmp.$$"
index=0

cleanup() {
    rm -f "${tmp}"
}
trap cleanup EXIT

: > "${tmp}"
while IFS= read -r entry; do
    entry="${entry%$'\r'}"
    [[ -n "${entry}" && "${entry}" != \#* ]] || continue
    source_file="${repo_root}/${entry}"
    [[ -f "${source_file}" ]] || { printf 'Runtime manifest entry not found: %s\n' "${entry}" >&2; exit 1; }
    if (( index == 0 )); then
        perl -0pe 's/\A\xEF\xBB\xBF//; s/\r\n?/\n/g; s/\n+\z/\n/' "${source_file}" >> "${tmp}"
    else
        printf '\n' >> "${tmp}"
        perl -0pe 's/\A\xEF\xBB\xBF//; s/\A#![^\n]*\n//; s/\r\n?/\n/g; s/\n+\z/\n/' "${source_file}" >> "${tmp}"
    fi
    index=$((index + 1))
done < "${manifest}"

(( index > 0 )) || { printf 'OpenWrt reporter runtime manifest is empty.\n' >&2; exit 1; }
bash -n "${tmp}"
mkdir -p "$(dirname "${output}")"
mv "${tmp}" "${output}"
chmod 0755 "${output}"
