#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src_dir="${repo_root}/scripts/po0/relay/manager/src"
tmp_root="$(mkdir -p "${repo_root}/.tmp" && cd "${repo_root}/.tmp" && pwd -P)"
tmp_dir="$(mktemp -d "${tmp_root}/po0-manager-client-ip-cidr-prefix.XXXXXX")"
tmp_dir="$(cd "${tmp_dir}" && pwd -P)"
trap 'rm -rf "${tmp_dir}"' EXIT

# Load the production CIDR and client-report functions, then replace only their
# filesystem/token side effects so this test can run without root or nftables.
source "${src_dir}/000-header-globals.sh"
source "${src_dir}/010-core-ui-logging.sh"
source "${src_dir}/040-core-input-port-ip-validators.sh"
source "${src_dir}/050-ip-network-discovery-allowlist-modes.sh"
source "${src_dir}/060-allowlist-set-entry-model.sh"
source "${src_dir}/070-allowlist-source-token-dynamic.sh"
source "${src_dir}/080-report-stats-ingest.sh"

validate_client_ip_report_token() { [[ "${1:-}" == "test-token" ]]; }
normalize_client_ttl_seconds() { printf '%s\n' "${1:-43200}"; }
utc_after_seconds_iso() { printf '2030-01-01T00:00:00Z\n'; }
ipdb_snapshot_for_ip() { :; }
update_generic_report_stats() { :; }

captured_cidr=""
captured_note=""
replace_calls=0
replace_allowlist_entries_for_source_with_expiry() {
    captured_note="${4:-}"
    captured_cidr="${6:-}"
    replace_calls=$((replace_calls + 1))
}

report_client_ip_source_unlocked "stash-cellular" "8.8.8.129" "test-token" "iphone" "43200" "24"
[[ "${captured_cidr}" == "8.8.8.0/24" ]] || {
    printf 'expected /24 normalization, got %s\n' "${captured_cidr}" >&2
    exit 1
}
[[ "${CLIENT_IP_REPORT_CIDR:-}" == "8.8.8.0/24" && "${CLIENT_IP_REPORT_CIDR_PREFIX:-}" == "24" ]] || {
    printf 'client report CIDR state was not recorded\n' >&2
    exit 1
}
[[ "${captured_note}" == *"prefix=24"* ]] || {
    printf 'client report note did not record prefix=24\n' >&2
    exit 1
}

report_client_ip_source_unlocked "stash-wifi" "8.8.8.129" "test-token" "iphone" "43200"
[[ "${captured_cidr}" == "8.8.8.129/32" && "${CLIENT_IP_REPORT_CIDR_PREFIX:-}" == "32" ]] || {
    printf 'expected omitted prefix to remain /32, got %s\n' "${captured_cidr}" >&2
    exit 1
}

calls_before_invalid="${replace_calls}"
if report_client_ip_source_unlocked "stash-invalid" "8.8.8.129" "test-token" "iphone" "43200" "25" >/dev/null 2>&1; then
    printf 'invalid client report CIDR prefix was accepted\n' >&2
    exit 1
fi
[[ "${replace_calls}" == "${calls_before_invalid}" ]] || {
    printf 'invalid client report reached allowlist persistence\n' >&2
    exit 1
}

# Generate the actual forced-command wrapper and exercise its optional sixth
# argument validation before the manager command is invoked.
source "${src_dir}/270-report-endpoints-and-keys.sh"

forwarded_prefix=""
ensure_layout() { :; }
load_settings() { :; }
report_client_ip_source() {
    forwarded_prefix="${6:-}"
    CLIENT_IP_REPORT_SOURCE="${1:-}"
    CLIENT_IP_REPORT_IP="${2:-}"
    CLIENT_IP_REPORT_CIDR="8.8.8.0/${forwarded_prefix:-32}"
    CLIENT_IP_REPORT_TTL="${5:-43200}"
}
enable_allowlist_for_custom_add() { :; }
apply_src_allowlist_changes() { :; }
DYNAMIC_REPORT_PENDING_COUNT=0

do_report_client_ip_source "stash-cellular" "8.8.8.129" "test-token" "iphone" "43200" "24" > "${tmp_dir}/endpoint-output.txt"
[[ "${forwarded_prefix}" == "24" ]] || {
    printf 'client-ip endpoint did not forward prefix 24\n' >&2
    exit 1
}
grep -Fq 'CIDR 8.8.8.0/24' "${tmp_dir}/endpoint-output.txt" || {
    printf 'client-ip endpoint output did not show the accepted CIDR\n' >&2
    exit 1
}

REPORT_KEY_WRAPPER_PATH="${tmp_dir}/po0-report-key-wrapper"
MANAGER_INSTALL_PATH="${tmp_dir}/fake-manager.sh"
capture_file="${tmp_dir}/wrapper-args.txt"

cat > "${MANAGER_INSTALL_PATH}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${WRAPPER_CAPTURE:?}"
EOF
chmod +x "${MANAGER_INSTALL_PATH}"
ensure_report_key_wrapper

WRAPPER_CAPTURE="${capture_file}" \
SSH_ORIGINAL_COMMAND="bash ${MANAGER_INSTALL_PATH} --client-ip-report stash-cellular 8.8.8.129 test-token iphone 43200 24" \
    "${REPORT_KEY_WRAPPER_PATH}" worker "${MANAGER_INSTALL_PATH}"
grep -Fxq '24' "${capture_file}" || {
    printf 'forced-command wrapper did not forward prefix 24\n' >&2
    exit 1
}

if WRAPPER_CAPTURE="${capture_file}" \
    SSH_ORIGINAL_COMMAND="bash ${MANAGER_INSTALL_PATH} --client-ip-report stash-invalid 8.8.8.129 test-token iphone 43200 25" \
    "${REPORT_KEY_WRAPPER_PATH}" worker "${MANAGER_INSTALL_PATH}" >/dev/null 2>&1; then
    printf 'forced-command wrapper accepted invalid prefix 25\n' >&2
    exit 1
fi

printf 'manager client-ip CIDR prefix tests passed\n'
