#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
sdk_root="${1:?ImmortalWrt SDK directory is required}"
asset_dir="${2:-${repo_root}/.tmp/po0-check-assets}"
output_dir="${3:-${repo_root}/.tmp/po0-apks}"

[[ -f "${sdk_root}/rules.mk" && -f "${sdk_root}/include/package.mk" ]] || {
    printf 'Invalid ImmortalWrt SDK directory: %s\n' "${sdk_root}" >&2
    exit 1
}
for asset in po0-wan-probe.sh po0-outbound-ip-report.sh; do
    [[ -s "${asset_dir}/${asset}" ]] || { printf 'Missing PO0 asset: %s\n' "${asset}" >&2; exit 1; }
done

mkdir -p "${sdk_root}/package" "${sdk_root}/po0-assets" "${output_dir}"
for package in po0-wan-probe po0-outbound-ip-report; do
    [[ ! -e "${sdk_root}/package/${package}" ]] || {
        printf 'SDK package path already exists: %s\n' "${sdk_root}/package/${package}" >&2
        exit 1
    }
    cp -R "${repo_root}/packaging/openwrt/${package}" "${sdk_root}/package/${package}"
done
cp "${asset_dir}/po0-wan-probe.sh" "${sdk_root}/po0-assets/po0-wan-probe.sh"
cp "${asset_dir}/po0-outbound-ip-report.sh" "${sdk_root}/po0-assets/po0-outbound-ip-report.sh"

make -C "${sdk_root}" defconfig
make -C "${sdk_root}" package/po0-wan-probe/compile package/po0-outbound-ip-report/compile V=s

for package in po0-wan-probe po0-outbound-ip-report; do
    built="$(find "${sdk_root}/bin/packages" -type f -name "${package}-*.apk" -print -quit)"
    [[ -n "${built}" ]] || { printf 'Built APK not found: %s\n' "${package}" >&2; exit 1; }
    cp "${built}" "${output_dir}/${package}.apk"
done

printf 'Built PO0 APKs in %s\n' "${output_dir}"

