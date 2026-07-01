#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(git rev-parse --show-toplevel)" && pwd -P)"
asset_dir="${1:-${repo_root}/.tmp/po0-check-assets}"

manifest_entries() {
    local manifest="$1"
    awk '{
        sub(/\r$/, "")
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        if ($0 != "" && $0 !~ /^#/) print $0
    }' "${manifest}"
}

check_manifest_coverage() {
    local name="$1" manifest="$2" source_dir="$3" pattern="${4:-*.sh}" rel_source entry
    printf 'Checking manifest coverage: %s\n' "${name}"
    [[ -d "${repo_root}/${source_dir}" ]] || { printf 'Source directory not found: %s\n' "${source_dir}" >&2; exit 1; }
    rel_source="${source_dir%/}/"
    mapfile -t entries < <(manifest_entries "${repo_root}/${manifest}")
    [[ "${#entries[@]}" -gt 0 ]] || { printf 'Manifest has no entries: %s\n' "${manifest}" >&2; exit 1; }
    printf '%s\n' "${entries[@]}" | sort | uniq -d | grep -q . && {
        printf 'Duplicate manifest entry in %s\n' "${manifest}" >&2
        exit 1
    }
    for entry in "${entries[@]}"; do
        [[ "${entry}" == "${rel_source}"* ]] || { printf 'Manifest entry outside %s: %s\n' "${source_dir}" "${entry}" >&2; exit 1; }
        [[ -f "${repo_root}/${entry}" ]] || { printf 'Manifest entry does not exist: %s\n' "${entry}" >&2; exit 1; }
    done
    while IFS= read -r source; do
        printf '%s\n' "${entries[@]}" | grep -Fxq "${source}" || {
            printf 'Source part missing from manifest %s: %s\n' "${name}" "${source}" >&2
            exit 1
        }
    done < <(cd "${repo_root}" && find "${source_dir}" -maxdepth 1 -type f -name "${pattern}" -printf '%p\n' | sort)
}

check_raw_refs() {
    local scan_file="${repo_root}/.tmp/po0-raw-scan.txt" line unexpected=0
    mkdir -p "${repo_root}/.tmp"
    : > "${scan_file}"
    rg -n "raw\\.githubusercontent\\.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0|RAW_URL|GitHub raw|raw URL" \
        "${repo_root}/scripts/po0" "${repo_root}/README.md" "${repo_root}/README.en.md" "${repo_root}/AGENTS.md" \
        > "${scan_file}" || true
    while IFS= read -r line; do
        [[ "${line}" == *"raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0"* ]] || continue
        case "${line}" in
            *"scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml"*|\
            *"scripts/po0/nftables/clients/egern/po0-ssh-ip-report.js"*|\
            *"scripts/po0/relay/egern/PO0-SSH-IP-Report.yaml"*|\
            *"scripts/po0/relay/egern/po0-ssh-ip-report.js"*|\
            *"scripts/po0/nftables/tools/build-iplist-package.sh"*|\
            *"scripts/po0/nftables/tools/build-iplist-package.ps1"*|\
            *"scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh"*)
                ;;
            *)
                printf '%s\n' "${line}" >&2
                unexpected=1
                ;;
        esac
    done < "${scan_file}"
    if [[ "${unexpected}" == "1" ]]; then
        printf 'Unexpected PO0 raw URL reference found.\n' >&2
        exit 1
    fi
}

check_egern_compat_sync() {
    local file canonical legacy
    for file in PO0-SSH-IP-Report.yaml po0-ssh-ip-report.js; do
        canonical="${repo_root}/scripts/po0/nftables/clients/egern/${file}"
        legacy="${repo_root}/scripts/po0/relay/egern/${file}"
        [[ -f "${canonical}" ]] || { printf 'Canonical Egern file missing: %s\n' "${canonical}" >&2; exit 1; }
        [[ -f "${legacy}" ]] || { printf 'Legacy Egern compatibility file missing: %s\n' "${legacy}" >&2; exit 1; }
        if ! cmp -s <(tr -d '\r' < "${canonical}") <(tr -d '\r' < "${legacy}"); then
            printf 'Legacy Egern compatibility file differs from canonical after LF normalization: %s\n' "${file}" >&2
            exit 1
        fi
    done
}

check_windows_canonical_path() {
    local asset="${asset_dir}/po0-outbound-ip-report.ps1" default_script default_launcher
    grep -q 'po0-outbound-ip-report\.ps1' "${asset}" || {
        printf 'Windows self-report asset does not mention canonical po0-outbound-ip-report.ps1 path.\n' >&2
        exit 1
    }
    grep -q '^\$ScriptName = "po0-outbound-ip-report"' "${asset}" || {
        printf 'Windows self-report script name is not canonical.\n' >&2
        exit 1
    }
    default_script="$(awk '/^function Get-DefaultScriptPath /{flag=1} flag{print; if ($0 ~ /^}/) exit}' "${asset}")"
    default_launcher="$(awk '/^function Get-DefaultTaskLauncherPath /{flag=1} flag{print; if ($0 ~ /^}/) exit}' "${asset}")"
    if [[ "${default_script}" != *"po0-outbound-ip-report.ps1"* || "${default_script}" == *"po0-self-report.ps1"* ]]; then
        printf 'Windows self-report default script path is not canonical.\n' >&2
        exit 1
    fi
    if [[ "${default_launcher}" != *"po0-outbound-ip-report-task.vbs"* || "${default_launcher}" == *"po0-self-report-task.vbs"* ]]; then
        printf 'Windows self-report default launcher path is not canonical.\n' >&2
        exit 1
    fi
    default_config="$(awk '/^function Get-DefaultConfigPath /{flag=1} flag{print; if ($0 ~ /^}/) exit}' "${asset}")"
    default_log="$(awk '/^function Get-DefaultLogPath /{flag=1} flag{print; if ($0 ~ /^}/) exit}' "${asset}")"
    default_state="$(awk '/^function Get-IpCheckStatePath /{flag=1} flag{print; if ($0 ~ /^}/) exit}' "${asset}")"
    if [[ "${default_config}" != *"outbound-ip-report.json"* || "${default_config}" == *"self-report.json"* ]]; then
        printf 'Windows self-report default config path is not canonical.\n' >&2
        exit 1
    fi
    if [[ "${default_log}" != *"po0-outbound-ip-report.log"* || "${default_log}" == *"po0-self-report.log"* ]]; then
        printf 'Windows self-report default log path is not canonical.\n' >&2
        exit 1
    fi
    if [[ "${default_state}" != *"outbound-ip-report-ip-check-index.txt"* || "${default_state}" == *"self-report-ip-check-index.txt"* ]]; then
        printf 'Windows self-report IP check state path is not canonical.\n' >&2
        exit 1
    fi
    grep -q '^\$script:TaskName = "PO0 Outbound IP Report to LAN Worker"' "${asset}" || {
        printf 'Windows self-report task name is not canonical.\n' >&2
        exit 1
    }
    grep -q 'PO0_OUTBOUND_IP_REPORT_CONFIG' "${asset}" || {
        printf 'Windows self-report asset lacks canonical env aliases.\n' >&2
        exit 1
    }
}

check_unix_outbound_ip_report_canonical_path() {
    local asset="$1" platform="$2" install canonical_install config log state
    grep -q '^SCRIPT_NAME="po0-outbound-ip-report"' "${asset}" || {
        printf '%s script name is not canonical.\n' "${platform}" >&2
        exit 1
    }
    install="$(awk '/^default_install_path\(\)/{flag=1} flag{print; if ($0 ~ /^}/) exit}' "${asset}")"
    canonical_install="$(awk '/^canonical_install_path\(\)/{flag=1} flag{print; if ($0 ~ /^}/) exit}' "${asset}")"
    config="$(awk '/^canonical_config_file\(\)/{flag=1} flag{print; if ($0 ~ /^}/) exit}' "${asset}")"
    log="$(awk '/^self_report_log_path\(\)/{flag=1} flag{print; if ($0 ~ /^}/) exit}' "${asset}")"
    state="$(awk '/^ip_check_state_file\(\)/{flag=1} flag{print; if ($0 ~ /^}/) exit}' "${asset}")"
    if [[ "${install}" == *"po0-self-report"* || "${canonical_install}" != *"po0-outbound-ip-report"* || "${canonical_install}" == *"po0-self-report"* ]]; then
        printf '%s default install path is not canonical.\n' "${platform}" >&2
        exit 1
    fi
    if [[ "${config}" != *"po0-outbound-ip-report"* || "${config}" == *"po0-self-report"* ]]; then
        printf '%s default config path is not canonical.\n' "${platform}" >&2
        exit 1
    fi
    if [[ "${log}" != *"po0-outbound-ip-report.log"* || "${log}" == *"po0-self-report.log"* ]]; then
        printf '%s default log path is not canonical.\n' "${platform}" >&2
        exit 1
    fi
    if [[ "${state}" != *"po0-outbound-ip-report"* || "${state}" == *"po0-self-report"* ]]; then
        printf '%s IP check state path is not canonical.\n' "${platform}" >&2
        exit 1
    fi
    grep -q 'PO0_OUTBOUND_IP_REPORT_BEGIN' "${asset}" || {
        printf '%s cron marker is not canonical.\n' "${platform}" >&2
        exit 1
    }
    grep -q 'PO0_OUTBOUND_IP_REPORT_CONFIG' "${asset}" || {
        printf '%s asset lacks canonical env aliases.\n' "${platform}" >&2
        exit 1
    }
}

check_macos_launchd_canonical_path() {
    local asset="${asset_dir}/po0-outbound-ip-report-macos.sh" label
    label="$(awk '/^launchd_label\(\)/{flag=1} flag{print; if ($0 ~ /^}/) exit}' "${asset}")"
    if [[ "${label}" != *"fr.schweppes.po0-outbound-ip-report"* || "${label}" == *"fr.schweppes.po0-self-report"* ]]; then
        printf 'macOS launchd label is not canonical.\n' >&2
        exit 1
    fi
}

check_legacy_name_allowlist() {
    local asset line_no line start end context
    local pattern='po0-self-report|PO0_SELF_REPORT|SELF_REPORT_|PO0 Self Report|Self-report 已完成|Self-report 未完成|self-report\.json|po0-self-report\.log|fr\.schweppes\.po0-self-report|PO0_SELF_REPORT_BEGIN|PO0_SELF_REPORT_END'
    local allowed='legacy|compat|fallback|alias|shim|migrat|cleanup|old|Test-DownloadedScript|defaultScript\.Value|defaultLauncher\.Value|defaultLog\.Value|旧|兼容|迁移|回退|别名|历史|Get-Legacy|legacy_|LegacyTaskName|旧版|校验失败|grep -q|Self-report 已完成|Self-report 未完成|PO0_SELF_REPORT|SELF_REPORT_'
    for asset in "${asset_dir}/po0-outbound-ip-report.sh" "${asset_dir}/po0-outbound-ip-report-macos.sh" "${asset_dir}/po0-outbound-ip-report.ps1"; do
        while IFS=: read -r line_no line; do
            [[ -n "${line_no}" ]] || continue
            start=$((line_no > 10 ? line_no - 10 : 1))
            end=$((line_no + 10))
            context="$(sed -n "${start},${end}p" "${asset}")"
            if ! printf '%s\n' "${context}" | grep -Eiq "${allowed}"; then
                printf '%s contains legacy name outside migration/compat context at line %s: %s\n' "${asset##*/}" "${line_no}" "${line}" >&2
                exit 1
            fi
        done < <(grep -nE "${pattern}" "${asset}" || true)
    done
}

asset_version() {
    local asset="$1"
    if [[ "${asset}" == *.ps1 ]]; then
        grep -m1 '^\$ScriptVersion = ' "${asset}" | sed -E 's/^\$ScriptVersion = "([^"]+)".*/\1/'
    else
        grep -m1 '^SCRIPT_VERSION=' "${asset}" | sed -E 's/^SCRIPT_VERSION="([^"]+)".*/\1/'
    fi
}

asset_release_date() {
    local asset="$1"
    if [[ "${asset}" == *.ps1 ]]; then
        grep -m1 '^\$ScriptReleaseDate = ' "${asset}" | sed -E 's/^\$ScriptReleaseDate = "([^"]+)".*/\1/'
    else
        grep -m1 '^SCRIPT_RELEASE_DATE=' "${asset}" | sed -E 's/^SCRIPT_RELEASE_DATE="([^"]+)".*/\1/'
    fi
}

asset_has_changelog() {
    awk '
        /^# CHANGELOG_BEGIN/ {in_block=1; next}
        /^# CHANGELOG_END/ {exit}
        in_block {
            line=$0
            sub(/^# ?/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (line != "") found=1
        }
        END {exit found ? 0 : 1}
    ' "$1"
}

check_versions_consistent() {
    local expected="" asset version date
    for asset in nftables-relay-manager.sh po0-lan-client.sh po0-outbound-ip-report.sh po0-outbound-ip-report-macos.sh po0-outbound-ip-report.ps1; do
        version="$(asset_version "${asset_dir}/${asset}")"
        [[ -n "${version}" ]] || { printf 'Could not read version from %s\n' "${asset}" >&2; exit 1; }
        if [[ -z "${expected}" ]]; then
            expected="${version}"
        elif [[ "${version}" != "${expected}" ]]; then
            printf '%s version %s does not match %s\n' "${asset}" "${version}" "${expected}" >&2
            exit 1
        fi
        date="$(asset_release_date "${asset_dir}/${asset}")"
        [[ "${date}" == "2026-07-01" ]] || { printf '%s release date %s is unexpected\n' "${asset}" "${date}" >&2; exit 1; }
        asset_has_changelog "${asset_dir}/${asset}" || { printf '%s changelog block is empty\n' "${asset}" >&2; exit 1; }
    done
}

check_versions_match_tag() {
    local tag="${GITHUB_REF_NAME:-}" expected asset version
    [[ -n "${tag}" ]] || return 0
    if [[ ! "${tag}" =~ ^po0-v([0-9]{4}\.[0-9]{2}\.[0-9]{2})\.([0-9]+)$ ]]; then
        printf 'GITHUB_REF_NAME is set but is not a PO0 release tag: %s\n' "${tag}" >&2
        exit 1
    fi
    expected="${BASH_REMATCH[1]}+build.${BASH_REMATCH[2]}"
    for asset in nftables-relay-manager.sh po0-lan-client.sh po0-outbound-ip-report.sh po0-outbound-ip-report-macos.sh; do
        version="$(grep -m1 '^SCRIPT_VERSION=' "${asset_dir}/${asset}" | sed -E 's/^SCRIPT_VERSION="([^"]+)".*/\1/')"
        [[ "${version}" == "${expected}" ]] || { printf '%s version %s does not match tag %s\n' "${asset}" "${version}" "${expected}" >&2; exit 1; }
    done
    version="$(grep -m1 '^\$ScriptVersion = ' "${asset_dir}/po0-outbound-ip-report.ps1" | sed -E 's/^\$ScriptVersion = "([^"]+)".*/\1/')"
    [[ "${version}" == "${expected}" ]] || { printf 'po0-outbound-ip-report.ps1 version %s does not match tag %s\n' "${version}" "${expected}" >&2; exit 1; }
}

check_asset_inventory() {
    local expected actual checksum_names
    expected="$(printf '%s\n' checksums.txt nftables-relay-manager.sh po0-lan-client.sh po0-outbound-ip-report-macos.sh po0-outbound-ip-report.ps1 po0-outbound-ip-report.sh | sort)"
    actual="$(find "${asset_dir}" -maxdepth 1 -type f -printf '%f\n' | sort)"
    if [[ "${actual}" != "${expected}" ]]; then
        printf 'Unexpected PO0 asset inventory.\nExpected:\n%s\nActual:\n%s\n' "${expected}" "${actual}" >&2
        exit 1
    fi
    checksum_names="$(awk '{print $2}' "${asset_dir}/checksums.txt" | sort)"
    if [[ "${checksum_names}" != "$(printf '%s\n' nftables-relay-manager.sh po0-lan-client.sh po0-outbound-ip-report-macos.sh po0-outbound-ip-report.ps1 po0-outbound-ip-report.sh | sort)" ]]; then
        printf 'checksums.txt does not cover the exact asset set.\n' >&2
        exit 1
    fi
    (cd "${asset_dir}" && sha256sum -c checksums.txt >/dev/null)
}

check_manifest_coverage "manager" "tools/po0/manifests/manager.txt" "scripts/po0/relay/manager/src"
check_manifest_coverage "lan-worker" "tools/po0/manifests/lan-worker.txt" "scripts/po0/relay/lan-worker/src"
check_manifest_coverage "self-report-linux" "tools/po0/manifests/self-report-linux.txt" "scripts/po0/relay/self-report/linux/src"
check_manifest_coverage "self-report-macos" "tools/po0/manifests/self-report-macos.txt" "scripts/po0/relay/self-report/macos/src"
check_manifest_coverage "self-report-windows" "tools/po0/manifests/self-report-windows.txt" "scripts/po0/relay/self-report/windows/src" "*.ps1"

bash "${repo_root}/tools/po0/build-po0-assets.sh" "${asset_dir}"

for asset in nftables-relay-manager.sh po0-lan-client.sh po0-outbound-ip-report.sh po0-outbound-ip-report-macos.sh; do
    printf 'Checking bash -n %s\n' "${asset}"
    bash -n "${asset_dir}/${asset}"
done

if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -Command "\$tokens=\$null; \$errors=\$null; [System.Management.Automation.Language.Parser]::ParseFile('${asset_dir}/po0-outbound-ip-report.ps1',[ref]\$tokens,[ref]\$errors) | Out-Null; if (\$errors.Count -gt 0) { \$errors | ForEach-Object { Write-Error \$_.Message }; exit 1 }"
else
    printf 'pwsh not found; skipping PowerShell parser check.\n' >&2
fi

bash "${asset_dir}/nftables-relay-manager.sh" --version >/dev/null
bash "${asset_dir}/nftables-relay-manager.sh" --changelog >/dev/null
bash "${asset_dir}/po0-lan-client.sh" --version >/dev/null
bash "${asset_dir}/po0-outbound-ip-report.sh" --version >/dev/null
bash "${asset_dir}/po0-outbound-ip-report.sh" --changelog >/dev/null
bash "${asset_dir}/po0-outbound-ip-report-macos.sh" --version >/dev/null
bash "${asset_dir}/po0-outbound-ip-report-macos.sh" --changelog >/dev/null

check_versions_match_tag
check_versions_consistent
check_raw_refs
check_egern_compat_sync
check_asset_inventory
check_unix_outbound_ip_report_canonical_path "${asset_dir}/po0-outbound-ip-report.sh" "Linux/OpenWrt"
check_unix_outbound_ip_report_canonical_path "${asset_dir}/po0-outbound-ip-report-macos.sh" "macOS"
check_macos_launchd_canonical_path
check_windows_canonical_path
check_legacy_name_allowlist

printf 'PO0 asset checks passed.\n'
