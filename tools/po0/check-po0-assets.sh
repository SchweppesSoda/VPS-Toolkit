#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(git rev-parse --show-toplevel)" && pwd -P)"
asset_dir="${1:-${repo_root}/.tmp/po0-check-assets-bash}"
expected_po0_version="${PO0_EXPECTED_ASSET_VERSION:-2026.09.05+build.8}"
expected_po0_release_date="${PO0_EXPECTED_RELEASE_DATE:-2026-09-05}"
expected_po0_release_tag="${PO0_EXPECTED_RELEASE_TAG:-po0-v2026.09.05.8}"

manifest_entries() {
    local manifest="$1"
    awk '{
        sub(/\r$/, "")
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        if ($0 != "" && $0 !~ /^#/) print $0
    }' "${manifest}"
}

pwsh_literal_path() {
    local path="$1"
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "${path}"
    else
        printf '%s\n' "${path}"
    fi
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
            *"scripts/po0/nftables/clients/loon/PO0.LAN-Report.lpx"*|\
            *"scripts/po0/nftables/clients/loon/po0-loon-report.js"*|\
            *"scripts/po0/nftables/clients/stash/po0-stash-report.js"*|\
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

check_egern_ssid_guard() {
    local yaml="${repo_root}/scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml"
    local js="${repo_root}/scripts/po0/nftables/clients/egern/po0-ssh-ip-report.js"
    local guard_line detect_line
    grep -Eq '^[[:space:]]+SKIP_WIFI_SSIDS:' "${yaml}" || {
        printf 'Egern YAML lacks SKIP_WIFI_SSIDS env configuration.\n' >&2
        exit 1
    }
    grep -Fq '保存本机 PO0 上报配置' "${yaml}" || { printf 'Egern YAML lacks native storage save action.\n' >&2; exit 1; }
    grep -Fq '清除本机 PO0 上报配置' "${yaml}" || { printf 'Egern YAML lacks native storage clear action.\n' >&2; exit 1; }
    grep -Fq 'normalizeSsidSkipList' "${js}" || { printf 'Egern JS lacks SSID skip list normalizer.\n' >&2; exit 1; }
    grep -Fq 'currentWifiSsidFromNetwork' "${js}" || { printf 'Egern JS lacks raw Wi-Fi SSID reader.\n' >&2; exit 1; }
    grep -Fq 'ssidSkipDecision' "${js}" || { printf 'Egern JS lacks SSID skip decision helper.\n' >&2; exit 1; }
    grep -Fq 'isAutomaticReportRun' "${js}" || { printf 'Egern JS lacks explicit automatic trigger helper.\n' >&2; exit 1; }
    grep -Fq 'CONFIG_STORAGE_KEY' "${js}" || { printf 'Egern JS lacks native config storage key.\n' >&2; exit 1; }
    grep -Fq 'persistableEnvValues' "${js}" || { printf 'Egern JS lacks persisted env whitelist helper.\n' >&2; exit 1; }
    grep -Fq 'reportConfigSaveCandidate' "${js}" || { printf 'Egern JS lacks storage-first save merge helper.\n' >&2; exit 1; }
    grep -Fq 'storedReportConfig' "${js}" || { printf 'Egern JS lacks native stored config reader.\n' >&2; exit 1; }
    grep -Fq 'handleReportConfigSaveScript' "${js}" || { printf 'Egern JS lacks native config save handler.\n' >&2; exit 1; }
    grep -Fq 'handleReportConfigClearScript' "${js}" || { printf 'Egern JS lacks native config clear handler.\n' >&2; exit 1; }
    grep -Fq "skipType: 'missing-config'" "${js}" || { printf 'Egern JS lacks silent missing-config marker.\n' >&2; exit 1; }
    grep -Fq "skipType: 'wifi-ssid'" "${js}" || { printf 'Egern JS lacks wifi-ssid skipped state marker.\n' >&2; exit 1; }
    grep -Fq 'skipReason:' "${js}" || {
        printf 'Egern JS lacks local skip/no-upload wording.\n' >&2
        exit 1
    }
    if grep -Eq 'PO0_SELF_REPORT_[A-Z0-9_]*SSID|SELF_REPORT_[A-Z0-9_]*SSID' "${yaml}" "${js}" "${repo_root}/scripts/po0/relay/egern/PO0-SSH-IP-Report.yaml" "${repo_root}/scripts/po0/relay/egern/po0-ssh-ip-report.js"; then
        printf 'Egern SSID guard must not define legacy self-report SSID aliases.\n' >&2
        exit 1
    fi
    guard_line="$(
        awk '
            /^async function runEgernReportUnlocked/ {in_fn=1}
            in_fn && /ssidSkipDecision\(ctx, env, network\)/ {print NR; exit}
        ' "${js}"
    )"
    detect_line="$(
        awk '
            /^async function runEgernReportUnlocked/ {in_fn=1}
            in_fn && /detectCurrentIPv4WithFallback\(ctx, env, policy\)/ {print NR; exit}
        ' "${js}"
    )"
    [[ -n "${guard_line}" ]] || { printf 'Egern JS lacks SSID guard inside default report flow.\n' >&2; exit 1; }
    [[ -n "${detect_line}" ]] || { printf 'Egern JS IPv4 detection call not found in default report flow.\n' >&2; exit 1; }
    if (( guard_line >= detect_line )); then
        printf 'Egern SSID guard must run before public IPv4 detection.\n' >&2
        exit 1
    fi
    if awk '
        /^async function reportToPO0\(/ {in_fn=1}
        in_fn && tolower($0) ~ /ssid/ {found=1}
        in_fn && /^}/ {exit}
        END {exit found ? 0 : 1}
    ' "${js}"; then
        printf 'Egern reportToPO0 must not pass SSID through SSH report args.\n' >&2
        exit 1
    fi
}

check_egern_official_channel() {
    local yaml="${repo_root}/scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml"
    local js="${repo_root}/scripts/po0/nftables/clients/egern/po0-ssh-ip-report.js"
    local official_line worker_line
    grep -Fq 'PO0_FIREWALL_TOKENS:' "${yaml}" || {
        printf 'Egern YAML lacks the persisted PO0_FIREWALL_TOKENS setting.\n' >&2
        exit 1
    }
    grep -Fq 'PO0 官方防火墙状态（只读）' "${yaml}" || {
        printf 'Egern YAML lacks the official firewall read-only status action.\n' >&2
        exit 1
    }
    for token in \
        'OFFICIAL_FIREWALL_INTERVAL_SECONDS = 600' \
        'OFFICIAL_FIREWALL_API_BASE' \
        'parseOfficialTokens' \
        'officialDirectRequest' \
        'officialDisplaySlot' \
        'runOfficialFirewall' \
        "policy: 'DIRECT'" \
        'isOfficialStatusRun'; do
        grep -Fq "${token}" "${js}" || {
            printf 'Egern JS lacks official firewall contract marker: %s\n' "${token}" >&2
            exit 1
        }
    done
    official_line="$({
        awk '
            /^async function runEgernReportUnlocked/ {in_fn=1}
            in_fn && /runOfficialFirewall\(ctx, env/ {print NR; exit}
        ' "${js}"
    })"
    worker_line="$({
        awk '
            /^async function runEgernReportUnlocked/ {in_fn=1}
            in_fn && /reportToPO0\(ctx, env, target, ip\)/ {print NR; exit}
        ' "${js}"
    })"
    [[ -n "${official_line}" && -n "${worker_line}" && "${official_line}" -lt "${worker_line}" ]] || {
        printf 'Egern official firewall lane must run before the existing SSH lane.\n' >&2
        exit 1
    }
}

check_lan_worker_official_channel() {
    local source="${repo_root}/scripts/po0/relay/lan-worker/src/055-official-firewall.sh"
    [[ -f "${source}" ]] || {
        printf 'LAN Worker official firewall source is missing.\n' >&2
        exit 1
    }
    for token in \
        'PO0_FIREWALL_TOKENS' \
        'PO0_FIREWALL_API_BASE_URL="https://124.221.69.228/api/firewall"' \
        'PO0_FIREWALL_INTERVAL_SECONDS="600"' \
        'official_run_lock_acquire' \
        'official_response_valid' \
        'official_direct_request'; do
        grep -Fq -- "${token}" "${source}" || {
            printf 'LAN Worker official firewall source lacks contract marker: %s\n' "${token}" >&2
            exit 1
        }
    done
    grep -Fq 'request = "%s"' "${source}" || {
        printf 'LAN Worker official firewall source must keep the request method in curl config stdin.\n' >&2
        exit 1
    }
    local dispatch="${repo_root}/scripts/po0/relay/lan-worker/src/990-main-menu-dispatch.sh"
    for token in '--official-firewall-status' '--run-official-firewall' '--scheduled-run'; do
        grep -Fq -- "${token}" "${dispatch}" || {
            printf 'LAN Worker dispatch lacks official firewall action marker: %s\n' "${token}" >&2
            exit 1
        }
    done
    for source in \
        "${repo_root}/scripts/po0/relay/lan-worker/src/160-webauth-server.sh" \
        "${repo_root}/scripts/po0/relay/lan-worker/src/180-self-report-server.sh"; do
        grep -Fq 'env -u PO0_FIREWALL_TOKENS' "${source}" || {
            printf 'LAN Worker Python service leaks PO0_FIREWALL_TOKENS to its child: %s\n' "${source}" >&2
            exit 1
        }
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
    grep -q '^\$script:TaskName = "Outbound IP Report"' "${asset}" || {
        printf 'Windows self-report task name is not canonical.\n' >&2
        exit 1
    }
    grep -q '\$script:TaskName = "PO0 Outbound IP Report to LAN Worker"' "${asset}" || {
        printf 'Windows self-report asset lacks build.1 upgrade compatibility marker.\n' >&2
        exit 1
    }
    grep -q 'PO0_OUTBOUND_IP_REPORT_CONFIG' "${asset}" || {
        printf 'Windows self-report asset lacks canonical env aliases.\n' >&2
        exit 1
    }
    grep -q 'Cleanup-LegacySelfReportArtifacts' "${asset}" || {
        printf 'Windows self-report asset lacks legacy artifact cleanup.\n' >&2
        exit 1
    }
    grep -q 'Remove-LegacyScheduledReporterTask' "${asset}" || {
        printf 'Windows self-report asset lacks robust legacy scheduled task cleanup.\n' >&2
        exit 1
    }
    grep -q '"-NoNotify"' "${asset}" || {
        printf 'Windows self-report scheduled task does not preserve explicit -NoNotify.\n' >&2
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
    grep -q 'OUTBOUND_IP_REPORT_BEGIN' "${asset}" || {
        printf '%s cron marker is not canonical.\n' "${platform}" >&2
        exit 1
    }
    grep -q 'PO0_OUTBOUND_IP_REPORT_CONFIG' "${asset}" || {
        printf '%s asset lacks canonical env aliases.\n' "${platform}" >&2
        exit 1
    }
    if grep -q 'write_legacy_command_shim' "${asset}" || grep -q 'ln -s "${dest}" "${legacy}"' "${asset}"; then
        printf '%s still creates a legacy po0-self-report command shim.\n' "${platform}" >&2
        exit 1
    fi
    grep -q 'cleanup_legacy_self_report_artifacts' "${asset}" || {
        printf '%s lacks legacy artifact cleanup after upgrade/self-heal.\n' "${platform}" >&2
        exit 1
    }
}

check_macos_launchd_canonical_path() {
    local asset="${asset_dir}/po0-outbound-ip-report-macos.sh" label
    label="$(awk '/^launchd_label\(\)/{flag=1} flag{print; if ($0 ~ /^}/) exit}' "${asset}")"
    if [[ "${label}" != *"outbound-ip-report"* || "${label}" == *"fr.schweppes.po0-outbound-ip-report"* || "${label}" == *"fr.schweppes.po0-self-report"* ]]; then
        printf 'macOS launchd label is not canonical.\n' >&2
        exit 1
    fi
}

check_legacy_name_allowlist() {
    local asset line_no line start end context
    local pattern='po0-self-report|PO0_SELF_REPORT|SELF_REPORT_|PO0 Self Report|PO0 Outbound IP Report to LAN Worker|Self-report 已完成|Self-report 未完成|self-report\.json|po0-self-report\.log|fr\.schweppes\.po0-self-report|fr\.schweppes\.po0-outbound-ip-report|PO0_SELF_REPORT_BEGIN|PO0_SELF_REPORT_END|PO0_OUTBOUND_IP_REPORT_BEGIN|PO0_OUTBOUND_IP_REPORT_END'
    local allowed='legacy|compat|fallback|alias|migrat|cleanup|old|previous|PreviousTaskName|PreviousTaskLauncherPath|write_cron_without_managed_block|Test-DownloadedScript|defaultScript\.Value|defaultLauncher\.Value|defaultLog\.Value|旧|兼容|迁移|回退|别名|历史|Get-Legacy|legacy_|LegacyTaskName|旧版|校验失败|grep -q|Self-report 已完成|Self-report 未完成|PO0_SELF_REPORT|SELF_REPORT_'
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

check_no_new_legacy_ssid_aliases() {
    local asset
    for asset in "${asset_dir}/po0-outbound-ip-report.sh" "${asset_dir}/po0-outbound-ip-report-macos.sh" "${asset_dir}/po0-outbound-ip-report.ps1"; do
        if grep -Eq 'PO0_SELF_REPORT_[A-Z0-9_]*SSID|SELF_REPORT_[A-Z0-9_]*SSID' "${asset}"; then
            printf '%s defines a new legacy self-report SSID alias; use PO0_OUTBOUND_IP_REPORT_* only.\n' "${asset##*/}" >&2
            exit 1
        fi
    done
}

check_unix_ssid_guard() {
    local asset="$1" platform="$2" guard_line worker_line worker_http_line
    grep -Eiq 'PO0_OUTBOUND_IP_REPORT_[A-Z0-9_]*SSID' "${asset}" || {
        printf '%s asset lacks canonical SSID environment configuration.\n' "${platform}" >&2
        exit 1
    }
    grep -Eiq -- '--[a-z0-9-]*ssid[a-z0-9-]*' "${asset}" || {
        printf '%s asset lacks SSID CLI configuration.\n' "${platform}" >&2
        exit 1
    }
    grep -Eiq '(^|[^A-Z0-9_])([A-Z0-9_]*SSID[A-Z0-9_]*)=' "${asset}" || {
        printf '%s asset lacks persisted SSID configuration variable.\n' "${platform}" >&2
        exit 1
    }
    grep -Eiq 'ssid.*(skip|skipped|跳过)|(skip|skipped|跳过).*ssid' "${asset}" || {
        printf '%s asset lacks SSID skip result wording.\n' "${platform}" >&2
        exit 1
    }
    grep -Eiq 'ssid.*(summary|log|摘要|日志)|(summary|log|摘要|日志).*ssid' "${asset}" || grep -Eq 'self_report_log_event_summary|show_recent_self_report_log' "${asset}" || {
        printf '%s asset lacks SSID skip log/status summary wording.\n' "${platform}" >&2
        exit 1
    }
    grep -Eiq 'ssid.*(continue|continued|fail|failed|failure|error|unavailable|读取失败|读取.*失败|继续上报)|(continue|continued|fail|failed|failure|error|unavailable|读取失败|继续上报).*ssid' "${asset}" || grep -Eq 'current_wifi_ssid[[:space:]]+2>/dev/null[[:space:]]+\|\|[[:space:]]+true' "${asset}" || {
        printf '%s asset does not state that SSID read failure continues reporting.\n' "${platform}" >&2
        exit 1
    }
    if grep -Eq 'local -a items=|read -r -a items' "${asset}"; then
        printf '%s asset must not parse SSID lists with Bash arrays; macOS Bash 3.2 + set -u treats empty arrays as unbound.\n' "${platform}" >&2
        exit 1
    fi
    guard_line="$(
        awk '
            /^report_once(_inner)?\(\)/ {in_fn=1}
            in_fn && tolower($0) ~ /ssid/ && (tolower($0) ~ /skip|guard|allow|match|local/ || $0 ~ /跳过|匹配|本地/) {print NR; exit}
            in_fn && /^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{/ && $0 !~ /^report_once(_inner)?\(\)/ {in_fn=0}
        ' "${asset}"
    )"
    worker_line="$(
        awk '
            /^report_once(_inner)?\(\)/ {in_fn=1}
            in_fn && /(worker_report_once|report_worker_once)/ {print NR; exit}
            in_fn && /^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{/ && $0 !~ /^report_once(_inner)?\(\)/ {in_fn=0}
        ' "${asset}"
    )"
    [[ -n "${guard_line}" ]] || { printf '%s asset lacks an SSID guard inside report_once.\n' "${platform}" >&2; exit 1; }
    [[ -n "${worker_line}" ]] || { printf '%s asset report worker call was not found.\n' "${platform}" >&2; exit 1; }
    if (( guard_line >= worker_line )); then
        printf '%s asset SSID guard must run before report worker submission.\n' "${platform}" >&2
        exit 1
    fi
    worker_http_line="$(
        awk '
            /^(worker_report_once|report_worker_once)\(\)/ {in_fn=1}
            in_fn && /curl "\$\{curl_args\[@\]\}"/ {print NR; exit}
            in_fn && /^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{/ && $0 !~ /^(worker_report_once|report_worker_once)\(\)/ {in_fn=0}
        ' "${asset}"
    )"
    [[ -n "${worker_http_line}" ]] || {
        printf '%s asset HTTP submit point was not found in the report worker.\n' "${platform}" >&2
        exit 1
    }
}

check_macos_wifi_ssid_diagnostic() {
    local asset="${asset_dir}/po0-outbound-ip-report-macos.sh" fn body
    grep -Fq -- '--show-wifi-ssid' "${asset}" || {
        printf 'macOS asset lacks --show-wifi-ssid diagnostic CLI.\n' >&2
        exit 1
    }
    grep -Fq -- '--diagnose-wifi-ssid' "${asset}" || {
        printf 'macOS asset lacks --diagnose-wifi-ssid permission diagnostic CLI.\n' >&2
        exit 1
    }
    grep -Fq -- '--open-location-services' "${asset}" || {
        printf 'macOS asset lacks --open-location-services settings shortcut CLI.\n' >&2
        exit 1
    }
    grep -Fq -- '--request-location-permission' "${asset}" || {
        printf 'macOS asset lacks --request-location-permission authorization prompt CLI.\n' >&2
        exit 1
    }
    grep -Fq -- '--delete-location-permission-helper' "${asset}" && grep -Fq -- '--remove-location-helper' "${asset}" || {
        printf 'macOS asset lacks Location Permission Helper deletion CLI.\n' >&2
        exit 1
    }
    grep -Fq 'show_current_wifi_ssid_once()' "${asset}" || {
        printf 'macOS asset lacks explicit current Wi-Fi SSID diagnostic function.\n' >&2
        exit 1
    }
    grep -Fq 'show_wifi_ssid_permission_help()' "${asset}" || {
        printf 'macOS asset lacks Wi-Fi SSID permission diagnostic helper.\n' >&2
        exit 1
    }
    grep -Fq 'show_wifi_ssid_permission_help_interactive()' "${asset}" || {
        printf 'macOS asset lacks interactive Wi-Fi SSID permission menu helper.\n' >&2
        exit 1
    }
    grep -Fq 'request_macos_location_permission()' "${asset}" && grep -Fq 'ensure_macos_location_permission_helper_app()' "${asset}" && grep -Fq 'macos_location_helper_wifi_ssid()' "${asset}" || {
        printf 'macOS asset lacks Location Services authorization request helper.\n' >&2
        exit 1
    }
    grep -Fq 'Wi-Fi SSID 权限诊断' "${asset}" && grep -Fq '请选择操作 [0-13]' "${asset}" && grep -Fq '10) show_wifi_ssid_permission_help_interactive; pause_before_return ;;' "${asset}" && grep -Fq '12) remove_macos_location_permission_helper_app_interactive; pause_before_return ;;' "${asset}" || {
        printf 'macOS asset lacks Wi-Fi SSID diagnostic menu/range/case wiring.\n' >&2
        exit 1
    }
    grep -Fq 'remove_macos_location_permission_helper_app()' "${asset}" && grep -Fq 'remove_macos_location_permission_helper_app_interactive()' "${asset}" || {
        printf 'macOS asset lacks Location Permission Helper removal helpers.\n' >&2
        exit 1
    }
    grep -Fq 'accepted_wifi_ssid_value()' "${asset}" || {
        printf 'macOS asset lacks centralized Wi-Fi SSID value filter.\n' >&2
        exit 1
    }
    grep -Fq '<redacted>' "${asset}" && grep -Fq 'redacted' "${asset}" || {
        printf 'macOS asset must reject redacted Wi-Fi SSID placeholders.\n' >&2
        exit 1
    }
    grep -Fq 'WIFI_SSID_LAST_ERROR="privacy"' "${asset}" || {
        printf 'macOS asset must record privacy-hidden Wi-Fi SSID state.\n' >&2
        exit 1
    }
    grep -Fq 'open "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"' "${asset}" || {
        printf 'macOS asset must print an exact Location Services open command.\n' >&2
        exit 1
    }
    grep -Fq 'CoreLocation' "${asset}" && grep -Fq 'requestWhenInUseAuthorization' "${asset}" || {
        printf 'macOS asset must include a CoreLocation permission request path.\n' >&2
        exit 1
    }
    grep -Fq 'CoreWLAN' "${asset}" && grep -Fq 'macos_location_helper_wifi_ssid()' "${asset}" || {
        printf 'macOS asset must let the Location Permission Helper read Wi-Fi SSID in-process.\n' >&2
        exit 1
    }
    if grep -Eq 'networksetup_wifi_ssid\(\)|networksetup_any_wifi_ssid\(\)|networksetup_common_wifi_ssid\(\)|ipconfig_wifi_ssid\(\)|airport_wifi_ssid\(\)|wdutil_wifi_ssid\(\)' "${asset}"; then
        printf 'macOS asset must not keep shell command Wi-Fi SSID fallback functions; use Helper-only probing.\n' >&2
        exit 1
    fi
    if grep -Fq 'on run argv' "${asset}"; then
        printf 'macOS helper AppleScript must not depend on AppleScript applet argv coercion.\n' >&2
        exit 1
    fi
    grep -Fq 'path to resource "po0-location-helper-output.path"' "${asset}" || {
        printf 'macOS helper AppleScript should read output path from bundled resource.\n' >&2
        exit 1
    }
    grep -Fq 'path to resource "po0-location-helper-mode.txt"' "${asset}" || {
        printf 'macOS helper AppleScript should read request mode from bundled resource.\n' >&2
        exit 1
    }
    grep -Fq 'macos_location_helper_request_file()' "${asset}" && grep -Fq 'write_macos_location_helper_request_file()' "${asset}" || {
        printf 'macOS helper IPC must use managed request file helpers.\n' >&2
        exit 1
    }
    if grep -Fq 'open -W -n "${app_dir}" --args' "${asset}"; then
        printf 'macOS helper launcher must not pass output path through open --args.\n' >&2
        exit 1
    fi
    if grep -Eq 'as (boolean|integer|real)' "${asset}"; then
        printf 'macOS helper AppleScript must not coerce AppleScriptObjC values with as boolean/integer/real.\n' >&2
        exit 1
    fi
    if grep -Fq 'write theText to fileRef as' "${asset}"; then
        printf 'macOS helper AppleScript must not write output with AppleEvent utf8 class coercion.\n' >&2
        exit 1
    fi
    if grep -Fq 'writeToFile:outputPath' "${asset}"; then
        printf 'macOS helper AppleScript must not write output through AppleScriptObjC NSError bridging.\n' >&2
        exit 1
    fi
    grep -Fq '/usr/bin/printf %s' "${asset}" || {
        printf 'macOS helper AppleScript should write output through shell printf.\n' >&2
        exit 1
    }
    grep -Fq 'pollWifiSsid(40)' "${asset}" && grep -Fq 'pollWifiSsid(10)' "${asset}" || {
        printf 'macOS helper AppleScript should use separate request/probe wait budgets.\n' >&2
        exit 1
    }
    grep -Fq 'on currentWifiSsid()' "${asset}" && grep -Fq 'set foundSsid to my currentWifiSsid()' "${asset}" && grep -Fq 'exit repeat' "${asset}" || {
        printf 'macOS helper AppleScript should poll CoreWLAN and exit the wait loop as soon as SSID is available.\n' >&2
        exit 1
    }
    grep -Fq 'PO0 Location Permission Helper.app' "${asset}" && grep -Fq 'osacompile' "${asset}" || {
        printf 'macOS asset must build and open a stable Location Permission Helper app.\n' >&2
        exit 1
    }
    grep -Fq 'CFBundleIdentifier' "${asset}" && grep -Fq 'CFBundleExecutable' "${asset}" && grep -Fq 'CFBundlePackageType' "${asset}" && grep -Fq 'PO0HelperSchemaVersion' "${asset}" && grep -Fq 'NSLocationUsageDescription' "${asset}" && grep -Fq 'NSLocationWhenInUseUsageDescription' "${asset}" || {
        printf 'macOS helper app must include stable bundle identity, launch keys, and location usage descriptions.\n' >&2
        exit 1
    }
    grep -Fq 'macos_location_permission_helper_app_is_current()' "${asset}" || {
        printf 'macOS helper app generation must be idempotent for current helper schema.\n' >&2
        exit 1
    }
    grep -Fq 'macos_location_permission_helper_app_has_po0_identity()' "${asset}" && grep -Fq 'validate_macos_location_permission_helper_app_path()' "${asset}" || {
        printf 'macOS helper app deletion must validate path and PO0 helper identity before recursive removal.\n' >&2
        exit 1
    }
    grep -Fq 'create_macos_location_helper_output_file()' "${asset}" && grep -Fq 'cleanup_macos_location_helper_output_file()' "${asset}" || {
        printf 'macOS helper output path must use managed temp file helpers.\n' >&2
        exit 1
    }
    grep -Fq 'codesign --force --deep --sign -' "${asset}" || {
        printf 'macOS helper app should be ad-hoc signed when codesign is available.\n' >&2
        exit 1
    }
    if grep -Fq 'run_macos_location_permission_request_osascript()' "${asset}"; then
        printf 'macOS asset must not keep the old bare osascript Location Services request helper.\n' >&2
        exit 1
    fi
    if grep -Fq '如果看到 redacted' "${asset}"; then
        printf 'macOS asset must not ask users to look for raw redacted after classifying it as privacy-hidden.\n' >&2
        exit 1
    fi
    grep -Eq '定位服务|隐私权限' "${asset}" || {
        printf 'macOS asset lacks Location Services/privacy diagnostic guidance.\n' >&2
        exit 1
    }
    grep -Fq '不会自动获取或修改系统权限' "${asset}" || {
        printf 'macOS asset must state that it does not auto-grant system permissions.\n' >&2
        exit 1
    }
    grep -Fq 'no auto-grant' "${asset}" || {
        printf 'macOS asset must include an ASCII no-auto-grant marker for Windows parser-safe checks.\n' >&2
        exit 1
    }
    body="$(
        awk '
            $0 == "current_wifi_ssid() {" {in_fn=1}
            in_fn {print}
            in_fn && /^}/ {exit}
        ' "${asset}"
    )"
    printf '%s\n' "${body}" | grep -Fq 'capture_wifi_ssid_probe macos_location_helper_wifi_ssid' || {
        printf 'macOS current_wifi_ssid must use the Location Permission Helper as its only probe.\n' >&2
        exit 1
    }
    if printf '%s\n' "${body}" | grep -Eq 'networksetup|ipconfig|airport|wdutil'; then
        printf 'macOS current_wifi_ssid must not call shell command Wi-Fi SSID fallbacks.\n' >&2
        exit 1
    fi
    for fn in accepted_wifi_ssid_value print_wifi_ssid_permission_guidance show_wifi_ssid_permission_help show_wifi_ssid_permission_help_interactive open_macos_location_services_settings; do
        body="$(
            awk -v fn="${fn}" '
                $0 == fn "() {" {in_fn=1}
                in_fn {print}
                in_fn && /^}/ {exit}
            ' "${asset}"
        )"
        [[ -n "${body}" ]] || { printf 'macOS asset lacks %s body.\n' "${fn}" >&2; exit 1; }
        if printf '%s\n' "${body}" | grep -Eq '^[[:space:]]*(sudo|tccutil|sqlite3|osascript)[[:space:]]'; then
            printf 'macOS Wi-Fi SSID diagnostic must not run sudo/tccutil/sqlite3/osascript auto-grant commands in %s.\n' "${fn}" >&2
            exit 1
        fi
    done
    for fn in request_macos_location_permission ensure_macos_location_permission_helper_app macos_location_helper_wifi_ssid remove_macos_location_permission_helper_app remove_macos_location_permission_helper_app_interactive; do
        body="$(
            awk -v fn="${fn}" '
                $0 == fn "() {" {in_fn=1}
                in_fn {print}
                in_fn && /^}/ {exit}
            ' "${asset}"
        )"
        [[ -n "${body}" ]] || { printf 'macOS asset lacks %s body.\n' "${fn}" >&2; exit 1; }
        if printf '%s\n' "${body}" | grep -Eq '^[[:space:]]*(sudo|tccutil|sqlite3)[[:space:]]'; then
            printf 'macOS Wi-Fi SSID permission request must not run sudo/tccutil/sqlite3 commands in %s.\n' "${fn}" >&2
            exit 1
        fi
    done
    body="$(
        awk '
            $0 == "remove_macos_location_permission_helper_app() {" {in_fn=1}
            in_fn {print}
            in_fn && /^}/ {exit}
        ' "${asset}"
    )"
    printf '%s\n' "${body}" | grep -Fq 'validate_macos_location_permission_helper_app_path "${app_dir}"' || {
        printf 'macOS helper removal must validate the computed helper path.\n' >&2
        exit 1
    }
    printf '%s\n' "${body}" | grep -Fq 'macos_location_permission_helper_app_has_po0_identity "${app_dir}"' || {
        printf 'macOS helper removal must verify PO0 helper bundle identity.\n' >&2
        exit 1
    }
    printf '%s\n' "${body}" | grep -Fq 'rm -rf -- "${app_dir}"' || {
        printf 'macOS helper removal must recursively remove only the validated helper app path.\n' >&2
        exit 1
    }
    if printf '%s\n' "${body}" | grep -Eq 'rm -rf[^\r\n]*(root|HOME|PO0_OUTBOUND_IP_REPORT_MACOS_HELPER_DIR|app_dir%|[*])'; then
        printf 'macOS helper removal must not recursively delete helper root, HOME, parent directories, or globs.\n' >&2
        exit 1
    fi
}

check_windows_ssid_guard() {
    local asset
    asset="$(pwsh_literal_path "${asset_dir}/po0-outbound-ip-report.ps1")"
    PO0_WINDOWS_ASSET="${asset}" pwsh -NoProfile -Command '
$raw = Get-Content -LiteralPath $env:PO0_WINDOWS_ASSET -Raw -Encoding UTF8
if ($raw -notmatch "PO0_OUTBOUND_IP_REPORT_[A-Z0-9_]*SSID") { throw "Windows asset lacks canonical SSID environment configuration." }
if ($raw -notmatch ("(?im)^\s*\[[^\r\n]+\]\s*\" + [char]36 + "[A-Za-z0-9_]*Ssid[A-Za-z0-9_]*")) { throw "Windows asset lacks SSID CLI parameter configuration." }
if ($raw -notmatch ("(?i)(\" + [char]36 + "cfg\.[A-Za-z0-9_]*Ssid[A-Za-z0-9_]*|[A-Za-z0-9_]*Ssid[A-Za-z0-9_]*\s*=)")) { throw "Windows asset lacks persisted SSID configuration." }
if ($raw -notmatch "(?is)(ssid.{0,160}(skip|skipped|璺宠繃)|(skip|skipped|璺宠繃).{0,160}ssid)") { throw "Windows asset lacks SSID skip result wording." }
if ($raw -notmatch "(?is)(ssid.{0,160}(summary|log|鎽樿|鏃ュ織)|(summary|log|鎽樿|鏃ュ織).{0,160}ssid)") { throw "Windows asset lacks SSID skip log/status summary wording." }
if ($raw -notmatch "(?is)(ssid.{0,160}(continue|continued|fail|failed|failure|error|unavailable|璇诲彇澶辫触|缁х画涓婃姤)|(continue|continued|fail|failed|failure|error|unavailable|璇诲彇澶辫触|缁х画涓婃姤).{0,160}ssid)") { throw "Windows asset does not state that SSID read failure continues reporting." }
$fn = [regex]::Match($raw, "(?ms)^function Invoke-SelfReportCore\s*\{.*?(?=^function\s+[A-Za-z_][A-Za-z0-9_-]*\s*\{|\z)")
if (-not $fn.Success) { throw "Windows Invoke-SelfReportCore function was not found." }
$guard = [regex]::Match($fn.Value, "(?is)ssid.{0,160}(skip|guard|allow|match|local|璺宠繃|鍖归厤|鏈湴)|(skip|guard|allow|match|local|璺宠繃|鍖归厤|鏈湴).{0,160}ssid")
$http = [regex]::Match($fn.Value, "(Invoke-WorkerSelfReportCore|Invoke-WebRequest)")
if (-not $guard.Success) { throw "Windows asset lacks an SSID guard inside Invoke-SelfReportCore." }
if (-not $http.Success) { throw "Windows asset HTTP submit point was not found." }
if ($guard.Index -ge $http.Index) { throw "Windows asset SSID guard must run before HTTP report submission." }
'
}

check_outbound_ip_report_ssid_guards() {
    check_unix_ssid_guard "${asset_dir}/po0-outbound-ip-report.sh" "Linux/OpenWrt"
    check_unix_ssid_guard "${asset_dir}/po0-outbound-ip-report-macos.sh" "macOS"
    check_macos_wifi_ssid_diagnostic
    if command -v pwsh >/dev/null 2>&1; then
        check_windows_ssid_guard
    else
        printf 'pwsh not found; skipping Windows SSID guard check.\n' >&2
    fi
    check_no_new_legacy_ssid_aliases
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
    local expected="${expected_po0_version}" asset version date
    for asset in nftables-relay-manager.sh po0-lan-client.sh po0-wan-probe.sh po0-outbound-ip-report.sh po0-outbound-ip-report-macos.sh po0-outbound-ip-report.ps1; do
        version="$(asset_version "${asset_dir}/${asset}")"
        [[ -n "${version}" ]] || { printf 'Could not read version from %s\n' "${asset}" >&2; exit 1; }
        if [[ "${version}" != "${expected}" ]]; then
            printf '%s version %s does not match %s\n' "${asset}" "${version}" "${expected}" >&2
            exit 1
        fi
        date="$(asset_release_date "${asset_dir}/${asset}")"
        [[ "${date}" == "${expected_po0_release_date}" ]] || { printf '%s release date %s is unexpected\n' "${asset}" "${date}" >&2; exit 1; }
        asset_has_changelog "${asset_dir}/${asset}" || { printf '%s changelog block is empty\n' "${asset}" >&2; exit 1; }
    done
}

check_versions_match_tag() {
    local tag="${GITHUB_REF_NAME:-}" ref_type="${GITHUB_REF_TYPE:-}" ref="${GITHUB_REF:-}" expected asset version
    [[ -n "${tag}" ]] || return 0
    if [[ "${ref_type}" == "branch" || "${ref}" == refs/heads/* ]]; then
        return 0
    fi
    [[ "${tag}" == "${expected_po0_release_tag}" ]] || {
        printf 'GITHUB_REF_NAME %s does not match expected PO0 release tag %s\n' "${tag}" "${expected_po0_release_tag}" >&2
        exit 1
    }
    if [[ ! "${tag}" =~ ^po0-v([0-9]{4}\.[0-9]{2}\.[0-9]{2})\.([0-9]+)$ ]]; then
        printf 'GITHUB_REF_NAME is set but is not a PO0 release tag: %s\n' "${tag}" >&2
        exit 1
    fi
    expected="${BASH_REMATCH[1]}+build.${BASH_REMATCH[2]}"
    for asset in nftables-relay-manager.sh po0-lan-client.sh po0-wan-probe.sh po0-outbound-ip-report.sh po0-outbound-ip-report-macos.sh; do
        version="$(grep -m1 '^SCRIPT_VERSION=' "${asset_dir}/${asset}" | sed -E 's/^SCRIPT_VERSION="([^"]+)".*/\1/')"
        [[ "${version}" == "${expected}" ]] || { printf '%s version %s does not match tag %s\n' "${asset}" "${version}" "${expected}" >&2; exit 1; }
    done
    version="$(grep -m1 '^\$ScriptVersion = ' "${asset_dir}/po0-outbound-ip-report.ps1" | sed -E 's/^\$ScriptVersion = "([^"]+)".*/\1/')"
    [[ "${version}" == "${expected}" ]] || { printf 'po0-outbound-ip-report.ps1 version %s does not match tag %s\n' "${version}" "${expected}" >&2; exit 1; }
}

check_asset_inventory() {
    local expected actual checksum_names
    expected="$(printf '%s\n' checksums.txt nftables-relay-manager.sh po0-lan-client.sh po0-wan-probe.sh po0-outbound-ip-report-macos.sh po0-outbound-ip-report.ps1 po0-outbound-ip-report.sh | sort)"
    actual="$(find "${asset_dir}" -maxdepth 1 -type f -printf '%f\n' | sort)"
    if [[ "${actual}" != "${expected}" ]]; then
        printf 'Unexpected PO0 asset inventory.\nExpected:\n%s\nActual:\n%s\n' "${expected}" "${actual}" >&2
        exit 1
    fi
    checksum_names="$(awk '{print $2}' "${asset_dir}/checksums.txt" | sort)"
    if [[ "${checksum_names}" != "$(printf '%s\n' nftables-relay-manager.sh po0-lan-client.sh po0-wan-probe.sh po0-outbound-ip-report-macos.sh po0-outbound-ip-report.ps1 po0-outbound-ip-report.sh | sort)" ]]; then
        printf 'checksums.txt does not cover the exact asset set.\n' >&2
        exit 1
    fi
    (cd "${asset_dir}" && sha256sum -c checksums.txt >/dev/null)
}

check_manifest_coverage "manager" "tools/po0/manifests/manager.txt" "scripts/po0/relay/manager/src"
check_manifest_coverage "lan-worker" "tools/po0/manifests/lan-worker.txt" "scripts/po0/relay/lan-worker/src"
check_manifest_coverage "wan-probe-openwrt" "tools/po0/manifests/wan-probe-openwrt.txt" "scripts/po0/relay/wan-probe/openwrt/src"
check_manifest_coverage "self-report-linux" "tools/po0/manifests/self-report-linux.txt" "scripts/po0/relay/self-report/linux/src"
check_manifest_coverage "self-report-macos" "tools/po0/manifests/self-report-macos.txt" "scripts/po0/relay/self-report/macos/src"
check_manifest_coverage "self-report-windows" "tools/po0/manifests/self-report-windows.txt" "scripts/po0/relay/self-report/windows/src" "*.ps1"

bash "${repo_root}/tools/po0/test-macos-ssid-diagnostic.sh"
bash "${repo_root}/tools/po0/test-macos-official-report.sh"
bash "${repo_root}/tools/po0/test-self-report-refresh-policy.sh"
bash "${repo_root}/tools/po0/test-linux-multi-wan-report.sh"
bash "${repo_root}/tools/po0/test-linux-official-http.sh"
bash "${repo_root}/tools/po0/test-linux-official-report.sh"
check_lan_worker_official_channel
bash "${repo_root}/tools/po0/test-lan-worker-official-report.sh"
if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -ExecutionPolicy Bypass -File "${repo_root}/tools/po0/test-windows-official-report.ps1"
elif command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${repo_root}/tools/po0/test-windows-official-report.ps1"
else
    printf 'PowerShell not found; skipping Windows official report mock test.\n' >&2
fi
bash -n "${repo_root}/tools/po0/test-linux-official-cli.sh"
bash "${repo_root}/tools/po0/test-linux-official-cli.sh"
bash "${repo_root}/tools/po0/test-wan-probe.sh"
bash "${repo_root}/tools/po0/test-official-firewall-core.sh"
bash "${repo_root}/tools/po0/test-openwrt-official-adapter.sh"
bash "${repo_root}/tools/po0/test-openwrt-service.sh"
bash "${repo_root}/tools/po0/test-openwrt-luci-official-ui.sh"
bash "${repo_root}/tools/po0/test-openwrt-apk-layout.sh"
bash "${repo_root}/tools/po0/test-lan-worker-stash-report.sh"
bash "${repo_root}/tools/po0/test-manager-client-ip-cidr-prefix.sh"
bash "${repo_root}/tools/po0/test-manager-nft-atomic-reload.sh"
bash "${repo_root}/tools/po0/test-manager-resource-upload.sh"
bash "${repo_root}/tools/po0/test-debian-reinstall-grub.sh"
node "${repo_root}/tools/po0/test-egern-ssid-guard.mjs"
node "${repo_root}/tools/po0/test-egern-official-report.mjs"
node "${repo_root}/tools/po0/test-loon-report.js"
node "${repo_root}/tools/po0/test-stash-report.js"
bash "${repo_root}/tools/po0/build-po0-assets.sh" "${asset_dir}"

for asset in nftables-relay-manager.sh po0-lan-client.sh po0-wan-probe.sh po0-outbound-ip-report.sh po0-outbound-ip-report-macos.sh; do
    printf 'Checking bash -n %s\n' "${asset}"
    bash -n "${asset_dir}/${asset}"
done

if command -v pwsh >/dev/null 2>&1; then
    PO0_WINDOWS_ASSET="$(pwsh_literal_path "${asset_dir}/po0-outbound-ip-report.ps1")" pwsh -NoProfile -Command '$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile($env:PO0_WINDOWS_ASSET,[ref]$tokens,[ref]$errors) | Out-Null; if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Error $_.Message }; exit 1 }'
else
    printf 'pwsh not found; skipping PowerShell parser check.\n' >&2
fi

bash "${asset_dir}/nftables-relay-manager.sh" --version >/dev/null
bash "${asset_dir}/nftables-relay-manager.sh" --changelog >/dev/null
bash "${asset_dir}/po0-lan-client.sh" --version >/dev/null
REQUEST_METHOD=POST REMOTE_ADDR=192.168.88.2 bash "${asset_dir}/po0-wan-probe.sh" >/dev/null
bash "${asset_dir}/po0-outbound-ip-report.sh" --version >/dev/null
bash "${asset_dir}/po0-outbound-ip-report.sh" --changelog >/dev/null
bash "${asset_dir}/po0-outbound-ip-report-macos.sh" --version >/dev/null
bash "${asset_dir}/po0-outbound-ip-report-macos.sh" --changelog >/dev/null

check_versions_match_tag
check_versions_consistent
check_raw_refs
check_egern_compat_sync
check_egern_ssid_guard
check_egern_official_channel
check_lan_worker_official_channel
check_asset_inventory
check_unix_outbound_ip_report_canonical_path "${asset_dir}/po0-outbound-ip-report.sh" "Linux/OpenWrt"
check_unix_outbound_ip_report_canonical_path "${asset_dir}/po0-outbound-ip-report-macos.sh" "macOS"
check_macos_launchd_canonical_path
check_windows_canonical_path
check_legacy_name_allowlist
check_outbound_ip_report_ssid_guards

printf 'PO0 asset checks passed.\n'
