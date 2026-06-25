probe_self_report_target() {
    local response failed=0 targets line source host port user script token ttl extra count=0
    have_cmd ssh || { probe_fail "缺少 ssh，无法连接 PO0。"; failed=1; }
    if have_cmd python3 || have_cmd python; then
        probe_ok "Python 可用，可运行 self-report server"
    else
        probe_fail "缺少 python3/python，无法运行 self-report server。"
        failed=1
    fi
    targets="$(self_report_targets_env)" || return 1
    [[ -n "${targets}" ]] || {
        probe_fail "没有设备自上报目标。请配置 --po0-host/--client-ip-token，或在菜单中添加设备自上报目标。"
        return 1
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" == \#* ]] || continue
        IFS='|' read -r source host port user script token ttl extra <<< "${line}"
        source="$(normalize_report_token_shell "${source:-${SELF_REPORT_SOURCE}}" "self-report")"
        host="$(sanitize_field "${host}")"
        port="$(sanitize_field "${port:-22}")"
        user="$(sanitize_field "${user:-root}")"
        script="$(sanitize_field "${script:-${DEFAULT_PO0_SCRIPT}}")"
        token="$(sanitize_field "${token}")"
        extra="$(sanitize_field "${extra:-}")"
        [[ -n "${host}" && -n "${token}" ]] || {
            probe_fail "跳过无效设备自上报目标：${line}"
            failed=1
            continue
        }
        count=$((count + 1))
        if response="$(remote_manager_call "${host}" "${port:-22}" "${user:-root}" "${script:-${DEFAULT_PO0_SCRIPT}}" "${extra}" --client-ip-report-check "${source:-${SELF_REPORT_SOURCE}}" "${token}" 2>&1)"; then
            probe_ok "设备自上报目标 ${source:-${SELF_REPORT_SOURCE}}@${host}:${port:-22} 权限检查通过：${response}"
        else
            probe_fail "设备自上报目标 ${source:-${SELF_REPORT_SOURCE}}@${host}:${port:-22} 权限检查失败：${response}"
            failed=1
        fi
    done < <(printf '%s\n' "${targets}")
    if [[ "${count}" == "0" ]]; then
        probe_fail "没有可用的设备自上报目标。"
        failed=1
    fi
    [[ "${failed}" == "0" ]]
}
