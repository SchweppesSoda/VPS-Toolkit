#!/bin/bash
#
# REALITY 回落域名查找工具
# 自动检测 VPS 所在城市, 多数据源发现本地域名, 批量检测, 排序推荐
#
# 数据源:
#   1. 同网段 /24 TLS 证书扫描
#   2. 同 ASN 邻居 IP 反查
#   3. crt.sh 证书透明度日志 (自动按 VPS 所在城市/州搜索)
#   4. 动态本地域名发现 (Wikipedia 城市页面 + 行业关键词搜索)
#
# 用法:
#   chmod +x reality_dest_finder.sh
#   ./reality_dest_finder.sh                    # 完整扫描
#   ./reality_dest_finder.sh --strict           # 严格模式
#   ./reality_dest_finder.sh --relaxed          # 宽松模式
#   ./reality_dest_finder.sh --csv-only         # 只输出 CSV
#   ./reality_dest_finder.sh --skip-nmap        # 跳过 nmap 扫描
#   ./reality_dest_finder.sh --check <域名>     # 单域名深度检测
#
# 依赖: apt install -y nmap jq dnsutils openssl curl bc
#

set -uo pipefail

# ==================== 配置 ====================
SCAN_RANGE="24"
MAX_CONCURRENT=10
OUTPUT_DIR="$HOME/reality_scan"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SKIP_NMAP=false
STRICT_MODE=true
CSV_ONLY=false
CHECK_DOMAIN=""
ORIGINAL_ARG_COUNT=$#
LAST_ACTION="1"
LAST_CONFIG_FILE="$OUTPUT_DIR/.last_interactive_config"
HAD_LAST_CONFIG=false

# ==================== 颜色 ====================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[96m'; PANEL='\033[38;5;208m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*"; }

print_menu_divider() {
    echo -e "${CYAN}------------------------${NC}"
}

print_menu_section() {
    print_menu_divider
    echo -e "${BOLD}${CYAN}$1${NC}"
}

print_menu_item() {
    printf '  %b%2s%b) %s\n' "${CYAN}" "$1" "${NC}" "$2"
}

print_menu_footer() {
    print_menu_divider
}

print_panel_divider() {
    echo -e "${PANEL}------------------------${NC}"
}

print_panel_section() {
    print_panel_divider
    echo -e "${BOLD}${PANEL}$1${NC}"
}

print_panel_row() {
    local label="$1"
    shift
    printf '  %b%s%b' "${PANEL}" "${label}" "${NC}"
    if [ -t 1 ]; then
        printf '\033[24G'
    else
        printf '    '
    fi
    printf ': %s\n' "$*"
}

pause_before_return() {
    local _
    echo ""
    read -r -p "按回车返回菜单..." _ || true
}

mkdir -p "$OUTPUT_DIR"

print_usage() {
    cat <<'EOF'
用法:
  ./reality_dest_finder.sh
  ./reality_dest_finder.sh --strict
  ./reality_dest_finder.sh --relaxed
  ./reality_dest_finder.sh --csv-only
  ./reality_dest_finder.sh --skip-nmap
  ./reality_dest_finder.sh --check <域名>
  ./reality_dest_finder.sh --help

说明:
  不带参数直接运行时，会进入交互式菜单。

选项:
  --strict      严格模式。要求 TLS 1.3、X25519、HTTP/2、SNI 匹配。
  --relaxed     宽松模式。TLS 1.3 和 SNI 仍为硬条件，X25519/HTTP/2 改为扣分项。
  --csv-only    只生成 CSV，不打印文本报告。
  --skip-nmap   跳过 nmap 子网扫描。
  --check       对单个域名做深度检查。
EOF
}

mode_to_zh() {
    if [ "$1" = "true" ]; then
        echo "严格"
    else
        echo "宽松"
    fi
}

bool_to_zh() {
    if [ "$1" = "true" ]; then
        echo "是"
    else
        echo "否"
    fi
}

prompt_yes_no() {
    local prompt="$1"
    local default_answer="$2"
    local input=""
    local suffix="[y/N]"

    if [ "$default_answer" = "y" ]; then
        suffix="[Y/n]"
    fi

    while :; do
        read -r -p "$prompt $suffix: " input
        input="${input:-$default_answer}"
        case "${input,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) warn "请输入 y 或 n。" ;;
        esac
    done
}

load_last_config() {
    if [ -f "$LAST_CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        . "$LAST_CONFIG_FILE"
        HAD_LAST_CONFIG=true
    fi
}

save_last_config() {
    {
        printf 'STRICT_MODE=%q\n' "$STRICT_MODE"
        printf 'CSV_ONLY=%q\n' "$CSV_ONLY"
        printf 'SKIP_NMAP=%q\n' "$SKIP_NMAP"
        printf 'CHECK_DOMAIN=%q\n' "$CHECK_DOMAIN"
        printf 'LAST_ACTION=%q\n' "$LAST_ACTION"
    } > "$LAST_CONFIG_FILE"
}

show_last_config() {
    print_panel_section "上一次配置"
    case "$LAST_ACTION" in
        1) print_panel_row "操作" "完整扫描（严格模式）" ;;
        2) print_panel_row "操作" "完整扫描（宽松模式）" ;;
        3) print_panel_row "操作" "单域名深度检测" ;;
        *) print_panel_row "操作" "未知" ;;
    esac
    print_panel_row "只导出 CSV" "$(bool_to_zh "$CSV_ONLY")"
    print_panel_row "跳过 nmap" "$(bool_to_zh "$SKIP_NMAP")"
    if [ -n "$CHECK_DOMAIN" ]; then
        print_panel_row "深查域名" "$CHECK_DOMAIN"
    fi
    echo ""
}

show_banner() {
    local mode_label="严格"
    if ! $STRICT_MODE; then
        mode_label="宽松"
    fi

    echo ""
    echo -e "${BOLD}============================================================${NC}"
    echo -e "${BOLD}REALITY 回落域名发现与初筛${NC}"
    echo -e "${BOLD}模式: ${mode_label} | 并发: ${MAX_CONCURRENT} | 子网: /${SCAN_RANGE}${NC}"
    echo -e "${BOLD}============================================================${NC}"
    echo ""
}

interactive_config() {
    local action=""
    local default_action="1"
    local default_domain=""
    local mode_label="严格"

    load_last_config

    echo "未提供命令行参数，进入交互式模式。"
    echo "推荐直接先跑一次完整扫描（严格模式）。"
    echo ""

    if $HAD_LAST_CONFIG; then
        show_last_config
        if prompt_yes_no "是否直接沿用上一次配置" "y"; then
            return
        fi
        default_action="${LAST_ACTION:-1}"
    fi

    while :; do
        print_menu_section "操作"
        print_menu_item 1 "完整扫描（严格模式，推荐）"
        print_menu_item 2 "完整扫描（宽松模式）"
        print_menu_item 3 "单域名深度检测"
        print_menu_item 4 "查看帮助"
        print_menu_footer
        print_menu_item 0 "退出"
        print_menu_footer

        read -r -p "请选择操作 [0-4，默认 ${default_action}]: " action
        action=${action:-$default_action}
        case "$action" in
            0)
                exit 0
                ;;
            1)
                LAST_ACTION="1"
                CHECK_DOMAIN=""
                STRICT_MODE=true
                break
                ;;
            2)
                LAST_ACTION="2"
                CHECK_DOMAIN=""
                STRICT_MODE=false
                break
                ;;
            3)
                LAST_ACTION="3"
                default_domain="$CHECK_DOMAIN"
                while :; do
                    if [ -n "$default_domain" ]; then
                        read -r -p "请输入要深度检测的域名 [默认 ${default_domain}]: " CHECK_DOMAIN
                        CHECK_DOMAIN="${CHECK_DOMAIN:-$default_domain}"
                    else
                        read -r -p "请输入要深度检测的域名: " CHECK_DOMAIN
                    fi
                    [ -n "$CHECK_DOMAIN" ] && break
                    warn "域名不能为空。"
                done
                if prompt_yes_no "是否使用宽松模式展示结果" "n"; then
                    STRICT_MODE=false
                else
                    STRICT_MODE=true
                fi
                save_last_config
                return
                ;;
            4)
                print_usage
                echo ""
                pause_before_return
                ;;
            *)
                warn "请输入 0 到 4 之间的数字。"
                ;;
        esac
    done

    mode_label=$(mode_to_zh "$STRICT_MODE")
    echo "当前模式: $mode_label"

    if prompt_yes_no "是否只导出 CSV，不打印文本报告" "$( [ "$CSV_ONLY" = "true" ] && echo y || echo n )"; then
        CSV_ONLY=true
    else
        CSV_ONLY=false
    fi

    if prompt_yes_no "是否跳过 nmap 子网扫描" "$( [ "$SKIP_NMAP" = "true" ] && echo y || echo n )"; then
        SKIP_NMAP=true
    else
        SKIP_NMAP=false
    fi

    save_last_config
}

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-nmap)
            SKIP_NMAP=true
            shift
            ;;
        --strict)
            STRICT_MODE=true
            shift
            ;;
        --relaxed)
            STRICT_MODE=false
            shift
            ;;
        --csv-only)
            CSV_ONLY=true
            shift
            ;;
        --check)
            CHECK_DOMAIN="${2:-}"
            if [ -z "$CHECK_DOMAIN" ]; then
                err "--check 需要提供域名"
                exit 1
            fi
            shift 2
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            err "未知参数: $1"
            print_usage
            exit 1
            ;;
    esac
done

# ==================== 全局变量 (Step 0 填充) ====================
MY_IP=""
MY_ASN=""
MY_ASN_NUM=""
MY_CITY=""
MY_REGION=""
MY_COUNTRY=""

# ==================== 过滤规则 ====================
CF_ASNS="AS13335 AS209242"
BLACKLIST_KEYWORDS="microsoft.com apple.com google.com icloud.com amazon.com cloudflare.com googleapis.com gstatic.com facebook.com twitter.com tiktok.com"
REALITY_OVERUSED="dl.google.com www.samsung.com gateway.icloud.com swdist.apple.com www.lovelive-anime.jp"
COMMON_CDN_CNAME_KEYWORDS="cloudflare.net cloudfront.net fastly.net edgesuite.net edgekey.net akamai.net akamaiedge.net azureedge.net cdn77.org bunnycdn.net"
COMMON_CDN_SERVER_KEYWORDS="cloudflare cloudfront akamai fastly edgecast bunnycdn cdn77"

has_domain_suffix() {
    local domain="${1,,}"
    local suffix="${2,,}"
    case "$domain" in
        "$suffix"|*."$suffix") return 0 ;;
        *) return 1 ;;
    esac
}

is_cf_or_bad() {
    local domain="$1"
    for kw in $BLACKLIST_KEYWORDS; do
        has_domain_suffix "$domain" "$kw" && return 0
    done
    for kw in $REALITY_OVERUSED; do
        [ "$domain" = "$kw" ] && return 0
    done
    return 1
}

is_hot_domain() {
    local domain="$1"
    for kw in $BLACKLIST_KEYWORDS; do
        has_domain_suffix "$domain" "$kw" && return 0
    done
    return 1
}

is_number() {
    echo "$1" | grep -qE '^[0-9]+([.][0-9]+)?$'
}

ip_to_int() {
    local ip="$1"
    local a b c d
    IFS='.' read -r a b c d <<< "$ip"
    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

int_to_ip() {
    local num="$1"
    echo "$(( (num >> 24) & 255 )).$(( (num >> 16) & 255 )).$(( (num >> 8) & 255 )).$(( num & 255 ))"
}

sample_ip_from_prefix() {
    local prefix="$1"
    local base_ip cidr base_int mask network start end span rand offset

    IFS='/' read -r base_ip cidr <<< "$prefix"
    [ -n "$base_ip" ] || return 1
    [ -n "$cidr" ] || return 1
    [ "$cidr" -lt 31 ] || return 1

    base_int=$(ip_to_int "$base_ip")
    if [ "$cidr" -eq 0 ]; then
        start=1
        end=4294967294
    else
        mask=$(( (0xFFFFFFFF << (32 - cidr)) & 0xFFFFFFFF ))
        network=$(( base_int & mask ))
        start=$(( network + 1 ))
        end=$(( network + (1 << (32 - cidr)) - 2 ))
    fi

    [ "$end" -ge "$start" ] || return 1
    span=$(( end - start + 1 ))
    rand=$(( (RANDOM << 15) | RANDOM ))
    offset=$(( rand % span ))
    int_to_ip $(( start + offset ))
}

get_cert_common_name() {
    local tls_info="$1"
    echo "$tls_info" | openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null \
        | sed -n 's/.*CN=\([^,]*\).*/\1/p' | head -1
}

cert_name_matches_domain() {
    local domain="${1,,}"
    local cert_name="${2,,}"
    local suffix=""

    [ -n "$cert_name" ] || return 1
    [ "$domain" = "$cert_name" ] && return 0

    case "$cert_name" in
        \*.*)
            suffix="${cert_name#*.}"
            case "$domain" in
                *."$suffix")
                    [ "$domain" != "$suffix" ] && return 0
                    ;;
            esac
            ;;
    esac

    return 1
}

cert_matches_domain() {
    local domain="$1"
    local san_names="$2"
    local common_name="$3"
    local name=""

    for name in $san_names; do
        cert_name_matches_domain "$domain" "$name" && return 0
    done

    cert_name_matches_domain "$domain" "$common_name" && return 0
    return 1
}

detect_x25519_support() {
    local domain="$1"
    local tls_out=""

    tls_out=$(echo | timeout 5 openssl s_client -connect "${domain}:443" \
        -servername "$domain" -tls1_3 -groups X25519 2>/dev/null || true)
    if echo "$tls_out" | grep -q 'Protocol[[:space:]]*:[[:space:]]*TLSv1.3'; then
        echo "yes"
        return
    fi

    tls_out=$(echo | timeout 5 openssl s_client -connect "${domain}:443" \
        -servername "$domain" -tls1_3 -curves X25519 2>/dev/null || true)
    if echo "$tls_out" | grep -q 'Protocol[[:space:]]*:[[:space:]]*TLSv1.3'; then
        echo "yes"
    else
        echo "no"
    fi
}

measure_latency_ms() {
    local domain="$1"
    local latency connect_time

    latency=$(ping -4 -c 3 -W 2 "$domain" 2>/dev/null \
        | tail -1 | awk -F'/' '{printf "%.2f", $5}' || true)

    if ! is_number "$latency"; then
        connect_time=$(curl -4 -s --max-time 5 -o /dev/null -w '%{time_connect}' "https://${domain}" 2>/dev/null || true)
        if is_number "$connect_time" && [ "$connect_time" != "0.000000" ]; then
            latency=$(awk -v t="$connect_time" 'BEGIN { printf "%.2f", t * 1000 }')
        else
            latency="999.00"
        fi
    fi

    echo "$latency"
}

detect_cdn_risk() {
    local domain="$1"
    local headers="$2"
    local server_header="$3"
    local cname=""
    local lower_headers=""
    local lower_server=""
    local kw=""

    lower_headers=$(echo "$headers" | tr '[:upper:]' '[:lower:]')
    lower_server=$(echo "$server_header" | tr '[:upper:]' '[:lower:]')

    if echo "$lower_headers" | grep -qE '^cf-ray:|^cf-cache-status:|^server:[[:space:]]*cloudflare'; then
        echo "high:cloudflare-header"
        return
    fi

    cname=$(dig +short CNAME "$domain" 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/\.$//')
    for kw in $COMMON_CDN_CNAME_KEYWORDS; do
        if echo "$cname" | grep -q "$kw"; then
            echo "high:cname:$kw"
            return
        fi
    done

    if echo "$lower_headers" | grep -qE '^x-served-by:|^x-cache:|^via:|^x-cache-hits:'; then
        echo "medium:http-cache-header"
        return
    fi

    for kw in $COMMON_CDN_SERVER_KEYWORDS; do
        if echo "$lower_server" | grep -q "$kw"; then
            echo "low:server:$kw"
            return
        fi
    done

    echo "none"
}

detect_redirect_risk() {
    local domain="$1"
    local meta effective_url redirect_count status_code effective_host

    meta=$(curl -4 -sS -o /dev/null -I -L --max-time 8 \
        -w '%{url_effective}|%{num_redirects}|%{http_code}' "https://${domain}" 2>/dev/null || true)
    [ -n "$meta" ] || {
        echo "unknown"
        return
    }

    effective_url="${meta%%|*}"
    redirect_count="${meta#*|}"
    redirect_count="${redirect_count%%|*}"
    status_code="${meta##*|}"
    effective_host=$(echo "$effective_url" | sed -E 's#^[A-Za-z0-9+.-]+://##; s#/.*$##; s/:.*$//')
    effective_host="${effective_host,,}"

    if [ -z "$redirect_count" ] || [ "$redirect_count" = "0" ]; then
        echo "none:${status_code}"
        return
    fi

    if [ "$effective_host" = "${domain,,}" ]; then
        echo "internal:${redirect_count}:${status_code}"
    else
        echo "external:${redirect_count}:${effective_host}"
    fi
}

score_candidate() {
    local latency="$1"
    local cdn_risk="$2"
    local redirect_risk="$3"
    local hot_risk="$4"
    local x25519_support="$5"
    local h2_support="$6"
    local score=100
    local cdn_class="${cdn_risk%%:*}"
    local redirect_class="${redirect_risk%%:*}"

    case "$cdn_class" in
        high) score=$((score - 35)) ;;
        medium) score=$((score - 20)) ;;
        low) score=$((score - 10)) ;;
    esac

    case "$redirect_class" in
        external) score=$((score - 15)) ;;
        internal) score=$((score - 5)) ;;
        unknown) score=$((score - 5)) ;;
    esac

    if [ "$hot_risk" = "yes" ]; then
        score=$((score - 25))
    fi

    if [ "$x25519_support" != "yes" ]; then
        score=$((score - 25))
    fi

    if [ "$h2_support" != "yes" ]; then
        score=$((score - 15))
    fi

    if is_number "$latency"; then
        if (( $(echo "$latency > 15" | bc -l 2>/dev/null || echo 0) )); then
            score=$((score - 20))
        elif (( $(echo "$latency > 5" | bc -l 2>/dev/null || echo 0) )); then
            score=$((score - 10))
        elif (( $(echo "$latency > 1" | bc -l 2>/dev/null || echo 0) )); then
            score=$((score - 5))
        fi
    else
        score=$((score - 20))
    fi

    [ "$score" -lt 0 ] && score=0
    echo "$score"
}

# ==================== Domain check ====================
check_single_domain() {
    local domain="$1"
    local ip="${2:-}"
    local source="${3:-manual}"
    local tls_info tls_version headers issuer h2_support alpn h2_check latency
    local server_header san_names common_name x25519_support cdn_risk redirect_risk
    local hot_risk score

    if [ -z "$ip" ]; then
        ip=$(dig +short -4 "$domain" 2>/dev/null | grep -P '^\d' | head -1 || true)
        [ -z "$ip" ] && return
    fi

    if is_cf_or_bad "$domain"; then
        echo "BLACKLIST|${domain}|${ip}|${source}" >> "$OUTPUT_DIR/all_filtered.txt"
        return
    fi

    tls_info=$(echo | timeout 5 openssl s_client -connect "${domain}:443" \
        -servername "$domain" -tls1_3 2>/dev/null || true)
    tls_version=$(echo "$tls_info" | grep -oP 'Protocol\s*:\s*\K\S+' | head -1 || true)
    if [ "$tls_version" != "TLSv1.3" ]; then
        echo "NO_TLS13|${domain}|${ip}|${source}" >> "$OUTPUT_DIR/all_filtered.txt"
        return
    fi

    issuer=$(echo "$tls_info" | openssl x509 -noout -issuer 2>/dev/null || true)
    if echo "$issuer" | grep -qiE "self.?sign|localhost|test|fake|invalid|snakeoil"; then
        echo "SELF_SIGNED|${domain}|${ip}|${source}" >> "$OUTPUT_DIR/all_filtered.txt"
        return
    fi

    san_names=$(echo "$tls_info" | openssl x509 -noout -ext subjectAltName 2>/dev/null \
        | grep -oP 'DNS:[^\s,]+' 2>/dev/null | sed 's/DNS://' || true)
    common_name=$(get_cert_common_name "$tls_info")
    if ! cert_matches_domain "$domain" "$san_names" "$common_name"; then
        echo "SNI_MISMATCH|${domain}|${ip}|${source}" >> "$OUTPUT_DIR/all_filtered.txt"
        return
    fi

    x25519_support=$(detect_x25519_support "$domain")
    if $STRICT_MODE && [ "$x25519_support" != "yes" ]; then
        echo "NO_X25519|${domain}|${ip}|${source}" >> "$OUTPUT_DIR/all_filtered.txt"
        return
    fi

    headers=$(curl -4 -sI --max-time 5 --http2 "https://${domain}" 2>/dev/null || true)
    if echo "$headers" | grep -qi "cf-ray\|server: cloudflare\|cf-cache-status"; then
        echo "CLOUDFLARE|${domain}|${ip}|${source}" >> "$OUTPUT_DIR/all_filtered.txt"
        return
    fi

    h2_support="no"
    alpn=$(echo "$tls_info" | grep -oP 'ALPN protocol\s*:\s*\K\S+' | head -1 || true)
    if [ "$alpn" = "h2" ]; then
        h2_support="yes"
    else
        h2_check=$(curl -4 -s --max-time 5 -o /dev/null -w '%{http_version}' "https://${domain}" 2>/dev/null || echo "0")
        [ "$h2_check" = "2" ] && h2_support="yes"
    fi
    if $STRICT_MODE && [ "$h2_support" != "yes" ]; then
        echo "NO_H2|${domain}|${ip}|${source}" >> "$OUTPUT_DIR/all_filtered.txt"
        return
    fi

    latency=$(measure_latency_ms "$domain")
    server_header=$(echo "$headers" | grep -i "^server:" | head -1 | sed 's/[Ss]erver: //' | tr -d '\r' || true)
    cdn_risk=$(detect_cdn_risk "$domain" "$headers" "$server_header")
    if echo "$cdn_risk" | grep -qi '^high:cloudflare'; then
        echo "CLOUDFLARE|${domain}|${ip}|${source}" >> "$OUTPUT_DIR/all_filtered.txt"
        return
    fi

    redirect_risk=$(detect_redirect_risk "$domain")
    if is_hot_domain "$domain"; then
        hot_risk="yes"
    else
        hot_risk="no"
    fi

    score=$(score_candidate "$latency" "$cdn_risk" "$redirect_risk" "$hot_risk" "$x25519_support" "$h2_support")
    echo "${score}|${latency}|${domain}|${ip}|yes|${x25519_support}|${h2_support}|yes|${cdn_risk}|${redirect_risk}|${hot_risk}|${server_header}|${source}" >> "$OUTPUT_DIR/all_candidates.txt"
}

# ==================== Step 0: 收集 VPS 信息 ====================
step0_info() {
    log "========== 第 0 步: 收集本机信息 =========="

    MY_IP=$(curl -4 -s --max-time 5 ip.sb 2>/dev/null \
         || curl -4 -s --max-time 5 ifconfig.me 2>/dev/null \
         || curl -4 -s --max-time 5 icanhazip.com 2>/dev/null \
         || echo "unknown")

    if ! echo "$MY_IP" | grep -qP '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'; then
        err "无法获取有效的 IPv4 地址: $MY_IP"
        exit 1
    fi
    log "本机 IPv4: $MY_IP"

    local ip_info
    ip_info=$(curl -4 -s --max-time 10 "https://ipinfo.io/${MY_IP}" 2>/dev/null || echo "{}")
    MY_ASN=$(echo "$ip_info" | jq -r '.org // "unknown"')
    MY_ASN_NUM=$(echo "$MY_ASN" | grep -oP 'AS\d+' || true)
    MY_CITY=$(echo "$ip_info" | jq -r '.city // "unknown"')
    MY_REGION=$(echo "$ip_info" | jq -r '.region // "unknown"')
    MY_COUNTRY=$(echo "$ip_info" | jq -r '.country // "unknown"')

    log "ASN:   $MY_ASN"
    log "城市:  $MY_CITY"
    log "州省:  $MY_REGION"
    log "国家:  $MY_COUNTRY"

    echo "$MY_IP" > "$OUTPUT_DIR/my_ip.txt"
    echo "$MY_ASN_NUM" > "$OUTPUT_DIR/my_asn.txt"
    echo "$MY_CITY" > "$OUTPUT_DIR/my_city.txt"
    echo "$MY_REGION" > "$OUTPUT_DIR/my_region.txt"
    echo "$MY_COUNTRY" > "$OUTPUT_DIR/my_country.txt"

    ok "地理定位完成: $MY_CITY, $MY_REGION, $MY_COUNTRY"
}

# ==================== Source 1: 同网段扫描 ====================
source1_subnet_scan() {
    if $SKIP_NMAP; then
        warn "已跳过 nmap 子网扫描 (--skip-nmap)"
        > "$OUTPUT_DIR/src1_domains.txt"
        return
    fi

    log "========== 来源 1: 同网段 /$SCAN_RANGE 扫描 =========="

    IFS='.' read -r o1 o2 o3 o4 <<< "$MY_IP"
    local subnet="${o1}.${o2}.${o3}.0/24"
    log "扫描网段: $subnet"

    > "$OUTPUT_DIR/src1_domains.txt"
    local hosts=""
    local hosts_file="$OUTPUT_DIR/src1_hosts.txt"
    > "$hosts_file"

    if command -v nmap &>/dev/null; then
        nmap -sS -p 443 --open --min-rate 500 -T4 "$subnet" -oG "$OUTPUT_DIR/nmap_raw.txt" 2>/dev/null || true
        hosts=$(grep "443/open" "$OUTPUT_DIR/nmap_raw.txt" 2>/dev/null | awk '{print $2}' | grep -v "$MY_IP" || true)
    else
        warn "未检测到 nmap，改用 bash 回退扫描"
        local jobs=0
        for i in $(seq 1 254); do
            local target="${o1}.${o2}.${o3}.${i}"
            [ "$target" = "$MY_IP" ] && continue
            (
                timeout 1 bash -c "echo >/dev/tcp/$target/443" 2>/dev/null \
                    && echo "$target" >> "$hosts_file"
            ) &
            jobs=$((jobs + 1))
            [ $((jobs % 50)) -eq 0 ] && wait
        done
        wait
        hosts=$(sort -u "$hosts_file" 2>/dev/null | grep -v "^${MY_IP}$" || true)
    fi

    local count=0
    for ip in $hosts; do
        local cert_raw
        cert_raw=$(echo | timeout 3 openssl s_client -connect "${ip}:443" 2>/dev/null || true)
        local names
        names=$(echo "$cert_raw" | openssl x509 -noout -ext subjectAltName 2>/dev/null \
            | grep -oP 'DNS:[^\s,]+' 2>/dev/null | sed 's/DNS://' || true)
        local cn
        cn=$(echo "$cert_raw" | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
            | grep commonName 2>/dev/null | sed 's/.*= //' || true)

        for domain in $names $cn; do
            echo "$domain" | grep -qP '^\*|^\d+\.\d+' && continue
            echo "$domain" | grep -qi "host-by\|traefik\|default\|localhost" && continue
            echo "${domain}|${ip}|subnet" >> "$OUTPUT_DIR/src1_domains.txt"
            count=$((count + 1))
        done
    done

    ok "来源 1 完成: 发现 $count 个候选域名"
}

# ==================== Source 2: crt.sh (自动地区) ====================
source2_crtsh() {
    log "========== 来源 2: crt.sh 证书透明度日志 =========="
    log "  基于 VPS 位置: $MY_CITY, $MY_REGION, $MY_COUNTRY"

    > "$OUTPUT_DIR/src2_domains.txt"

    local search_terms=()
    [ "$MY_CITY" != "unknown" ] && search_terms+=("$MY_CITY")
    [ "$MY_REGION" != "unknown" ] && search_terms+=("$MY_REGION")
    if [ "$MY_CITY" != "unknown" ] && [ "$MY_REGION" != "unknown" ]; then
        search_terms+=("${MY_CITY} ${MY_REGION}")
    fi
    [ "$MY_CITY" != "unknown" ] && search_terms+=("${MY_CITY} County")

    if [ ${#search_terms[@]} -eq 0 ]; then
        warn "无法确定 VPS 位置，跳过 crt.sh 地域检索"
        return
    fi

    local count=0
    for term in "${search_terms[@]}"; do
        log "  检索关键词: $term"
        local encoded="${term// /+}"
        local result
        result=$(curl -4 -s --max-time 20 \
            "https://crt.sh/?O=${encoded}&output=json&exclude=expired" 2>/dev/null || echo "[]")

        local domains
        domains=$(echo "$result" | jq -r '.[].common_name // empty' 2>/dev/null \
            | grep -v '^\*' | sort -u | head -150 || true)

        for d in $domains; do
            echo "$d" | grep -qP '\.[a-z]{2,}$' || continue
            echo "${d}||crt.sh:${term}" >> "$OUTPUT_DIR/src2_domains.txt"
            count=$((count + 1))
        done
        sleep 1
    done

    ok "来源 2 完成: 发现 $count 个候选域名"
}

# ==================== Source 3: 同 ASN 邻居 ====================
source3_asn_neighbors() {
    log "========== 来源 3: 同 ASN ($MY_ASN_NUM) 邻居抽样 =========="

    > "$OUTPUT_DIR/src3_domains.txt"

    if [ -z "$MY_ASN_NUM" ]; then
        warn "无法获取 ASN，跳过同 ASN 邻居抽样"
        return
    fi

    local prefixes
    prefixes=$(curl -4 -s --max-time 10 \
        "https://stat.ripe.net/data/announced-prefixes/data.json?resource=${MY_ASN_NUM}" 2>/dev/null \
        | jq -r '.data.prefixes[].prefix' 2>/dev/null \
        | grep -v ':' | head -20 || true)

    if [ -z "$prefixes" ]; then
        warn "未找到可用前缀，跳过同 ASN 邻居抽样"
        return
    fi

    log "  找到 $(echo "$prefixes" | wc -l) 个 IPv4 前缀"

    local count=0
    for prefix in $prefixes; do
        for _ in $(seq 1 10); do
            local sample_ip
            sample_ip=$(sample_ip_from_prefix "$prefix" || true)
            [ -n "$sample_ip" ] || continue
            [ "$sample_ip" = "$MY_IP" ] && continue

            timeout 1 bash -c "echo >/dev/tcp/$sample_ip/443" 2>/dev/null || continue

            local cert_raw
            cert_raw=$(echo | timeout 3 openssl s_client -connect "${sample_ip}:443" 2>/dev/null || true)
            local names
            names=$(echo "$cert_raw" | openssl x509 -noout -ext subjectAltName 2>/dev/null \
                | grep -oP 'DNS:[^\s,]+' 2>/dev/null | sed 's/DNS://' || true)

            for domain in $names; do
                echo "$domain" | grep -qP '^\*|^\d+\.\d+' && continue
                echo "$domain" | grep -qi "host-by\|traefik\|default\|localhost" && continue
                echo "${domain}|${sample_ip}|asn:${MY_ASN_NUM}" >> "$OUTPUT_DIR/src3_domains.txt"
                count=$((count + 1))
            done
        done
    done

    ok "来源 3 完成: 发现 $count 个候选域名"
}

# ==================== Source 4: 动态本地域名发现 ====================
source4_dynamic_local() {
    log "========== 来源 4: 动态本地域名发现 =========="
    log "  城市: $MY_CITY | 州省: $MY_REGION | 国家: $MY_COUNTRY"

    > "$OUTPUT_DIR/src4_domains.txt"
    local count=0

    # ---- 4a: Wikipedia 城市/州页面外部链接 ----
    local wiki_pages=()
    [ "$MY_CITY" != "unknown" ] && wiki_pages+=("${MY_CITY// /_}")
    [ "$MY_REGION" != "unknown" ] && wiki_pages+=("${MY_REGION// /_}")
    # 常见子页面: 城市_metropolitan_area, Economy_of_城市 等
    if [ "$MY_CITY" != "unknown" ]; then
        wiki_pages+=("${MY_CITY// /_},_${MY_REGION// /_}")
    fi

    for page in "${wiki_pages[@]}"; do
        log "  [4a] Wikipedia 外链页: $page"
        local wiki_links
        wiki_links=$(curl -4 -s --max-time 15 \
            "https://en.wikipedia.org/w/api.php?action=parse&page=${page}&prop=externallinks&format=json" 2>/dev/null \
            | jq -r '.parse.externallinks[]? // empty' 2>/dev/null || true)

        for url in $wiki_links; do
            local domain
            domain=$(echo "$url" | grep -oP 'https?://([^/]+)' | sed 's|https\?://||' || true)
            [ -z "$domain" ] && continue
            # 去 www. 前缀后再加回来保证一致性
            domain=$(echo "$domain" | sed 's/^www\.//')
            echo "$domain" | grep -qiE "wikipedia|wikimedia|facebook|twitter|instagram|youtube|google|archive\.org|web\.archive|doi\.org|jstor|census\.gov|bls\.gov" && continue
            # 验证是真实域名格式
            echo "$domain" | grep -qP '\.[a-z]{2,}$' || continue
            echo "www.${domain}||wiki:${page}" >> "$OUTPUT_DIR/src4_domains.txt"
            count=$((count + 1))
        done
        sleep 0.5
    done

    # ---- 4b: crt.sh 行业关键词 + 城市搜索 ----
    if [ "$MY_CITY" != "unknown" ]; then
        log "  [4b] crt.sh 行业关键词搜索"

        local industries=("hospital" "medical" "library" "museum" "school" "church"
            "credit union" "water" "power" "transit" "police" "fire" "chamber")

        for industry in "${industries[@]}"; do
            local search="${MY_CITY}+${industry// /+}"
            log "    crt.sh 检索: ${MY_CITY} + ${industry}"
            local result
            result=$(curl -4 -s --max-time 10 \
                "https://crt.sh/?O=${search}&output=json&exclude=expired" 2>/dev/null || echo "[]")

            local domains
            domains=$(echo "$result" | jq -r '.[].common_name // empty' 2>/dev/null \
                | grep -v '^\*' | sort -u | head -30 || true)

            for d in $domains; do
                echo "$d" | grep -qP '\.[a-z]{2,}$' || continue
                echo "${d}||crt.sh:${MY_CITY}+${industry}" >> "$OUTPUT_DIR/src4_domains.txt"
                count=$((count + 1))
            done
            sleep 0.5
        done
    fi

    # ---- 4c: 通用小众域名 (全球 CDN 节点, 不依赖地区) ----
    log "  [4c] 通用小众域名补充"
    local generic=(
        "www.jenkins.io" "www.grafana.com" "www.hashicorp.com"
        "www.elastic.co" "www.redhat.com" "www.suse.com"
        "docs.python.org" "pkg.go.dev" "crates.io"
        "www.pagerduty.com" "www.datadoghq.com" "www.sentry.io"
        "www.postmarkapp.com" "www.eff.org" "www.mozilla.org"
        "www.apache.org" "www.linuxfoundation.org" "letsencrypt.org"
        "www.internic.net" "www.arin.net" "www.ripe.net"
        "www.apnic.net" "www.lacnic.net"
    )
    for d in "${generic[@]}"; do
        echo "${d}||generic" >> "$OUTPUT_DIR/src4_domains.txt"
        count=$((count + 1))
    done

    ok "来源 4 完成: 发现 $count 个候选域名"
}

# ==================== 合并去重 ====================
merge_domains() {
    log "========== 合并并去重 =========="

    > "$OUTPUT_DIR/all_domains.txt"

    cat "$OUTPUT_DIR"/src*_domains.txt 2>/dev/null \
        | awk -F'|' '{
            domain = tolower($1)
            gsub(/\.$/, "", domain)
            if (domain != "" && !seen[domain]++) {
                print domain"|"$2"|"$3
            }
        }' >> "$OUTPUT_DIR/all_domains.txt"

    local total
    total=$(wc -l < "$OUTPUT_DIR/all_domains.txt")
    ok "去重完成: 共 $total 个唯一域名"
}

# ==================== 批量检测 ====================
batch_check() {
    log "========== 批量检测候选域名 =========="

    > "$OUTPUT_DIR/all_candidates.txt"
    > "$OUTPUT_DIR/all_filtered.txt"

    local total
    total=$(wc -l < "$OUTPUT_DIR/all_domains.txt")
    local count=0 running=0

    while IFS='|' read -r domain ip source; do
        count=$((count + 1))
        printf "\r  检测进度: %d/%d - %-50s" "$count" "$total" "$domain"

        check_single_domain "$domain" "$ip" "$source" &
        running=$((running + 1))
        if [ $running -ge $MAX_CONCURRENT ]; then
            wait
            running=0
        fi
    done < "$OUTPUT_DIR/all_domains.txt"
    wait

    echo ""
    local passed filtered
    passed=$(wc -l < "$OUTPUT_DIR/all_candidates.txt" 2>/dev/null || echo 0)
    filtered=$(wc -l < "$OUTPUT_DIR/all_filtered.txt" 2>/dev/null || echo 0)
    ok "批量检测完成: $passed 个通过, $filtered 个被过滤"
}

# ==================== 报告 ====================
generate_report() {
    log "========== 生成报告 =========="

    local result_file="$OUTPUT_DIR/results_${TIMESTAMP}.txt"
    local csv_file="$OUTPUT_DIR/candidates_${TIMESTAMP}.csv"
    local mode_label="严格"

    if ! $STRICT_MODE; then
        mode_label="宽松"
    fi

    {
        echo 'score,latency_ms,domain,ip,tls13,x25519,h2,sni,cdn_risk,redirect_risk,hot_risk,server,source'
        if [ -s "$OUTPUT_DIR/all_candidates.txt" ]; then
            sort -t'|' -k1,1nr -k2,2n "$OUTPUT_DIR/all_candidates.txt" \
                | while IFS='|' read -r score latency domain ip tls13 x25519 h2 sni cdn_risk redirect_risk hot_risk server source; do
                    server=${server//\"/\"\"}
                    source=${source//\"/\"\"}
                    printf '%s,%s,"%s","%s",%s,%s,%s,%s,"%s","%s",%s,"%s","%s"\n' \
                        "$score" "$latency" "$domain" "$ip" "$tls13" "$x25519" "$h2" "$sni" \
                        "$cdn_risk" "$redirect_risk" "$hot_risk" "$server" "$source"
                done
        fi
    } > "$csv_file"

    if $CSV_ONLY; then
        ok "已生成 CSV: $csv_file"
        return
    fi

    {
        echo "============================================================"
        echo "REALITY 回落域名候选报告"
        echo "============================================================"
        echo ""
        echo "扫描时间 : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "工作模式 : $mode_label"
        echo "本机 IPv4: $MY_IP"
        echo "ASN      : $MY_ASN"
        echo "地理位置 : $MY_CITY, $MY_REGION, $MY_COUNTRY"
        echo ""
        echo "来源统计"
        echo "  子网扫描 : $(wc -l < "$OUTPUT_DIR/src1_domains.txt" 2>/dev/null || echo 0)"
        echo "  crt.sh   : $(wc -l < "$OUTPUT_DIR/src2_domains.txt" 2>/dev/null || echo 0)"
        echo "  ASN 抽样 : $(wc -l < "$OUTPUT_DIR/src3_domains.txt" 2>/dev/null || echo 0)"
        echo "  动态发现 : $(wc -l < "$OUTPUT_DIR/src4_domains.txt" 2>/dev/null || echo 0)"
        echo ""
        echo "过滤统计"
        if [ -f "$OUTPUT_DIR/all_filtered.txt" ]; then
            echo "  黑名单      : $(grep -c 'BLACKLIST' "$OUTPUT_DIR/all_filtered.txt" 2>/dev/null || echo 0)"
            echo "  Cloudflare  : $(grep -c 'CLOUDFLARE' "$OUTPUT_DIR/all_filtered.txt" 2>/dev/null || echo 0)"
            echo "  无 TLS 1.3  : $(grep -c 'NO_TLS13' "$OUTPUT_DIR/all_filtered.txt" 2>/dev/null || echo 0)"
            echo "  无 X25519   : $(grep -c 'NO_X25519' "$OUTPUT_DIR/all_filtered.txt" 2>/dev/null || echo 0)"
            echo "  无 HTTP/2   : $(grep -c 'NO_H2' "$OUTPUT_DIR/all_filtered.txt" 2>/dev/null || echo 0)"
            echo "  SNI 不匹配  : $(grep -c 'SNI_MISMATCH' "$OUTPUT_DIR/all_filtered.txt" 2>/dev/null || echo 0)"
            echo "  自签证书    : $(grep -c 'SELF_SIGNED' "$OUTPUT_DIR/all_filtered.txt" 2>/dev/null || echo 0)"
        fi
        echo ""

        if [ ! -s "$OUTPUT_DIR/all_candidates.txt" ]; then
            echo "没有候选域名通过当前模式的筛选条件。"
        else
            printf "%-5s %-8s %-42s %-10s %-12s %s\n" "评分" "延迟" "域名" "CDN" "跳转" "来源"
            printf "%-5s %-8s %-42s %-10s %-12s %s\n" "-----" "-------" "------------------------------------------" "----------" "------------" "------"
            sort -t'|' -k1,1nr -k2,2n "$OUTPUT_DIR/all_candidates.txt" \
                | while IFS='|' read -r score latency domain ip tls13 x25519 h2 sni cdn_risk redirect_risk hot_risk server source; do
                    printf "%-5s %-8s %-42s %-10s %-12s %s\n" \
                        "$score" "${latency}ms" "$domain" "${cdn_risk%%:*}" "${redirect_risk%%:*}" "$source"
                done
        fi

        echo ""
        echo "深度检测 : ./reality_dest_finder.sh --check <域名>"
        echo "CSV 文件 : $csv_file"
        echo "============================================================"
    } | tee "$result_file"

    echo ""
    ok "文本报告: $result_file"
    ok "CSV 结果: $csv_file"
}

# ==================== 深度检测 ====================
deep_check() {
    local domain="$1"
    local resolved_ip tls_out http_headers tls_ver san_names common_name x25519_support
    local h2_ver cdn_risk redirect_risk hot_risk latency score issuer

    log "========== 深度检测: $domain =========="

    echo ""
    log "[DNS]"
    echo "  IPv4: $(dig +short -4 "$domain" 2>/dev/null | head -3 | tr '\n' ' ' || true)"
    echo "  IPv6: $(dig +short AAAA "$domain" 2>/dev/null | head -3 | tr '\n' ' ' || true)"

    resolved_ip=$(dig +short -4 "$domain" 2>/dev/null | grep -P '^\d' | head -1 || true)
    tls_out=$(echo | timeout 5 openssl s_client -connect "${domain}:443" \
        -servername "$domain" -tls1_3 2>/dev/null || true)
    http_headers=$(curl -4 -sI --max-time 5 --http2 "https://${domain}" 2>/dev/null || true)
    tls_ver=$(echo "$tls_out" | grep -oP 'Protocol\s*:\s*\K\S+' | head -1 || true)
    san_names=$(echo "$tls_out" | openssl x509 -noout -ext subjectAltName 2>/dev/null \
        | grep -oP 'DNS:[^\s,]+' 2>/dev/null | sed 's/DNS://' || true)
    common_name=$(get_cert_common_name "$tls_out")
    x25519_support=$(detect_x25519_support "$domain")
    h2_ver=$(curl -4 -s --max-time 5 -o /dev/null -w '%{http_version}' "https://${domain}" 2>/dev/null || echo "0")
    issuer=$(echo "$tls_out" | openssl x509 -noout -issuer 2>/dev/null || true)
    cdn_risk=$(detect_cdn_risk "$domain" "$http_headers" "$(echo "$http_headers" | grep -i '^server:' | head -1 | sed 's/[Ss]erver: //' | tr -d '\r' || true)")
    redirect_risk=$(detect_redirect_risk "$domain")
    latency=$(measure_latency_ms "$domain")
    if is_hot_domain "$domain"; then
        hot_risk="yes"
    else
        hot_risk="no"
    fi
    score=$(score_candidate "$latency" "$cdn_risk" "$redirect_risk" "$hot_risk")

    echo ""
    log "[TLS]"
    echo "$tls_out" | grep -E "Protocol|Cipher|Server Temp Key|Server public key|Peer signing" || echo "  握手失败"

    echo ""
    log "[证书]"
    echo "$tls_out" | openssl x509 -noout -issuer -subject -dates -ext subjectAltName 2>/dev/null || echo "  证书解析失败"

    echo ""
    log "[HTTP 头]"
    echo "$http_headers" | head -15

    echo ""
    log "[IP 归属]"
    if [ -n "$resolved_ip" ]; then
        curl -4 -s --max-time 5 "https://ipinfo.io/${resolved_ip}" 2>/dev/null \
            | jq -r '"  IP:   \(.ip // "N/A")\n  ASN:  \(.org // "N/A")\n  位置: \(.city // "N/A"), \(.region // "N/A"), \(.country // "N/A")"' \
            || echo "  查询失败"
    else
        echo "  没有解析到 IPv4"
    fi

    echo ""
    log "[摘要]"
    echo "  TLS 1.3      : ${tls_ver:-no}"
    echo "  X25519       : $x25519_support"
    if [ "$h2_ver" = "2" ]; then
        echo "  HTTP/2       : yes"
    else
        echo "  HTTP/2       : no"
    fi
    if cert_matches_domain "$domain" "$san_names" "$common_name"; then
        echo "  SNI 匹配     : yes"
    else
        echo "  SNI 匹配     : no"
    fi
    if echo "$issuer" | grep -qiE "self.?sign|localhost|test|fake|invalid|snakeoil"; then
        echo "  自签证书     : yes"
    else
        echo "  自签证书     : no"
    fi
    echo "  CDN 风险     : $cdn_risk"
    echo "  跳转风险     : $redirect_risk"
    echo "  热门域名     : $hot_risk"
    echo "  延迟         : ${latency}ms"
    echo "  评分         : $score/100"

    echo ""
    if [ "$tls_ver" != "TLSv1.3" ] || [ "$x25519_support" != "yes" ] || [ "$h2_ver" != "2" ]; then
        if $STRICT_MODE; then
            err "严格模式硬条件未满足"
        else
            warn "宽松模式下可保留，但硬条件不完整"
        fi
    elif [ "$score" -ge 85 ]; then
        ok "强候选"
    elif [ "$score" -ge 70 ]; then
        ok "可用候选"
    else
        warn "可用，但建议人工复核"
    fi
}

# ==================== main ====================
main() {
    if [ "$ORIGINAL_ARG_COUNT" -eq 0 ] && [ -t 0 ]; then
        interactive_config
    fi

    if [ -n "$CHECK_DOMAIN" ]; then
        LAST_ACTION="3"
    elif $STRICT_MODE; then
        LAST_ACTION="1"
    else
        LAST_ACTION="2"
    fi
    save_last_config

    show_banner

    if [ -n "$CHECK_DOMAIN" ]; then
        deep_check "$CHECK_DOMAIN"
        exit 0
    fi

    step0_info
    echo ""
    source1_subnet_scan
    echo ""
    source2_crtsh
    echo ""
    source3_asn_neighbors
    echo ""
    source4_dynamic_local
    echo ""
    merge_domains
    echo ""
    batch_check
    echo ""
    generate_report
    echo ""
    log "完成。可继续使用 ./reality_dest_finder.sh --check <域名> 做单域名深查"
}

main "$@"
