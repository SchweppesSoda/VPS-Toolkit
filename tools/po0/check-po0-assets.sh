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
    local scan_file="${repo_root}/.tmp/po0-raw-scan.txt"
    mkdir -p "${repo_root}/.tmp"
    : > "${scan_file}"
    rg -n "raw\\.githubusercontent\\.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0|RAW_URL|GitHub raw|raw URL" \
        "${repo_root}/scripts/po0" "${repo_root}/README.md" "${repo_root}/README.en.md" "${repo_root}/AGENTS.md" \
        > "${scan_file}" || true
    if grep -Ev 'clients[\\/]egern|relay[\\/]egern|EGERN_SSH_REPORT_MODULE_RAW_URL|iplist|ipdb|proxy-services|reinstall|legacy[\\/]nftables-legacy|raw URL is disabled|raw URLs are disabled' "${scan_file}"; then
        printf 'Unexpected PO0 raw URL reference found.\n' >&2
        exit 1
    fi
}

check_versions_match_tag() {
    local tag="${GITHUB_REF_NAME:-}" expected asset version
    [[ "${tag}" =~ ^po0-v([0-9]{4}\.[0-9]{2}\.[0-9]{2})\.([0-9]+)$ ]] || return 0
    expected="${BASH_REMATCH[1]}+build.${BASH_REMATCH[2]}"
    for asset in nftables-relay-manager.sh po0-lan-client.sh po0-outbound-ip-report.sh po0-outbound-ip-report-macos.sh; do
        version="$(grep -m1 '^SCRIPT_VERSION=' "${asset_dir}/${asset}" | sed -E 's/^SCRIPT_VERSION="([^"]+)".*/\1/')"
        [[ "${version}" == "${expected}" ]] || { printf '%s version %s does not match tag %s\n' "${asset}" "${version}" "${expected}" >&2; exit 1; }
    done
    version="$(grep -m1 '^\$ScriptVersion = ' "${asset_dir}/po0-outbound-ip-report.ps1" | sed -E 's/^\$ScriptVersion = "([^"]+)".*/\1/')"
    [[ "${version}" == "${expected}" ]] || { printf 'po0-outbound-ip-report.ps1 version %s does not match tag %s\n' "${version}" "${expected}" >&2; exit 1; }
}

check_manifest_coverage "manager" "tools/po0/manifests/manager.txt" "scripts/po0/relay/manager/src"
check_manifest_coverage "lan-worker" "tools/po0/manifests/lan-worker.txt" "scripts/po0/relay/lan-worker/src"
check_manifest_coverage "self-report-linux" "tools/po0/manifests/self-report-linux.txt" "scripts/po0/relay/self-report/linux/src"
check_manifest_coverage "self-report-macos" "tools/po0/manifests/self-report-macos.txt" "scripts/po0/relay/self-report/macos/src"
check_manifest_coverage "self-report-windows" "tools/po0/manifests/self-report-windows.txt" "scripts/po0/relay/self-report/windows/src" "*.ps1"

"${repo_root}/tools/po0/build-po0-assets.sh" "${asset_dir}"

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
check_raw_refs

printf 'PO0 asset checks passed.\n'
