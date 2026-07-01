do_full_backup_import() {
    local archive="${1:-}" restore_cron=0 restore_systemd=0 restore_nftables=0 restore_keys=0 work local_status arg temp_parent
    PO0_FULL_RESTORE_DRY_RUN=0
    shift || true
    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "${arg}" in
            --restore-cron)
                restore_cron=1
                ;;
            --restore-systemd)
                restore_systemd=1
                ;;
            --restore-nftables|--restore-system)
                restore_nftables=1
                ;;
            --restore-report-keys|--restore-authorized-keys)
                restore_keys=1
                ;;
            --restore-all)
                restore_cron=1
                restore_systemd=1
                restore_nftables=1
                restore_keys=1
                ;;
            --dry-run)
                PO0_FULL_RESTORE_DRY_RUN=1
                ;;
            *)
                err "未知导入参数：${arg}"
                return 1
                ;;
        esac
        shift
    done
    [[ -n "${archive}" ]] || { err "缺少备份包路径。"; return 1; }
    [[ -r "${archive}" ]] || { err "无法读取备份包：${archive}"; return 1; }
    command -v tar >/dev/null 2>&1 || { err "缺少 tar，无法导入完整备份。"; return 1; }
    validate_full_backup_tar_members "${archive}" || return 1
    if [[ "${PO0_FULL_RESTORE_DRY_RUN:-0}" == "1" ]]; then
        temp_parent="${TMPDIR:-/tmp}"
    else
        ensure_layout || return 1
        temp_parent="${BACKUP_DIR}"
    fi
    make_temp_dir "${temp_parent}" "po0-full-restore" || return 1
    work="${TEMP_DIR_RESULT}"
    chmod 700 "${work}" 2>/dev/null || true
    tar -xzf "${archive}" -C "${work}" || return 1
    [[ -f "${work}/manifest.env" ]] || { err "备份包缺少 manifest.env。"; return 1; }
    local_status=0
    restore_conf_dir_from_full_backup "${work}" || local_status=1
    if [[ "${local_status}" == "0" && "${PO0_FULL_RESTORE_DRY_RUN:-0}" != "1" ]]; then
        load_settings 1 || true
        load_rules 1 || true
    fi
    if [[ "${restore_cron}" == "1" ]]; then
        restore_managed_cron_blocks_from_full_backup "${work}" || local_status=1
    fi
    if [[ "${restore_nftables}" == "1" ]]; then
        restore_nftables_system_from_full_backup "${work}" || local_status=1
    fi
    if [[ "${restore_systemd}" == "1" ]]; then
        restore_systemd_from_full_backup "${work}" || local_status=1
    fi
    if [[ "${restore_keys}" == "1" ]]; then
        restore_report_keys_from_full_backup "${work}" || local_status=1
    fi
    [[ "${local_status}" == "0" ]] || return 1
    if [[ "${PO0_FULL_RESTORE_DRY_RUN:-0}" == "1" ]]; then
        success "PO0 完整备份 dry-run 完成，未写入 live state：${archive}"
    else
        success "PO0 完整备份已导入：${archive}"
    fi
    if (( restore_cron == 0 && restore_systemd == 0 && restore_nftables == 0 && restore_keys == 0 )); then
        info "默认仅恢复 ${CONF_DIR} 下的配置、token、状态和资源文件；cron、systemd/nftables 和 authorized_keys 未恢复。需要时加 --restore-cron、--restore-systemd、--restore-nftables、--restore-report-keys 或 --restore-all。"
    fi
}

do_full_backup_restore_interactive() {
    local choice path
    print_menu_section "PO0 完整备份 / 恢复"
    print_menu_item 1 "导出完整备份"
    print_menu_item 2 "导入：只恢复配置、token、状态和资源文件"
    print_menu_item 3 "导入：恢复全部（含 cron/systemd/nftables/authorized_keys）"
    print_menu_item 0 "返回"
    print_menu_footer
    read_menu_choice_or_return choice "请选择操作 [0-3]: " || return 0
    case "${choice}" in
        1)
            path="$(prompt_with_default "备份输出路径" "$(full_backup_default_path)")"
            do_full_backup_export "${path}"
            ;;
        2)
            path="$(prompt_with_default "备份包路径" "")"
            [[ -n "${path}" ]] || return 0
            do_full_backup_import "${path}"
            ;;
        3)
            path="$(prompt_with_default "备份包路径" "")"
            [[ -n "${path}" ]] || return 0
            warn "即将恢复 cron、systemd/nftables 和 PO0 受限 authorized_keys；这会修改本机运行入口。"
            confirm_strong_yes "确认恢复全部" || return 0
            do_full_backup_import "${path}" --restore-all
            ;;
        0)
            return 0
            ;;
        *)
            err "无效选择。"
            return 1
            ;;
    esac
}

print_cli_usage() {
    printf '%s\n' \
        "用法: nftables-relay-manager.sh [命令]" \
        "" \
        "PO0 主控部署（Release asset 下载到 PO0 后运行；首次部署也可 scp 上传同一 asset）:" \
        "  curl -fsSL ${MANAGER_DOWNLOAD_URL} -o ${MANAGER_INSTALL_PATH}" \
        "  chmod +x ${MANAGER_INSTALL_PATH} && bash ${MANAGER_INSTALL_PATH}" \
        "" \
        "LAN Worker / 客户端快速启动（先在 PO0 上生成命令，再到 LAN Worker/客户端执行）:" \
        "  bash ${MANAGER_INSTALL_PATH} --show-client-deploy-commands" \
        "  bash ${MANAGER_INSTALL_PATH} --worker-token-bundle" \
        "  bash ${MANAGER_INSTALL_PATH} --show-client-deploy-commands lan-resource" \
        "  bash ${MANAGER_INSTALL_PATH} --show-client-deploy-commands lan-ddns" \
        "  bash ${MANAGER_INSTALL_PATH} --show-client-deploy-commands self-server" \
        "  bash ${MANAGER_INSTALL_PATH} --show-client-deploy-commands egern" \
        "" \
        "常用命令:" \
        "  --version        以面板显示当前脚本名称、版本、build 构建标识、路径和默认安装路径。" \
        "  --changelog      显示当前版本更新内容；适合 scp 上传后确认本次变化。" \
        "  --upgrade-manager-from-lan [URL]" \
        "                   从 LAN Worker HTTP 更新镜像拉取新版 PO0 manager，校验 resource token HMAC 后原子替换脚本。" \
        "  --backup-export [PATH]" \
        "                   导出 PO0 完整备份；默认包含 token、状态、资源文件、受限 key 信息和脚本快照，备份包 chmod 600。" \
        "  --backup-import PATH [--restore-cron] [--restore-systemd] [--restore-nftables] [--restore-report-keys] [--restore-all] [--dry-run]" \
        "                   导入完整备份；默认只恢复 ${CONF_DIR} 下的配置、token、状态和资源文件。" \
        "  --render         将计划生成的 nftables 配置输出到标准输出。" \
        "  --refresh-ddns   按 LAN Worker/路由器已上报且仍在 TTL 内的 DDNS 结果重建/应用；PO0 不做本地 DNS 解析，也不延长原上报 TTL。" \
        "  --collect-blocked [since]" \
        "                   采集 po0-block 内核日志到被阻挡访问 TSV。默认范围: 1 hour ago。" \
        "  白名单模式      manual_only / trusted_dynamic / region_plus_trusted / region_only / custom_sources。" \
        "                   custom_sources 可在菜单中手动组合 manual、ssh_temp、ddns、client_ip、ssh_report、webauth、learned、region。" \
        "" \
        "DDNS / Worker 上报接口（SSH only，PO0 不开放 HTTP）:" \
        "  --ddns-report <source-key> <公网IPv4[,公网IPv4...]> [token]" \
        "                   接收 LAN Worker/路由器解析好的 DDNS A 记录，写入 PO0 DDNS 来源白名单。" \
        "  --ddns-report-check <source-key> [token]" \
        "                   只读检查 PO0 DDNS 来源 key 和上报 token，供 LAN Worker probe 使用。" \
        "  --outbound-ip-report / --outbound-ip-report-check" \
        "                   旧脚本兼容别名；新自上报应先报 LAN Worker，再由 LAN Worker 调 --client-ip-report。" \
        "  --client-ip-report <source-id> <ipv4> <token> [identity] [ttl]" \
        "                   接收 LAN Worker self-report 代报的访问设备公网 IPv4。" \
        "  --client-ip-report-check <source-id> [token]" \
        "                   只读检查客户端 IP 上报 token。" \
        "  --ssh-ip-report <source-id> <ipv4> <token> [identity] [ttl] [cidr-prefix]" \
        "                   接收 Egern / 直接 SSH 上报的当前出口公网 IPv4，写入 ssh_report 来源；cidr-prefix 仅允许 32 或 24。" \
        "  --ssh-ip-report-check <source-id> [token]" \
        "                   只读检查 SSH report token。" \
        "  --webauth-report <source-id> <ipv4> <identity> <expires-at> <token> [note]" \
        "                   接收 LAN Worker WebAuth 上报；PO0 不开放 HTTP。" \
        "  --webauth-report-check <source-id> [token]" \
        "                   只读检查 WebAuth 上报 token。" \
        "  --automation-mode <regular|attack>" \
        "                   attack 模式冻结自动新增白名单，新自动 IP 进入待审核。" \
        "  --pending-auto-sources" \
        "                   查看自动来源待审核 IP。" \
        "  --cleanup-dynamic-allowlist" \
        "                   清理 ddns/client_ip/ssh_report/webauth 的过期和超量 IP；默认每 source-id 保留 12 个有效 CIDR。" \
        "  --install-dynamic-allowlist-cleanup-cron [hourly|daily|weekly|monthly|CRON_EXPR]" \
        "                   安装/更新动态来源清理 cron，默认 daily；默认每 source-id 保留 12 个有效 CIDR。" \
        "  --remove-dynamic-allowlist-cleanup-cron" \
        "                   删除动态来源清理 cron。" \
        "  --show-client-deploy-commands [lan-resource|lan-ddns|self-server|self-client|webauth|egern|all]" \
        "                   按主题输出 LAN Worker、Self-report、WebAuth、Egern 的部署命令；token/key 管理在白名单菜单或专用 CLI。" \
        "  --worker-token-bundle [--ensure-resource-token]" \
        "                   输出 LAN Worker 向导使用的 KEY=value token bundle（SSH only）。" \
        "  --show-report-keys [user]" \
        "                   显示普通登录 key、PO0 受限上报 key、其它 restricted key 分类。" \
        "  --show-report-key-denials [lines]" \
        "                   显示 PO0 受限上报 key 最近拒绝日志；不记录 token。" \
        "  --refresh-report-key-wrapper" \
        "                   只刷新 PO0 受限上报 key wrapper，不改 authorized_keys。" \
        "  --install-report-key <egern|worker|all> '<public-key-line>' [user]" \
        "                   追加或转换专用受限上报 public key；不接收私钥。" \
        "  --compat-check   只读检查旧配置/旧白名单/旧日志兼容状态。" \
        "  --cleanup-legacy --dry-run|--apply" \
        "                   清理旧文件候选；默认不删除 live state。" \
        "" \
        "内网资源任务管理（PO0 管理员）:" \
        "  --resource-task-create <iplist|ipdb|all>" \
        "                   创建一次资源更新任务，等待内网 Worker 领取。" \
        "  --install-resource-task-cron <iplist|ipdb|all> [hourly|daily|weekly|monthly|CRON_EXPR]" \
        "                   安装/更新 PO0 端定时创建任务。默认 daily；CRON_EXPR 需整体加引号；管道运行时会自动落盘。" \
        "  --remove-resource-task-cron" \
        "                   删除 PO0 端资源任务定时创建 cron。" \
        "  --resource-task-cron-status" \
        "                   只读输出 PO0 端资源任务定时创建状态，供 LAN Worker 菜单展示。" \
        "" \
        "内网资源任务接口（供 Worker 调用）:" \
        "  --resource-task-ping <token>" \
        "                   只读检查资源任务 token，供内网 Worker probe 使用。" \
        "  --resource-task-claim <worker_id> <token>" \
        "                   内网机器领取一个等待中的 iplist/IPDB 更新任务。" \
        "  --resource-task-upload <task_id> <worker_id> <sha256> <size> <token>" \
        "                   从标准输入接收 Worker 产物，写入 PO0 资源任务收件目录。" \
        "  --resource-task-complete <task_id> <worker_id> <sha256> <size> <token>" \
        "                   校验已回传文件，导入资源并记录任务结果。" \
        "  --resource-task-fail <task_id> <worker_id> <reason> <token>" \
        "                   记录内网机器执行失败。" \
        "" \
        "后台服务:" \
        "  --learn-service  运行后台来源 IP 学习服务。" \
        "  --help           显示本帮助。" \
        "" \
        "不带命令运行时进入交互菜单。"
}
