#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src_dir="${repo_root}/scripts/po0/relay/manager/src"
tmp_root="$(mkdir -p "${repo_root}/.tmp" && cd "${repo_root}/.tmp" && pwd -P)"
tmp_dir="$(mktemp -d "${tmp_root}/po0-manager-nft-atomic-reload.XXXXXX")"
tmp_dir="$(cd "${tmp_dir}" && pwd -P)"
trap 'rm -rf "${tmp_dir}"' EXIT

export PO0_CONF_DIR="${tmp_dir}"
source "${src_dir}/000-header-globals.sh"
source "${src_dir}/010-core-ui-logging.sh"
source "${src_dir}/020-core-temp-locks.sh"
source "${src_dir}/250-relay-nft-apply-actions.sh"

cleanup() {
    cleanup_temp_files
    rm -rf "${tmp_dir}"
}
trap cleanup EXIT

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

NFT_CONF="${tmp_dir}/po0-relay.conf"
call_log="${tmp_dir}/nft-calls.log"
checked_transaction="${tmp_dir}/checked-transaction.nft"
applied_transaction="${tmp_dir}/applied-transaction.nft"

cat > "${NFT_CONF}" <<EOF
#!/usr/sbin/nft -f
# atomic reload fixture
table ip ${NAT_TABLE} {
    chain prerouting { type nat hook prerouting priority dstnat; policy accept; }
}
table ip ${MANGLE_TABLE} {
    chain forward { type filter hook forward priority mangle; policy accept; }
}
EOF

NAT_EXISTS=1
MANGLE_EXISTS=1
CHECK_RC=0
APPLY_RC=0
CHECK_CALLS=0
APPLY_CALLS=0

nft() {
    printf '%s\n' "$*" >> "${call_log}"
    if [[ "${1:-}" == "list" && "${2:-}" == "table" && "${3:-}" == "ip" ]]; then
        case "${4:-}" in
            "${NAT_TABLE}") [[ "${NAT_EXISTS}" == "1" ]] ;;
            "${MANGLE_TABLE}") [[ "${MANGLE_EXISTS}" == "1" ]] ;;
            *) return 1 ;;
        esac
        return $?
    fi
    if [[ "${1:-}" == "-c" && "${2:-}" == "-f" ]]; then
        CHECK_CALLS=$((CHECK_CALLS + 1))
        cp "${3}" "${checked_transaction}"
        return "${CHECK_RC}"
    fi
    if [[ "${1:-}" == "-f" ]]; then
        APPLY_CALLS=$((APPLY_CALLS + 1))
        cp "${2}" "${applied_transaction}"
        return "${APPLY_RC}"
    fi
    return 1
}

reset_case() {
    : > "${call_log}"
    rm -f -- "${checked_transaction}" "${applied_transaction}"
    CHECK_CALLS=0
    APPLY_CALLS=0
    CHECK_RC=0
    APPLY_RC=0
    NAT_EXISTS=1
    MANGLE_EXISTS=1
}

assert_no_reload_temp() {
    if find "${tmp_dir}" -maxdepth 1 -type f -name 'po0-relay.conf.reload.tmp.*' -print -quit | grep -q .; then
        find "${tmp_dir}" -maxdepth 1 -type f -name 'po0-relay.conf.reload.tmp.*' -print >&2
        fail "atomic reload left a transaction staging file"
    fi
}

reset_case
reload_managed_rules
[[ "${CHECK_CALLS}" == "1" && "${APPLY_CALLS}" == "1" ]] || fail "managed reload did not check once and apply once"
grep -Fxq "delete table ip ${NAT_TABLE}" "${applied_transaction}" || fail "transaction did not delete the existing NAT table"
grep -Fxq "delete table ip ${MANGLE_TABLE}" "${applied_transaction}" || fail "transaction did not delete the existing MANGLE table"
grep -Fq "table ip ${NAT_TABLE}" "${applied_transaction}" || fail "transaction did not include the new NAT table"
grep -Fq "table ip ${MANGLE_TABLE}" "${applied_transaction}" || fail "transaction did not include the new MANGLE table"
cmp -s "${checked_transaction}" "${applied_transaction}" || fail "checked and applied transactions differ"
[[ "$(wc -l < "${call_log}" | tr -d '[:space:]')" == "4" ]] || fail "managed reload issued unexpected nft commands"
if grep -Eq '^delete table ' "${call_log}"; then
    fail "managed reload issued a standalone table deletion"
fi
assert_no_reload_temp

reset_case
MANGLE_EXISTS=0
reload_managed_rules
grep -Fxq "delete table ip ${NAT_TABLE}" "${applied_transaction}" || fail "NAT deletion was omitted when MANGLE was absent"
if grep -Fxq "delete table ip ${MANGLE_TABLE}" "${applied_transaction}"; then
    fail "transaction tried to delete an absent MANGLE table"
fi
[[ "${CHECK_CALLS}" == "1" && "${APPLY_CALLS}" == "1" ]] || fail "optional-table reload did not stay single-apply"
assert_no_reload_temp

reset_case
CHECK_RC=1
if reload_managed_rules > "${tmp_dir}/precheck-failure.out" 2>&1; then
    fail "reload succeeded after transaction precheck failure"
fi
[[ "${CHECK_CALLS}" == "1" && "${APPLY_CALLS}" == "0" ]] || fail "precheck failure reached live apply"
grep -Fq "原子刷新事务预检失败" "${tmp_dir}/precheck-failure.out" || fail "precheck failure message is missing"
assert_no_reload_temp

reset_case
APPLY_RC=1
if reload_managed_rules > "${tmp_dir}/apply-failure.out" 2>&1; then
    fail "reload succeeded after atomic apply failure"
fi
[[ "${CHECK_CALLS}" == "1" && "${APPLY_CALLS}" == "1" ]] || fail "apply failure used an unexpected number of transactions"
grep -Fq "旧托管规则保持不变" "${tmp_dir}/apply-failure.out" || fail "atomic apply failure message does not describe rollback semantics"
assert_no_reload_temp

if grep -Eq '^[[:space:]]*nft delete table' "${src_dir}/250-relay-nft-apply-actions.sh"; then
    fail "production reload still contains a standalone nft table deletion"
fi

printf 'manager nftables atomic reload tests passed\n'
