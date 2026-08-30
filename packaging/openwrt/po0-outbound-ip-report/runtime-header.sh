#!/usr/bin/env bash
set -uo pipefail

SCRIPT_NAME="po0-outbound-ip-report-openwrt"
SCRIPT_VERSION="2026.08.30+build.4"
WORKER_URL="${PO0_OUTBOUND_IP_REPORT_WORKER_URL:-}"
SOURCE_ID="${PO0_OUTBOUND_IP_REPORT_SOURCE:-router-88-1}"
IDENTITY="${PO0_OUTBOUND_IP_REPORT_IDENTITY:-router-88-1-via-gateway}"
SECRET="${PO0_OUTBOUND_IP_REPORT_SECRET:-}"
ALLOW_HTTP="${PO0_OUTBOUND_IP_REPORT_ALLOW_HTTP:-0}"
IP_CHECK_URL="https://ip9.com.cn/get"
IP_CHECK_URLS="${PO0_OUTBOUND_IP_REPORT_IP_CHECK_URLS:-}"
WANS="${PO0_OUTBOUND_IP_REPORT_WANS:-all}"
WANS_CLI_SEEN="0"
ROUTER_PROBE_URL="${PO0_OUTBOUND_IP_REPORT_ROUTER_PROBE_URL:-}"
ROUTER_PROBE_BATCH_RAW=""
SKIP_WIFI_SSIDS="${PO0_OUTBOUND_IP_REPORT_SKIP_WIFI_SSIDS:-}"
FORCE_REPORT="0"

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

sanitize_device_id_part() {
    local value="$1" out="" ch i
    value="$(to_lower "$(trim "${value}")")"
    for ((i = 0; i < ${#value}; i++)); do
        ch="${value:i:1}"
        case "${ch}" in
            [a-z0-9._-]) out+="${ch}" ;;
            *) [[ "${out}" == *- ]] || out+="-" ;;
        esac
    done
    while [[ "${out}" == -* ]]; do out="${out#-}"; done
    while [[ "${out}" == *- ]]; do out="${out%-}"; done
    [[ -n "${out}" ]] || return 1
    [[ ${#out} -le 48 ]] || out="${out:0:48}"
    printf '%s\n' "${out}"
}

normalize_report_token() {
    local value="$1" fallback="${2:-router}" normalized
    normalized="$(sanitize_device_id_part "${value}" 2>/dev/null || true)"
    printf '%s\n' "${normalized:-${fallback}}"
}

default_source_id() {
    normalize_report_token "${SOURCE_ID:-router-88-1}" 'router-88-1'
}

normalize_worker_url() {
    local value rest
    value="$(trim "$1")"
    [[ -n "${value}" ]] || { printf '\n'; return 0; }
    case "${value}" in http://*|https://*) ;; *) value="https://${value}" ;; esac
    rest="${value#*://}"
    if [[ "${rest}" != */* ]]; then value="${value}/report"; elif [[ "${value}" == */ ]]; then value="${value%/}/report"; fi
    printf '%s\n' "${value}"
}

http_allowed() {
    case "$(to_lower "${ALLOW_HTTP}")" in 1|true|yes|y) return 0 ;; *) return 1 ;; esac
}

validate_worker_url() {
    WORKER_URL="$(normalize_worker_url "${WORKER_URL}")"
    [[ -n "${WORKER_URL}" ]] || { printf '未配置 LAN Worker URL。\n' >&2; return 1; }
    case "${WORKER_URL}" in
        https://*) return 0 ;;
        http://*) http_allowed || { printf 'LAN Worker URL 必须使用 HTTPS。\n' >&2; return 1; } ;;
        *) printf 'LAN Worker URL 无效。\n' >&2; return 1 ;;
    esac
}

validate_router_probe_url() {
    ROUTER_PROBE_URL="$(trim "${ROUTER_PROBE_URL}")"
    while [[ "${ROUTER_PROBE_URL}" == */ ]]; do ROUTER_PROBE_URL="${ROUTER_PROBE_URL%/}"; done
    [[ -n "${ROUTER_PROBE_URL}" ]] || return 0
    case "${ROUTER_PROBE_URL}" in http://*|https://*) ;; *) printf '上游路由探针 URL 无效。\n' >&2; return 1 ;; esac
    case "${ROUTER_PROBE_URL}" in *\?*|*\#*) printf '上游路由探针 URL 不应包含查询参数或片段。\n' >&2; return 1 ;; esac
}

self_report_completed() {
    printf 'PO0 Outbound IP Report 已完成：%s\n' "$1"
}

self_report_incomplete() {
    printf 'PO0 Outbound IP Report 未完成：%s\n' "$1" >&2
}

self_report_append_response_target_success() {
    printf '%s\n' "$1"
}

report_detail_enabled() {
    return 1
}
