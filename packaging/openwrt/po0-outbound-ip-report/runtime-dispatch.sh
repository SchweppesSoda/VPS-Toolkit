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
report_once
