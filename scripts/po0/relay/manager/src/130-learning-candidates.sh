learned_ip_candidates() {
    [[ -s "${LEARN_LOG_FILE}" ]] || return 0
    awk -F '\t' '
        NF >= 10 {
            ip = $3
            count[ip]++
            if (!(ip in first_epoch) || $1 < first_epoch[ip]) {
                first_epoch[ip] = $1
                first_iso[ip] = $2
            }
            if (!(ip in last_epoch) || $1 > last_epoch[ip]) {
                last_epoch[ip] = $1
                last_iso[ip] = $2
            }
            key = $4 "/" $5
            if (ports[ip] == "") {
                ports[ip] = key
            } else if (index("," ports[ip] ",", "," key ",") == 0) {
                ports[ip] = ports[ip] "," key
            }
        }
        END {
            for (ip in count) {
                span = last_epoch[ip] - first_epoch[ip]
                print ip "\t" count[ip] "\t" span "\t" first_iso[ip] "\t" last_iso[ip] "\t" ports[ip]
            }
        }
    ' "${LEARN_LOG_FILE}" | sort -t "$(printf '\t')" -k2,2nr -k5,5r
}

qualified_learned_ip_candidates() {
    learned_ip_candidates | awk -F '\t' \
        -v min_hits="${LEARN_IP_MIN_HITS}" \
        -v min_span="${LEARN_IP_MIN_SPAN_SECONDS}" \
        '($2 >= min_hits) || ($2 >= 2 && $3 >= min_span)'
}

learned_cidr24_candidates() {
    [[ -s "${LEARN_LOG_FILE}" ]] || return 0
    awk -F '\t' '
        NF >= 10 {
            split($3, o, ".")
            net = o[1] "." o[2] "." o[3] ".0/24"
            total[net]++
            if (!seen[net SUBSEP $3]++) unique[net]++
            if (!(net in first_epoch) || $1 < first_epoch[net]) {
                first_epoch[net] = $1
                first_iso[net] = $2
            }
            if (!(net in last_epoch) || $1 > last_epoch[net]) {
                last_epoch[net] = $1
                last_iso[net] = $2
            }
        }
        END {
            for (net in total) {
                if (unique[net] >= 2 || total[net] >= 3) {
                    span = last_epoch[net] - first_epoch[net]
                    print net "\t" unique[net] "\t" total[net] "\t" span "\t" first_iso[net] "\t" last_iso[net]
                }
            }
        }
    ' "${LEARN_LOG_FILE}" | sort -t "$(printf '\t')" -k2,2nr -k3,3nr -k6,6r
}

qualified_learned_cidr24_candidates() {
    learned_cidr24_candidates | awk -F '\t' \
        -v min_hits="${LEARN_NET24_MIN_HITS}" \
        -v min_unique="${LEARN_NET24_MIN_UNIQUE_IPS}" \
        '($2 >= min_unique) || ($3 >= min_hits)'
}

learned_cidr16_candidates() {
    [[ -s "${LEARN_LOG_FILE}" ]] || return 0
    awk -F '\t' '
        NF >= 10 {
            split($3, o, ".")
            net = o[1] "." o[2] ".0.0/16"
            net24 = o[1] "." o[2] "." o[3] ".0/24"
            total[net]++
            if (!seen_ip[net SUBSEP $3]++) unique_ip[net]++
            if (!seen_net24[net SUBSEP net24]++) unique_24[net]++
            if (!(net in first_epoch) || $1 < first_epoch[net]) {
                first_epoch[net] = $1
                first_iso[net] = $2
            }
            if (!(net in last_epoch) || $1 > last_epoch[net]) {
                last_epoch[net] = $1
                last_iso[net] = $2
            }
        }
        END {
            for (net in total) {
                span = last_epoch[net] - first_epoch[net]
                print net "\t" unique_ip[net] "\t" unique_24[net] "\t" total[net] "\t" span "\t" first_iso[net] "\t" last_iso[net]
            }
        }
    ' "${LEARN_LOG_FILE}" | sort -t "$(printf '\t')" -k3,3nr -k2,2nr -k4,4nr -k7,7r
}

qualified_learned_cidr16_candidates() {
    learned_cidr16_candidates | awk -F '\t' \
        -v min_hits="${LEARN_NET16_MIN_HITS}" \
        -v min_unique_24="${LEARN_NET16_MIN_UNIQUE_24S}" \
        '($3 >= min_unique_24) || ($4 >= min_hits)'
}

print_learning_daily_summary() {
    local row idx=1
    local day events first last unique_ips unique_24s unique_16s top_ips top_24s top_16s updated
    local -a rows=()
    [[ -s "${LEARN_SUMMARY_FILE}" ]] || return 0
    mapfile -t rows < <(awk -F '\t' 'NF >= 11 && $1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { print }' "${LEARN_SUMMARY_FILE}" | tail -n 7)
    [[ ${#rows[@]} -gt 0 ]] || return 0
    echo ""
    echo "每日历史汇总（最近 7 天）："
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r day events first last unique_ips unique_24s unique_16s top_ips top_24s top_16s updated <<< "${row}"
        printf '  [%d] %s | 归档 %s 条 | 来源 IP %s 个 | /24 %s 个 | /16 %s 个\n' \
            "${idx}" "${day}" "${events}" "${unique_ips}" "${unique_24s}" "${unique_16s}"
        printf '      事件时间: %s -> %s\n' "$(format_learn_time "${first}")" "$(format_learn_time "${last}")"
        [[ -n "${top_ips}" ]] && printf '      Top IP: %s\n' "${top_ips}"
        [[ -n "${top_24s}" ]] && printf '      Top /24: %s\n' "${top_24s}"
        ((idx++))
    done
}

print_learning_stats() {
    local row idx=1
    local ipdb_ready=0 ip_info
    local -a rows=()
    ipdb_lookup_ready && ipdb_ready=1
    printf '学习日志   : %s（%s 条事件，%s）\n' \
        "${LEARN_LOG_FILE}" "$(learning_log_count)" "$(format_bytes "$(learning_log_size_bytes)")"
    printf '每日汇总   : %s（%s 天）\n' "${LEARN_SUMMARY_FILE}" "$(learning_summary_count)"
    printf '自动压缩   : 跨 UTC 日期归档；或超过 %s / %s 行时保留最近 %s 行；每 %s 条做一次大小兜底检查\n' \
        "$(format_bytes "${LEARN_LOG_MAX_BYTES}")" "${LEARN_LOG_KEEP_LINES}" "${LEARN_LOG_KEEP_LINES}" \
        "${LEARN_COMPACT_CHECK_INTERVAL}"
    printf 'IPDB 数据  : %s\n' "$(ipdb_status_label)"
    if [[ ! -s "${LEARN_LOG_FILE}" ]]; then
        echo "  (暂无学习记录)"
        print_learning_daily_summary
        return 0
    fi
    echo ""
    echo "来源 IP 统计："
    mapfile -t rows < <(learned_ip_candidates | head -n 30)
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "  (暂无可用来源 IP)"
    else
        for row in "${rows[@]}"; do
            IFS=$'\t' read -r SELECTED_LEARN_CIDR count span first last ports <<< "${row}"
            ip_info="$(ipdb_lookup_ip "${SELECTED_LEARN_CIDR}" "${ipdb_ready}")"
            printf '  [%d] %s | 命中 %s 次 | 观察 %s | %s\n' \
                "${idx}" "${SELECTED_LEARN_CIDR}" "${count}" "$(format_seconds "${span}")" "${ip_info}"
            printf '      时间: %s -> %s | 中转机监听端口: %s\n' \
                "$(format_learn_time "${first}")" "$(format_learn_time "${last}")" "${ports}"
            ((idx++))
        done
    fi

    echo ""
    echo "/24 候选网段："
    idx=1
    mapfile -t rows < <(learned_cidr24_candidates | head -n 20)
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "  (暂无 /24 候选)"
    else
        for row in "${rows[@]}"; do
            IFS=$'\t' read -r cidr unique total span first last <<< "${row}"
            printf '  [%d] %s | 来源 IP %s 个 | 命中 %s 次 | 观察 %s\n' \
                "${idx}" "${cidr}" "${unique}" "${total}" "$(format_seconds "${span}")"
            printf '      时间: %s -> %s\n' "$(format_learn_time "${first}")" "$(format_learn_time "${last}")"
            ((idx++))
        done
    fi

    echo ""
    echo "/16 候选网段（高风险）："
    idx=1
    mapfile -t rows < <(learned_cidr16_candidates | head -n 20)
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "  (暂无 /16 候选)"
    else
        for row in "${rows[@]}"; do
            IFS=$'\t' read -r cidr unique unique24 total span first last <<< "${row}"
            printf '  [%d] %s | 来源 IP %s 个 | 覆盖 /24 %s 个 | 命中 %s 次 | 观察 %s\n' \
                "${idx}" "${cidr}" "${unique}" "${unique24}" "${total}" "$(format_seconds "${span}")"
            printf '      时间: %s -> %s\n' "$(format_learn_time "${first}")" "$(format_learn_time "${last}")"
            ((idx++))
        done
    fi
    print_learning_daily_summary
}

select_learned_ip_candidate() {
    local choice row ip count span first last ports
    local ipdb_ready=0 ip_info
    local -a rows=()
    SELECTED_LEARN_CIDR=""
    SELECTED_LEARN_NOTE=""
    ipdb_lookup_ready && ipdb_ready=1
    mapfile -t rows < <(qualified_learned_ip_candidates | head -n 50)
    [[ ${#rows[@]} -gt 0 ]] || {
        err "暂无达到门槛的学习 IP（至少 ${LEARN_IP_MIN_HITS} 次，或 2 次且跨度 >= $(format_seconds "${LEARN_IP_MIN_SPAN_SECONDS}")）。"
        return 1
    }
    local idx=1
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r ip count span first last ports <<< "${row}"
        ip_info="$(ipdb_lookup_ip "${ip}" "${ipdb_ready}")"
        printf '  [%d] %s | 命中 %s 次 | 观察 %s | %s\n' \
            "${idx}" "${ip}" "${count}" "$(format_seconds "${span}")" "${ip_info}"
        printf '      最近: %s | 中转机监听端口: %s\n' "$(format_learn_time "${last}")" "${ports}"
        ((idx++))
    done
    choice="$(read_prompt "请选择要加入自定义白名单的 IP [1-${#rows[@]}]: ")" || return 1
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#rows[@]} )) || return 1
    IFS=$'\t' read -r ip count span first last ports <<< "${rows[$((choice - 1))]}"
    SELECTED_LEARN_CIDR="${ip}/32"
    SELECTED_LEARN_NOTE="learned hits=${count}, span=$(format_seconds "${span}"), last=${last}, ports=${ports}"
}

select_learned_cidr24_candidate() {
    local choice row cidr unique total span first last
    local -a rows=()
    SELECTED_LEARN_CIDR=""
    SELECTED_LEARN_NOTE=""
    mapfile -t rows < <(qualified_learned_cidr24_candidates | head -n 50)
    [[ ${#rows[@]} -gt 0 ]] || {
        err "暂无达到门槛的 /24 候选（至少 ${LEARN_NET24_MIN_UNIQUE_IPS} 个 IP，或 ${LEARN_NET24_MIN_HITS} 次命中）。"
        return 1
    }
    local idx=1
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r cidr unique total span first last <<< "${row}"
        printf '  [%d] %s | 来源 IP %s 个 | 命中 %s 次 | 观察 %s | 最近 %s\n' \
            "${idx}" "${cidr}" "${unique}" "${total}" "$(format_seconds "${span}")" "$(format_learn_time "${last}")"
        ((idx++))
    done
    choice="$(read_prompt "请选择要加入自定义白名单的 /24 网段 [1-${#rows[@]}]: ")" || return 1
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#rows[@]} )) || return 1
    IFS=$'\t' read -r cidr unique total span first last <<< "${rows[$((choice - 1))]}"
    SELECTED_LEARN_CIDR="${cidr}"
    SELECTED_LEARN_NOTE="learned /24 unique=${unique}, hits=${total}, span=$(format_seconds "${span}"), last=${last}"
}

select_learned_cidr16_candidate() {
    local choice row cidr unique unique24 total span first last
    local -a rows=()
    SELECTED_LEARN_CIDR=""
    SELECTED_LEARN_NOTE=""
    mapfile -t rows < <(qualified_learned_cidr16_candidates | head -n 50)
    [[ ${#rows[@]} -gt 0 ]] || {
        err "暂无达到门槛的 /16 候选（至少 ${LEARN_NET16_MIN_UNIQUE_24S} 个 /24，或 ${LEARN_NET16_MIN_HITS} 次命中）。"
        return 1
    }
    local idx=1
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r cidr unique unique24 total span first last <<< "${row}"
        printf '  [%d] %s | 来源 IP %s 个 | 覆盖 /24 %s 个 | 命中 %s 次 | 观察 %s | 最近 %s\n' \
            "${idx}" "${cidr}" "${unique}" "${unique24}" "${total}" "$(format_seconds "${span}")" "$(format_learn_time "${last}")"
        ((idx++))
    done
    choice="$(read_prompt "请选择要加入自定义白名单的 /16 网段 [1-${#rows[@]}]: ")" || return 1
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#rows[@]} )) || return 1
    IFS=$'\t' read -r cidr unique unique24 total span first last <<< "${rows[$((choice - 1))]}"
    SELECTED_LEARN_CIDR="${cidr}"
    SELECTED_LEARN_NOTE="learned /16 unique_ip=${unique}, unique_24=${unique24}, hits=${total}, span=$(format_seconds "${span}"), last=${last}"
}
