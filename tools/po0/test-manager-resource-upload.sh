#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src_dir="${repo_root}/scripts/po0/relay/manager/src"
tmp_root="$(mkdir -p "${repo_root}/.tmp" && cd "${repo_root}/.tmp" && pwd -P)"
tmp_dir="$(mktemp -d "${tmp_root}/po0-manager-resource-upload.XXXXXX")"
tmp_dir="$(cd "${tmp_dir}" && pwd -P)"
mkdir -p "${tmp_dir}/conf/backups"
trap 'rm -rf "${tmp_dir}"' EXIT

export PO0_CONF_DIR="${tmp_dir}/conf"
unset PO0_RESOURCE_IPLIST_MAX_BYTES PO0_RESOURCE_IPDB_MAX_BYTES
unset RESOURCE_IPLIST_MAX_BYTES RESOURCE_IPDB_MAX_BYTES

source "${src_dir}/000-header-globals.sh"
source "${src_dir}/010-core-ui-logging.sh"
source "${src_dir}/020-core-temp-locks.sh"
source "${src_dir}/150-resource-task-state.sh"
source "${src_dir}/180-resource-artifact-ingest.sh"
source "${src_dir}/190-resource-task-completion.sh"

cleanup() {
    cleanup_temp_files
    rm -rf "${tmp_dir}"
}
trap cleanup EXIT

# Keep the completion fixture isolated from the optional Python/ipdb runtime.
ipdb_python_cmd() { return 1; }
tsv_safe() { printf '%s' "${1:-}" | tr '|\r\n' '   '; }

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

sha256_file_for_test() {
    sha256sum "$1" | awk '{print $1}'
}

artifact_path_for_test() {
    local task_id="$1" type="$2"
    printf '%s/%s.%s\n' "${RESOURCE_INBOX_DIR}" "${task_id}" "$(resource_task_artifact_name "${type}")"
}

add_running_task() {
    local task_id="$1" type="$2" worker="$3" status="${4:-running}"
    local claimed="2026-07-22T00:00:01Z"
    [[ "${status}" == "running" ]] || claimed=""
    printf '%s|%s|%s|2026-07-22T00:00:00Z|%s||%s||||waiting\n' \
        "${task_id}" "${type}" "${status}" "${claimed}" "${worker}" >> "${RESOURCE_TASKS_FILE}"
}

assert_no_task_artifact() {
    local task_id="$1"
    if find "${RESOURCE_INBOX_DIR}" -maxdepth 1 -type f -name "${task_id}.*" -print -quit | grep -q .; then
        find "${RESOURCE_INBOX_DIR}" -maxdepth 1 -type f -name "${task_id}.*" -print >&2
        fail "failed upload left an artifact or staging file for ${task_id}"
    fi
}

assert_rejected_without_stdin_read() {
    local label="$1" task_id="$2" worker="$3" sha="$4" size="$5" token="$6"
    local input="${tmp_dir}/${label}.stdin" output="${tmp_dir}/${label}.out" first=""
    printf 'sentinel' > "${input}"
    exec 7< "${input}"
    if upload_resource_task_artifact "${task_id}" "${worker}" "${sha}" "${size}" "${token}" <&7 > "${output}" 2>&1; then
        exec 7<&-
        fail "${label} upload was unexpectedly accepted"
    fi
    IFS= read -r -n 1 first <&7 || true
    exec 7<&-
    [[ "${first}" == "s" ]] || fail "${label} rejection consumed stdin"
    assert_no_task_artifact "${task_id}"
}

ensure_resource_task_layout
printf 'resource-token\n' > "${RESOURCE_TASK_TOKEN_FILE}"

# Closing the lock fd must not permanently redirect the caller's stderr. This
# specifically guards the no-flock path used by Git Bash on Windows.
stderr_probe="$({
    resource_task_lock
    resource_task_unlock
    printf 'stderr-alive\n' >&2
} 2>&1 >/dev/null)"
[[ "${stderr_probe}" == "stderr-alive" ]] || fail "resource_task_unlock swallowed caller stderr"

[[ "${RESOURCE_IPLIST_MAX_BYTES}" == "8388608" ]] || \
    fail "unexpected default iplist upload limit: ${RESOURCE_IPLIST_MAX_BYTES}"
[[ "${RESOURCE_IPDB_MAX_BYTES}" == "134217728" ]] || \
    fail "unexpected default ipdb upload limit: ${RESOURCE_IPDB_MAX_BYTES}"

default_iplist_max="${RESOURCE_IPLIST_MAX_BYTES}"
default_ipdb_max="${RESOURCE_IPDB_MAX_BYTES}"
RESOURCE_IPLIST_MAX_BYTES=64
RESOURCE_IPDB_MAX_BYTES=128
[[ "$(resource_task_upload_max_bytes iplist)" == "64" ]] || \
    fail "legacy iplist upload-limit override was not honored"
[[ "$(resource_task_upload_max_bytes ipdb)" == "128" ]] || \
    fail "legacy ipdb upload-limit override was not honored"

# Both task types accept ordinary declarations and exact SHA-256/length bodies.
iplist_task="iplist-exact"
iplist_payload="${tmp_dir}/iplist.payload"
printf 'small-iplist-archive-fixture' > "${iplist_payload}"
iplist_sha="$(sha256_file_for_test "${iplist_payload}")"
iplist_size="$(wc -c < "${iplist_payload}" | tr -d '[:space:]')"
add_running_task "${iplist_task}" iplist worker-a
upload_resource_task_artifact "${iplist_task}" worker-a "${iplist_sha}" "${iplist_size}" resource-token \
    < "${iplist_payload}" > "${tmp_dir}/iplist-exact.out"
grep -Fq 'OK|' "${tmp_dir}/iplist-exact.out" || fail "exact iplist upload did not return OK"
cmp -s "${iplist_payload}" "$(artifact_path_for_test "${iplist_task}" iplist)" || \
    fail "exact iplist upload was not saved byte-for-byte"
if ! upload_resource_task_artifact "${iplist_task}" worker-a "${iplist_sha}" "${iplist_size}" resource-token \
    < "${iplist_payload}" > "${tmp_dir}/iplist-duplicate.out"; then
    fail "identical duplicate upload failed"
fi
grep -Fq 'OK|' "${tmp_dir}/iplist-duplicate.out" || fail "identical duplicate upload was not idempotent"
cmp -s "${iplist_payload}" "$(artifact_path_for_test "${iplist_task}" iplist)" || \
    fail "identical duplicate upload changed the saved artifact"

ipdb_task="ipdb-complete"
ipdb_payload="${tmp_dir}/valid.ipdb"
metadata='{"fields":[],"languages":{"CN":0},"node_count":1}'
metadata_size="${#metadata}"
(( metadata_size >= 32 && metadata_size < 256 )) || fail "invalid IPDB metadata fixture length"
{
    printf '\000\000\000'
    printf "\\$(printf '%03o' "${metadata_size}")"
    printf '%sX' "${metadata}"
} > "${ipdb_payload}"
ipdb_sha="$(sha256_file_for_test "${ipdb_payload}")"
ipdb_size="$(wc -c < "${ipdb_payload}" | tr -d '[:space:]')"
padded_ipdb_size="000${ipdb_size}"
uppercase_ipdb_sha="${ipdb_sha^^}"
add_running_task "${ipdb_task}" ipdb worker-a
upload_resource_task_artifact "${ipdb_task}" worker-a "${uppercase_ipdb_sha}" "${padded_ipdb_size}" resource-token \
    < "${ipdb_payload}" > "${tmp_dir}/ipdb-exact.out"
grep -Fq 'OK|' "${tmp_dir}/ipdb-exact.out" || fail "exact ipdb upload did not return OK"
finish_resource_task "${ipdb_task}" worker-a "${uppercase_ipdb_sha}" "${padded_ipdb_size}" resource-token \
    > "${tmp_dir}/ipdb-complete.out"
grep -Fq 'OK|' "${tmp_dir}/ipdb-complete.out" || fail "valid ipdb completion did not return OK"
cmp -s "${ipdb_payload}" "${IPDB_FILE}" || fail "valid ipdb was not installed byte-for-byte"
grep -Fq "${ipdb_task}|ipdb|success|" "${RESOURCE_TASKS_FILE}" || \
    fail "completed ipdb task did not advance to success"
[[ ! -e "$(artifact_path_for_test "${ipdb_task}" ipdb)" ]] || \
    fail "completed ipdb inbox artifact was not removed"

RESOURCE_IPLIST_MAX_BYTES="${default_iplist_max}"
RESOURCE_IPDB_MAX_BYTES="${default_ipdb_max}"

po0_override_values="$(
    PO0_RESOURCE_IPLIST_MAX_BYTES=96 \
    PO0_RESOURCE_IPDB_MAX_BYTES=192 \
    RESOURCE_IPLIST_MAX_BYTES=64 \
    RESOURCE_IPDB_MAX_BYTES=128 \
    bash -c '
        source "$1/000-header-globals.sh"
        source "$1/150-resource-task-state.sh"
        printf "%s|%s\n" "$(resource_task_upload_max_bytes iplist)" "$(resource_task_upload_max_bytes ipdb)"
    ' _ "${src_dir}"
)"
[[ "${po0_override_values}" == "96|192" ]] || \
    fail "documented PO0_* upload-limit overrides did not take precedence: ${po0_override_values}"
if PO0_RESOURCE_IPLIST_MAX_BYTES=0 bash -c '
    source "$1/000-header-globals.sh"
    source "$1/150-resource-task-state.sh"
    resource_task_upload_max_bytes iplist
' _ "${src_dir}" >/dev/null 2>&1; then
    fail "zero PO0_RESOURCE_IPLIST_MAX_BYTES was accepted"
fi
if PO0_RESOURCE_IPDB_MAX_BYTES=invalid bash -c '
    source "$1/000-header-globals.sh"
    source "$1/150-resource-task-state.sh"
    resource_task_upload_max_bytes ipdb
' _ "${src_dir}" >/dev/null 2>&1; then
    fail "invalid PO0_RESOURCE_IPDB_MAX_BYTES was accepted"
fi

# Invalid declarations must be rejected before the controlled stdin is read.
zero_sha="$(printf '0%.0s' {1..64})"
add_running_task iplist-too-large iplist worker-a
assert_rejected_without_stdin_read iplist-too-large iplist-too-large worker-a "${zero_sha}" \
    "$((RESOURCE_IPLIST_MAX_BYTES + 1))" resource-token

add_running_task ipdb-too-large ipdb worker-a
assert_rejected_without_stdin_read ipdb-too-large ipdb-too-large worker-a "${zero_sha}" \
    "$((RESOURCE_IPDB_MAX_BYTES + 1))" resource-token

add_running_task wrong-token iplist worker-a
assert_rejected_without_stdin_read wrong-token wrong-token worker-a "${zero_sha}" 8 bad-token

add_running_task wrong-worker iplist worker-a
assert_rejected_without_stdin_read wrong-worker wrong-worker worker-b "${zero_sha}" 8 resource-token

add_running_task wrong-state iplist worker-a pending
assert_rejected_without_stdin_read wrong-state wrong-state worker-a "${zero_sha}" 8 resource-token

# Invalid local/legacy limit settings fail closed before reading stdin. The
# documented PO0_* aliases are checked below in a clean subprocess because the
# production globals resolve their precedence when the manager starts.
RESOURCE_IPLIST_MAX_BYTES=0
RESOURCE_IPDB_MAX_BYTES=invalid
add_running_task invalid-iplist-limit iplist worker-a
assert_rejected_without_stdin_read invalid-iplist-limit invalid-iplist-limit worker-a "${zero_sha}" 1 resource-token
add_running_task invalid-ipdb-limit ipdb worker-a
assert_rejected_without_stdin_read invalid-ipdb-limit invalid-ipdb-limit worker-a "${zero_sha}" 1 resource-token
RESOURCE_IPLIST_MAX_BYTES="${default_iplist_max}"
RESOURCE_IPDB_MAX_BYTES="${default_ipdb_max}"

# A short body and an extra trailing byte both fail closed and leave no file.
short_task="short-body"
short_payload="${tmp_dir}/short.payload"
printf 'short' > "${short_payload}"
short_sha="$(sha256_file_for_test "${short_payload}")"
add_running_task "${short_task}" iplist worker-a
if upload_resource_task_artifact "${short_task}" worker-a "${short_sha}" 6 resource-token \
    < "${short_payload}" > "${tmp_dir}/short.out" 2>&1; then
    fail "short upload body was accepted"
fi
assert_no_task_artifact "${short_task}"

tail_task="trailing-byte"
tail_prefix="${tmp_dir}/tail-prefix.payload"
tail_payload="${tmp_dir}/tail.payload"
printf 'declared-body' > "${tail_prefix}"
printf 'declared-bodyX' > "${tail_payload}"
tail_sha="$(sha256_file_for_test "${tail_prefix}")"
tail_size="$(wc -c < "${tail_prefix}" | tr -d '[:space:]')"
add_running_task "${tail_task}" iplist worker-a
if upload_resource_task_artifact "${tail_task}" worker-a "${tail_sha}" "${tail_size}" resource-token \
    < "${tail_payload}" > "${tmp_dir}/tail.out" 2>&1; then
    fail "upload with a trailing byte was accepted"
fi
assert_no_task_artifact "${tail_task}"

# While the body is stalled, another queue operation must still acquire the
# global task lock. Git Bash does not always ship flock, so Windows runs skip
# only this concurrency assertion; Linux CI exercises it.
if command -v flock >/dev/null 2>&1; then
    lock_task="slow-body"
    lock_payload='slow-upload-body'
    lock_input="${tmp_dir}/slow-upload.fifo"
    lock_output="${tmp_dir}/slow-upload.out"
    lock_payload_file="${tmp_dir}/slow-upload.payload"
    printf '%s' "${lock_payload}" > "${lock_payload_file}"
    lock_sha="$(sha256_file_for_test "${lock_payload_file}")"
    lock_size="$(wc -c < "${lock_payload_file}" | tr -d '[:space:]')"
    add_running_task "${lock_task}" iplist worker-a
    mkfifo "${lock_input}"
    upload_resource_task_artifact "${lock_task}" worker-a "${lock_sha}" "${lock_size}" resource-token \
        < "${lock_input}" > "${lock_output}" 2>&1 &
    upload_pid=$!
    exec 8> "${lock_input}"

    # The staging file is created only after the first short state check. Wait
    # until it exists so an early lock acquisition cannot create a false pass.
    staging_seen=0
    for _ in $(seq 1 100); do
        if find "${RESOURCE_INBOX_DIR}" -maxdepth 1 -type f \
            -name "${lock_task}.*.tmp.*" -print -quit | grep -q .; then
            staging_seen=1
            break
        fi
        kill -0 "${upload_pid}" 2>/dev/null || break
        sleep 0.02
    done
    if [[ "${staging_seen}" != "1" ]]; then
        exec 8>&-
        wait "${upload_pid}" || true
        fail "slow upload did not reach its unlocked body-read stage"
    fi

    # Repeated non-blocking attempts avoid timing flakes while still proving
    # the queue lock remains available throughout the stalled body read.
    lock_acquired=0
    for _ in $(seq 1 40); do
        if flock -w 0.05 "${RESOURCE_TASK_LOCK_FILE}" true; then
            lock_acquired=1
            break
        fi
        sleep 0.05
    done
    if [[ "${lock_acquired}" != "1" ]]; then
        exec 8>&-
        wait "${upload_pid}" || true
        fail "slow upload held the global resource-task lock"
    fi
    kill -0 "${upload_pid}" 2>/dev/null || {
        exec 8>&-
        wait "${upload_pid}" || true
        fail "slow upload exited before receiving its declared body"
    }
    printf '%s' "${lock_payload}" >&8
    exec 8>&-
    wait "${upload_pid}" || fail "slow upload failed after its body was released"
    grep -Fq 'OK|' "${lock_output}" || fail "slow upload did not finish successfully"

    # A task may change after the preflight lock is released. The post-upload
    # authoritative check must reject that stale body and remove its staging
    # file instead of publishing it.
    race_task="state-changed-during-upload"
    race_payload='state-race-body'
    race_input="${tmp_dir}/state-race.fifo"
    race_output="${tmp_dir}/state-race.out"
    race_payload_file="${tmp_dir}/state-race.payload"
    race_tasks_tmp="${tmp_dir}/state-race-tasks.tsv"
    printf '%s' "${race_payload}" > "${race_payload_file}"
    race_sha="$(sha256_file_for_test "${race_payload_file}")"
    race_size="$(wc -c < "${race_payload_file}" | tr -d '[:space:]')"
    add_running_task "${race_task}" iplist worker-a
    mkfifo "${race_input}"
    upload_resource_task_artifact "${race_task}" worker-a "${race_sha}" "${race_size}" resource-token \
        < "${race_input}" > "${race_output}" 2>&1 &
    race_pid=$!
    exec 8> "${race_input}"

    race_staging_seen=0
    for _ in $(seq 1 100); do
        if find "${RESOURCE_INBOX_DIR}" -maxdepth 1 -type f \
            -name "${race_task}.*.tmp.*" -print -quit | grep -q .; then
            race_staging_seen=1
            break
        fi
        kill -0 "${race_pid}" 2>/dev/null || break
        sleep 0.02
    done
    if [[ "${race_staging_seen}" != "1" ]]; then
        exec 8>&-
        wait "${race_pid}" || true
        fail "state-race upload did not reach its unlocked body-read stage"
    fi

    resource_task_lock || fail "could not acquire task lock during stalled state-race upload"
    awk -F '|' -v OFS='|' -v task_id="${race_task}" '
        $1 == task_id {
            $3 = "failed"
            $6 = "2026-07-22T00:00:02Z"
            $11 = "test changed state during upload"
        }
        { print }
    ' "${RESOURCE_TASKS_FILE}" > "${race_tasks_tmp}"
    mv -f "${race_tasks_tmp}" "${RESOURCE_TASKS_FILE}"
    resource_task_unlock

    printf '%s' "${race_payload}" >&8
    exec 8>&-
    if wait "${race_pid}"; then
        fail "upload succeeded after its task changed state"
    fi
    assert_no_task_artifact "${race_task}"
    grep -Fq "${race_task}|iplist|failed|" "${RESOURCE_TASKS_FILE}" || \
        fail "state-race fixture did not preserve the newer failed state"
else
    printf 'flock not found; skipped resource upload lock concurrency assertion.\n' >&2
fi

printf 'manager resource upload tests passed\n'
