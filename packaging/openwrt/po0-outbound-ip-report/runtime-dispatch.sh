case "${1:-}" in
    "") ;;
    --force-report) FORCE_REPORT="1" ;;
    *)
        printf 'unsupported OpenWrt reporter argument: %s\n' "$1" >&2
        exit 2
        ;;
esac

WANS="$(normalize_wan_selection_list "${WANS:-}")"
SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${ENV_SKIP_WIFI_SSIDS:-}")"
validate_wan_selection || exit 1
validate_router_probe_url || exit 1
# UCI owns the run lock and procd owns both schedules. The APK engine must
# not enter the standalone client's second lock/state/scheduler layer.
if ! skip_report_for_wifi_ssid_if_needed; then
    worker_report_once
fi
