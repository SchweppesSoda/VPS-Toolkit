cron_begin_marker() {
    printf '# OUTBOUND_IP_REPORT_BEGIN %s\n' "${CONFIG_FILE}"
}

cron_end_marker() {
    printf '# OUTBOUND_IP_REPORT_END %s\n' "${CONFIG_FILE}"
}

write_cron_without_managed_block() {
    awk '
        /# OUTBOUND_IP_REPORT_BEGIN/ || /# PO0_OUTBOUND_IP_REPORT_BEGIN/ || /# PO0_SELF_REPORT_BEGIN/ {skip=1; next}
        /# OUTBOUND_IP_REPORT_END/ || /# PO0_OUTBOUND_IP_REPORT_END/ || /# PO0_SELF_REPORT_END/ {skip=0; next}
        !skip {print}
    '
}

cron_managed_block_exists() {
    command -v crontab >/dev/null 2>&1 || return 1
    crontab -l 2>/dev/null | grep -Eq '^# (OUTBOUND_IP_REPORT|PO0_OUTBOUND_IP_REPORT|PO0_SELF_REPORT)_BEGIN'
}
