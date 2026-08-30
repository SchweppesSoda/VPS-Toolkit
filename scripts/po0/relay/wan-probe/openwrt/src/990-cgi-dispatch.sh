cgi_text_reply() {
    status="$1" body="$2"
    printf 'Status: %s\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\n\r\n%s\n' "${status}" "${body}"
}

cgi_json_all_reply() {
    first=1
    now="$(date +%s 2>/dev/null || printf '0')"
    printf 'Status: 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n'
    printf '{"version":"%s","observed_at":%s,"wans":[' "$(json_escape "${SCRIPT_VERSION}")" "${now}"
    list_enabled_mwan3_wans | while IFS= read -r wan; do
        wan_is_allowed "${wan}" || continue
        device="$(wan_l3_device "${wan}" 2>/dev/null || true)"
        ip="$(detect_wan_public_ipv4 "${wan}" 2>/dev/null || true)"
        [ "${first}" -eq 1 ] || printf ','
        first=0
        if [ -n "${ip}" ]; then
            printf '{"name":"%s","device":"%s","ok":true,"ip":"%s","error":null}' \
                "$(json_escape "${wan}")" "$(json_escape "${device}")" "$(json_escape "${ip}")"
        else
            printf '{"name":"%s","device":"%s","ok":false,"ip":null,"error":"public_ipv4_detection_failed"}' \
                "$(json_escape "${wan}")" "$(json_escape "${device}")"
        fi
    done
    printf ']}\n'
}

load_probe_config

case "${PROBE_ENABLED}" in 1|true|yes|on) ;; *) cgi_text_reply '503 Service Unavailable' 'probe disabled'; exit 0 ;; esac
[ "${REQUEST_METHOD:-GET}" = "GET" ] || { cgi_text_reply '405 Method Not Allowed' 'method not allowed'; exit 0; }
source_is_allowed || { cgi_text_reply '403 Forbidden' 'forbidden'; exit 0; }

query="${QUERY_STRING:-}"
case "${query}" in
    wan=*) wan="${query#wan=}"; wan="${wan%%&*}" ;;
    *) wan="" ;;
esac

case "${wan}" in
    list)
        result="$(list_enabled_mwan3_wans | while IFS= read -r item; do wan_is_allowed "${item}" && printf '%s\n' "${item}"; done)"
        [ -n "${result}" ] && cgi_text_reply '200 OK' "${result}" || cgi_text_reply '503 Service Unavailable' 'no enabled WAN'
        ;;
    all)
        cgi_json_all_reply
        ;;
    *)
        valid_wan_name "${wan}" || { cgi_text_reply '400 Bad Request' 'invalid WAN'; exit 0; }
        wan_is_enabled "${wan}" || { cgi_text_reply '404 Not Found' 'WAN not enabled'; exit 0; }
        wan_is_allowed "${wan}" || { cgi_text_reply '403 Forbidden' 'WAN not allowed'; exit 0; }
        ip="$(detect_wan_public_ipv4 "${wan}" 2>/dev/null || true)"
        [ -n "${ip}" ] && cgi_text_reply '200 OK' "${ip}" || cgi_text_reply '502 Bad Gateway' 'public IPv4 detection failed'
        ;;
esac

