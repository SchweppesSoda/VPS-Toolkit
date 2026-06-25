cron_begin_marker() {
    printf '# PO0_SELF_REPORT_BEGIN %s\n' "${CONFIG_FILE}"
}

cron_end_marker() {
    printf '# PO0_SELF_REPORT_END %s\n' "${CONFIG_FILE}"
}

write_cron_without_managed_block() {
    awk '/# PO0_SELF_REPORT_BEGIN/{skip=1; next} /# PO0_SELF_REPORT_END/{skip=0; next} !skip{print}'
}

cron_managed_block_exists() {
    command -v crontab >/dev/null 2>&1 || return 1
    crontab -l 2>/dev/null | grep -q '^# PO0_SELF_REPORT_BEGIN'
}
