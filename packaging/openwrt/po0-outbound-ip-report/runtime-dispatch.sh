# Compatibility entry for installations which invoke the former engine path.
case "${1:-}" in
    --version) printf '%s\n' "$SCRIPT_VERSION"; exit 0 ;;
    --worker-only|--worker-report) printf '自建上报已退役。\n'; exit 0 ;;
esac
exec /usr/libexec/po0-outbound-ip-report-uci --official-only "$@"
