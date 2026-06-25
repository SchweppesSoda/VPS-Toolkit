write_learning_runner() {
    local script_path escaped_path tmp
    script_path="$(current_script_path)" || return 1
    printf -v escaped_path '%q' "${script_path}"
    tmp="${LEARN_RUNNER}.tmp.$$"
    mkdir -p "$(dirname "${LEARN_RUNNER}")" || return 1
    cat > "${tmp}" <<EOF
#!/usr/bin/env bash
exec /usr/bin/env bash ${escaped_path} --learn-service
EOF
    chmod 0755 "${tmp}" || return 1
    mv -f "${tmp}" "${LEARN_RUNNER}"
}

write_learning_service_unit() {
    cat > "${LEARN_SERVICE_FILE}" <<EOF
[Unit]
Description=nftables relay source IP learning service
After=network-online.target nftables.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=${LEARN_RUNNER}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

enable_learning_service() {
    command -v systemctl &>/dev/null || {
        err "系统缺少 systemctl，无法安装学习服务。"
        return 1
    }
    install_conntrack_if_needed || return 1
    write_learning_runner || return 1
    write_learning_service_unit || return 1
    systemctl daemon-reload || return 1
    systemctl enable --now "${LEARN_SERVICE_NAME}" || return 1
}

disable_learning_service() {
    command -v systemctl &>/dev/null || {
        err "系统缺少 systemctl。"
        return 1
    }
    systemctl disable --now "${LEARN_SERVICE_NAME}" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
}
