script_file_var() {
    local file="$1"
    local name="$2"
    local line value
    [[ -r "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" == "${name}="* ]] || continue
        value="${line#*=}"
        value="${value%\"}"
        value="${value#\"}"
        printf '%s\n' "${value}"
        return 0
    done < "${file}"
    return 1
}

script_file_changelog() {
    local file="$1"
    local line in_block=0 found=0
    [[ -r "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "# CHANGELOG_BEGIN" ]]; then
            in_block=1
            continue
        fi
        if [[ "${line}" == "# CHANGELOG_END" ]]; then
            break
        fi
        [[ "${in_block}" == "1" ]] || continue
        line="${line#\# }"
        line="${line#\#}"
        line="$(trim "${line}")"
        [[ -n "${line}" ]] || continue
        found=1
        printf '  %s\n' "${line}"
    done < "${file}"
    [[ "${found}" == "1" ]]
}

default_config_file() {
    if [[ -n "${CONFIG_FILE}" ]]; then
        printf '%s\n' "${CONFIG_FILE}"
    elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
        printf '%s\n' "${XDG_CONFIG_HOME}/po0-lan-client/targets.tsv"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.config/po0-lan-client/targets.tsv"
    else
        printf '%s\n' "./po0-lan-client-targets.tsv"
    fi
}

CONFIG_FILE="$(default_config_file)"

usage() {
    printf '%s\n' \
        "PO0 内网 Worker" \
        "" \
        "用法:" \
        "  bash po0-lan-client.sh" \
        "  bash po0-lan-client.sh --wizard" \
        "  bash po0-lan-client.sh --menu" \
        "  bash po0-lan-client.sh --probe --po0-host HOST --source-key home --ddns-domain home.example.com --token TOKEN --resource-token TOKEN" \
        "  bash po0-lan-client.sh --bootstrap --po0-host HOST --source-key home --ddns-domain home.example.com --token TOKEN --resource-token TOKEN --ddns-interval-seconds 3600 --install-cron" \
        "  bash po0-lan-client.sh --bootstrap --po0-host HOST --resource-token TOKEN --install-cron 1440" \
        "  curl -fsSL ${DOWNLOAD_URL} | bash -s -- --bootstrap --po0-host HOST --source-key home --ddns-domain home.example.com --token TOKEN --resource-token TOKEN --ddns-interval-seconds 3600 --install-cron" \
        "  po0-lan-client --webauth-server --listen 127.0.0.1:8787 --po0-host HOST --webauth-token TOKEN" \
        "  po0-lan-client --install-self-report-https --self-report-https-domain report.example.com --po0-host HOST --client-ip-token TOKEN --self-report-secret SECRET" \
        "  po0-lan-client --install-manager-update-http --manager-update-domain 172.81.111.68" \
        "  po0-lan-client --self-report-server --self-report-listen 127.0.0.1:8788 --po0-host HOST --client-ip-token TOKEN" \
        "" \
        "常用命令:" \
        "  --probe              只做依赖、DDNS 解析、SSH、PO0 token 连通性/权限检查，不修改 PO0 白名单。" \
        "  --bootstrap          写入本机目标配置，默认先做连通性/权限检查，再执行一次 --run。" \
        "  --install-cron [N]   安装/更新本机 Worker 轮询器；N 为兼容分钟参数，会作为资源间隔，并在未显式设置 DDNS 秒数时作为 DDNS 间隔。" \
        "                        不带 N 时，DDNS 默认 $(cron_minutes_to_seconds "${DDNS_CRON_MINUTES}") 秒，资源任务默认 ${RESOURCE_CRON_MINUTES} 分钟。" \
        "  --ddns-interval-seconds N  设置 DDNS resolver 上报间隔秒数，必须是 60 的倍数，默认 3600。" \
        "                        资源任务创建周期在 PO0 nft manager 里设置，本机只定期领取已创建任务。" \
        "                        如果目标启用了 DDNS resolver，DDNS 间隔应小于 PO0 端该 DDNS 来源 TTL。" \
        "  PO0_IPLIST_JOBS=N   iplist txt 并发下载数，默认 16，范围 1-50。" \
        "  PO0_RESOURCE_TASK_MAX_PER_RUN=N 每轮最多处理资源任务数，默认 10；0 表示不设上限。" \
        "  PO0_RESOURCE_UPLOAD_TIMEOUT_SECONDS=N 上传资源产物到 PO0 的超时秒数，默认 900；0 表示不设超时。" \
        "  PO0_RESOURCE_COMPLETE_TIMEOUT_SECONDS=N PO0 校验/导入资源产物的超时秒数，默认 600。" \
        "  PO0_REMOTE_MANAGER_TIMEOUT_SECONDS=N 默认 PO0 manager SSH 调用总超时秒数，默认 30；0 表示不设超时。" \
        "  --source-key KEY     PO0 端来源 key/名称；脚本不会解析这个值。" \
        "  --ddns-domain DOMAIN LAN Worker 要解析的 DDNS 域名；结果通过 SSH 上报 PO0。" \
        "  --install-self-report-https --self-report-https-domain DOMAIN  配置 Self-report HTTPS/Caddy，后端监听 127.0.0.1:8788。" \
        "  --install-manager-update-http --manager-update-domain HOST[:PORT]  配置 PO0 manager HTTP 更新镜像，默认公网端口 ${MANAGER_UPDATE_DEFAULT_PORT}，后端监听 127.0.0.1:8789；--manager-update-host 等价。" \
        "  --manager-update-mirror-server 启动 PO0 manager 更新镜像 HTTP 后端。" \
        "  --ddns-targets STR  DDNS 上报目标；格式 source_key|ddns_domain|host|port|user|script|token|ssh_args，多目标用分号或换行分隔。" \
        "  --domain DOMAIN      兼容旧参数：没有 --ddns-domain 时同时作为 source-key 和 DDNS 域名。" \
        "  --ssh-extra-args STR 可选 SSH 参数，例如 '-i /path/key -J jump-host'；不是私钥短语。" \
        "  --no-run             bootstrap 后不立即执行 DDNS 解析上报和资源任务轮询领取。" \
        "  --no-cron            bootstrap 时不安装本机 Worker 轮询器。" \
        "  --run                执行已配置目标的 DDNS 解析上报，并轮询领取 PO0 已创建的资源任务。" \
        "  --run-ddns           只执行 DDNS resolver 上报。" \
        "  --run-resource       只轮询领取 PO0 已创建的资源任务。" \
        "  --webauth-server     在 LAN Worker 本地运行 WebAuth 接收服务；PO0 不开放 HTTP。" \
        "  --webauth-targets STR WebAuth 上报目标；格式 source|host|port|user|script|token|ttl|ssh_args，多目标用分号或换行分隔。" \
        "  --install-webauth-service 安装 systemd 服务运行 WebAuth server。" \
        "  --webauth-probe      检查 WebAuth 依赖和 PO0 上报 token。" \
        "  --self-report-server 在 LAN Worker 本地运行自上报接收服务；访问设备先报 LAN Worker，再由 LAN Worker SSH 上报 PO0。" \
        "  --self-report-targets STR 设备自上报目标；格式 source|host|port|user|script|token|ttl|ssh_args，多目标用分号或换行分隔。" \
        "  --self-report-probe  检查自上报接收端依赖和 PO0 client-ip token。" \
        "  --version            显示当前脚本名称、版本、发布日期、路径和本机状态。" \
        "  --upgrade-self       从 ${DOWNLOAD_URL} 覆盖更新本机 po0-lan-client 命令，设置权限，并输出版本变化和更新内容。" \
        "  --backup-export [PATH] 导出 LAN Worker 完整备份；默认包含 Token、SSH 私钥和 SELF_REPORT_SECRET，备份包 chmod 600。" \
        "  --backup-import PATH  导入备份；默认只恢复配置、状态和密钥。" \
        "  --restore-cron       导入时恢复本机 managed cron block。" \
        "  --restore-systemd    导入时重新生成并启用 LAN Worker systemd service。" \
        "  --restore-caddy      导入时恢复 Self-report Caddy snippet 并刷新 Caddy。" \
        "  --restore-all        导入时恢复 cron、systemd service 和 Caddy snippet。" \
        "  --dry-run            配合 --backup-import 只显示将恢复的文件和入口。" \
        "  --wizard             进入交互式安装向导。" \
        "  --menu               进入高级菜单。" \
        "" \
        "默认 PO0_SCRIPT=${DEFAULT_PO0_SCRIPT}；可用 --po0-script 覆盖，兼容旧配置。" \
        "WebAuth server 只运行在 LAN Worker 上，推荐经 cloudflared tunnel + Cloudflare Access 暴露。" \
        "DDNS resolver 模式解析 --ddns-domain；--source-key 只用于匹配 PO0 端来源，不在本机解析。" \
        "Self-report 模式接收访问设备上报/请求里的公网 IP，再通过 PO0 的 client_ip 来源写白名单。" \
        "资源任务由 PO0 创建，PO0 端 cron 决定创建周期；本机 Worker 轮询器只负责领取待处理任务，构建/下载后通过 SSH 调 PO0 manager 上传。" \
        "配置文件会明文保存 Token，请放在可信内网机器上，并注意文件权限。"
}
