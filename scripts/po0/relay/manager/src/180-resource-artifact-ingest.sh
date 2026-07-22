validate_ipdb_file() {
    local file="$1"
    local py metadata_size metadata file_size
    local b1 b2 b3 b4
    [[ -s "${file}" ]] || {
        err "IPDB 文件为空。"
        return 1
    }
    command -v od >/dev/null 2>&1 && command -v dd >/dev/null 2>&1 || {
        err "校验 qqwry.ipdb 需要 od 和 dd。"
        return 1
    }
    read -r b1 b2 b3 b4 < <(od -An -N4 -tu1 "${file}" 2>/dev/null)
    [[ "${b1:-}" =~ ^[0-9]+$ && "${b2:-}" =~ ^[0-9]+$ && "${b3:-}" =~ ^[0-9]+$ && "${b4:-}" =~ ^[0-9]+$ ]] || {
        err "IPDB 文件头无效。"
        return 1
    }
    metadata_size=$((b1 * 16777216 + b2 * 65536 + b3 * 256 + b4))
    (( metadata_size >= 32 && metadata_size <= 1048576 )) || {
        err "IPDB 元数据长度无效。"
        return 1
    }
    file_size="$(wc -c < "${file}" | tr -d '[:space:]')"
    [[ "${file_size}" =~ ^[0-9]+$ ]] && (( file_size > metadata_size + 4 )) || {
        err "IPDB 文件缺少数据区。"
        return 1
    }
    metadata="$(dd if="${file}" bs=1 skip=4 count="${metadata_size}" 2>/dev/null)" || return 1
    printf '%s' "${metadata}" | grep -q '"fields"' || { err "IPDB 元数据缺少 fields。"; return 1; }
    printf '%s' "${metadata}" | grep -q '"languages"' || { err "IPDB 元数据缺少 languages。"; return 1; }
    printf '%s' "${metadata}" | grep -q '"node_count"' || { err "IPDB 元数据缺少 node_count。"; return 1; }

    py="$(ipdb_python_cmd 2>/dev/null || true)"
    [[ -n "${py}" ]] || return 0
    "${py}" - "${file}" <<'PY' >/dev/null 2>&1
import json
import struct
import sys

path = sys.argv[1]
with open(path, "rb") as fh:
    header = fh.read(4)
    if len(header) != 4:
        raise SystemExit(1)
    metadata_size = struct.unpack(">I", header)[0]
    if metadata_size < 32 or metadata_size > 1024 * 1024:
        raise SystemExit(1)
    metadata = json.loads(fh.read(metadata_size).decode("utf-8"))
    if not isinstance(metadata.get("fields"), list):
        raise SystemExit(1)
    if "languages" not in metadata or "node_count" not in metadata:
        raise SystemExit(1)
    if fh.read(1) == b"":
        raise SystemExit(1)
PY
}

install_received_ipdb() {
    local source="$1"
    local tmp backup
    validate_ipdb_file "${source}" || return 1
    make_temp_file "${IPDB_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    cp "${source}" "${tmp}" || return 1
    validate_ipdb_file "${tmp}" || return 1
    if [[ -f "${IPDB_FILE}" ]]; then
        backup="${BACKUP_DIR}/qqwry.ipdb.$(date '+%Y%m%d_%H%M%S')"
        cp "${IPDB_FILE}" "${backup}" 2>/dev/null || true
    fi
    mv -f "${tmp}" "${IPDB_FILE}" || return 1
    chmod 600 "${IPDB_FILE}" 2>/dev/null || true
}

activate_received_iplist() {
    local package="$1"
    import_iplist_package "${package}" || return 1
    load_settings 1
    if src_allowlist_enabled; then
        build_src_allowlist_cache || return 1
        backup_managed_files
        write_nft_conf || return 1
        apply_or_save_notice "iplist 已刷新并应用。" "iplist 已刷新，托管配置已更新。" || return 1
    fi
}

receive_resource_task_body_exact() {
    local output="$1"
    local expected_size="$2"
    local block_size=1048576 full_blocks remainder actual_size extra_size
    : > "${output}" || return 1
    full_blocks=$((expected_size / block_size))
    remainder=$((expected_size % block_size))
    if (( full_blocks > 0 )); then
        dd bs="${block_size}" count="${full_blocks}" iflag=fullblock status=none > "${output}" || return 1
    fi
    if (( remainder > 0 )); then
        dd bs="${remainder}" count=1 iflag=fullblock status=none >> "${output}" || return 1
    fi
    actual_size="$(wc -c < "${output}" | tr -d '[:space:]')"
    [[ "${actual_size}" == "${expected_size}" ]] || return 2
    extra_size="$(dd bs=1 count=1 status=none 2>/dev/null | wc -c | tr -d '[:space:]')" || return 1
    [[ "${extra_size}" == "0" ]] || return 3
}

record_resource_task_upload_locked() {
    local task_id="$1"
    local worker="$2"
    local expected_type="$3"
    local expected_path="$4"
    local reported_sha="$5"
    local reported_size="$6"
    local upload_tmp="$7"
    local line id type status created claimed finished task_worker artifact sha size message
    local tmp previous_path="" found=0 result=""
    make_temp_file "${RESOURCE_TASKS_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ -n "${line}" && "${line}" != \#* ]]; then
            IFS='|' read -r id type status created claimed finished task_worker artifact sha size message <<< "${line}"
            if [[ "${id}" == "${task_id}" ]]; then
                found=1
                if [[ "${type}" != "${expected_type}" || "${status}" != "running" || "${task_worker}" != "${worker}" ]]; then
                    result="state_mismatch"
                elif [[ -n "${artifact}" || -n "${sha}" || -n "${size}" ]]; then
                    if [[ "${artifact}" == "${expected_path}" && "${sha,,}" == "${reported_sha,,}" && "${size}" == "${reported_size}" && -f "${expected_path}" ]]; then
                        result="duplicate"
                    else
                        result="artifact_conflict"
                    fi
                else
                    printf '%s|%s|running|%s|%s||%s|%s|%s|%s|%s\n' \
                        "${id}" "${type}" "${created}" "${claimed}" "${task_worker}" \
                        "${expected_path}" "${reported_sha,,}" "${reported_size}" "资源任务文件已上传，等待校验导入" >> "${tmp}"
                    result="recorded"
                    continue
                fi
            fi
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${RESOURCE_TASKS_FILE}"
    [[ "${found}" == "1" ]] || result="not_found"
    case "${result}" in
        recorded)
            if [[ -e "${expected_path}" ]]; then
                make_temp_file "${expected_path}" || {
                    rm -f -- "${tmp}" 2>/dev/null || true
                    return 1
                }
                previous_path="${TEMP_FILE_RESULT}"
                rm -f -- "${previous_path}" 2>/dev/null || {
                    rm -f -- "${tmp}" 2>/dev/null || true
                    return 1
                }
                mv -f "${expected_path}" "${previous_path}" || {
                    rm -f -- "${tmp}" 2>/dev/null || true
                    return 1
                }
            fi
            if ! mv -f "${upload_tmp}" "${expected_path}"; then
                [[ -z "${previous_path}" ]] || mv -f "${previous_path}" "${expected_path}" 2>/dev/null || true
                rm -f -- "${tmp}" 2>/dev/null || true
                return 6
            fi
            chmod 600 "${expected_path}" 2>/dev/null || true
            if ! mv -f "${tmp}" "${RESOURCE_TASKS_FILE}"; then
                rm -f -- "${expected_path}" 2>/dev/null || true
                [[ -z "${previous_path}" ]] || mv -f "${previous_path}" "${expected_path}" 2>/dev/null || true
                rm -f -- "${tmp}" 2>/dev/null || true
                return 1
            fi
            [[ -z "${previous_path}" ]] || rm -f -- "${previous_path}" 2>/dev/null || true
            return 0
            ;;
        duplicate) rm -f -- "${tmp}" 2>/dev/null || true; return 2 ;;
        state_mismatch) rm -f -- "${tmp}" 2>/dev/null || true; return 3 ;;
        artifact_conflict) rm -f -- "${tmp}" 2>/dev/null || true; return 4 ;;
        not_found) rm -f -- "${tmp}" 2>/dev/null || true; return 5 ;;
        *) rm -f -- "${tmp}" 2>/dev/null || true; return 1 ;;
    esac
}

upload_resource_task_artifact() {
    local task_id="$1"
    local worker="$2"
    local reported_sha="$3"
    local reported_size="$4"
    local token="$5"
    local line id type status created claimed finished task_worker artifact sha size message
    local expected_path tmp actual_sha actual_size found=0 max_bytes receive_rc record_rc snapshot_type
    [[ "${task_id}" =~ ^[A-Za-z0-9._-]+$ ]] || { printf 'ERROR|任务 ID 无效\n'; return 1; }
    [[ "${worker}" =~ ^[A-Za-z0-9._:-]{1,80}$ ]] || { printf 'ERROR|worker_id 无效\n'; return 1; }
    [[ "${reported_sha}" =~ ^[A-Fa-f0-9]{64}$ ]] || { printf 'ERROR|SHA256 无效\n'; return 1; }
    reported_size="$(resource_task_normalize_size "${reported_size}")" || { printf 'ERROR|文件大小无效\n'; return 1; }
    resource_task_token_matches "${token}" || { printf 'ERROR|Token 错误\n'; return 1; }
    command -v sha256sum >/dev/null 2>&1 || { printf 'ERROR|PO0 缺少 sha256sum\n'; return 1; }
    command -v dd >/dev/null 2>&1 || { printf 'ERROR|PO0 缺少 dd\n'; return 1; }
    snapshot_type="$(resource_task_type_for_id_readonly "${task_id}" 2>/dev/null || true)"
    [[ -n "${snapshot_type}" ]] || { printf 'ERROR|任务不存在\n'; return 1; }
    max_bytes="$(resource_task_upload_max_bytes "${snapshot_type}" 2>/dev/null || true)"
    [[ -n "${max_bytes}" ]] || { printf 'ERROR|资源上传大小上限配置无效\n'; return 1; }
    resource_task_size_within_limit "${reported_size}" "${max_bytes}" || {
        printf 'ERROR|声明文件大小超过 %s 上限（%s bytes）\n' "${snapshot_type}" "${max_bytes}"
        return 1
    }
    resource_task_lock || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "${line}" && "${line}" != \#* ]] || continue
        IFS='|' read -r id type status created claimed finished task_worker artifact sha size message <<< "${line}"
        if [[ "${id}" == "${task_id}" ]]; then
            found=1
            [[ "${status}" == "running" && "${task_worker}" == "${worker}" ]] || {
                resource_task_unlock
                printf 'ERROR|任务状态或领取机器不匹配\n'
                return 1
            }
            break
        fi
    done < "${RESOURCE_TASKS_FILE}"
    [[ "${found}" == "1" ]] || {
        resource_task_unlock
        printf 'ERROR|任务不存在\n'
        return 1
    }
    [[ "${type}" == "${snapshot_type}" ]] || {
        resource_task_unlock
        printf 'ERROR|任务类型已变化\n'
        return 1
    }
    max_bytes="$(resource_task_upload_max_bytes "${type}" 2>/dev/null || true)"
    [[ -n "${max_bytes}" ]] || {
        resource_task_unlock
        printf 'ERROR|资源上传大小上限配置无效\n'
        return 1
    }
    resource_task_size_within_limit "${reported_size}" "${max_bytes}" || {
        resource_task_unlock
        printf 'ERROR|声明文件大小超过 %s 上限（%s bytes）\n' "${type}" "${max_bytes}"
        return 1
    }
    expected_path="${RESOURCE_INBOX_DIR}/${task_id}.$(resource_task_artifact_name "${type}")"
    make_temp_file "${expected_path}" || {
        resource_task_unlock
        return 1
    }
    tmp="${TEMP_FILE_RESULT}"
    resource_task_unlock
    if receive_resource_task_body_exact "${tmp}" "${reported_size}"; then
        receive_rc=0
    else
        receive_rc=$?
    fi
    if [[ "${receive_rc}" -ne 0 ]]; then
        rm -f -- "${tmp}" 2>/dev/null || true
        case "${receive_rc}" in
            2) printf 'ERROR|任务文件提前结束\n' ;;
            3) printf 'ERROR|任务文件包含超出声明大小的尾随数据\n' ;;
            *) printf 'ERROR|接收任务文件失败\n' ;;
        esac
        return 1
    fi
    actual_sha="$(sha256sum "${tmp}" | awk '{print $1}')"
    actual_size="$(wc -c < "${tmp}" | tr -d '[:space:]')"
    if [[ "${actual_sha,,}" != "${reported_sha,,}" || "${actual_size}" != "${reported_size}" ]]; then
        rm -f -- "${tmp}" 2>/dev/null || true
        printf 'ERROR|SHA256 或文件大小不匹配\n'
        return 1
    fi
    resource_task_lock || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    if record_resource_task_upload_locked "${task_id}" "${worker}" "${type}" "${expected_path}" "${reported_sha}" "${reported_size}" "${tmp}"; then
        record_rc=0
    else
        record_rc=$?
    fi
    if [[ "${record_rc}" == "2" ]]; then
        rm -f -- "${tmp}" 2>/dev/null || true
        resource_task_unlock
        printf 'OK|资源任务文件已上传\n'
        return 0
    fi
    if [[ "${record_rc}" != "0" ]]; then
        rm -f -- "${tmp}" 2>/dev/null || true
        resource_task_unlock
        case "${record_rc}" in
            3) printf 'ERROR|任务状态或领取机器不匹配\n' ;;
            4) printf 'ERROR|任务已有不同的上传文件\n' ;;
            5) printf 'ERROR|任务不存在\n' ;;
            6) printf 'ERROR|保存任务文件失败\n' ;;
            *) printf 'ERROR|记录任务文件失败\n' ;;
        esac
        return 1
    fi
    resource_task_unlock
    printf 'OK|资源任务文件已上传\n'
}
