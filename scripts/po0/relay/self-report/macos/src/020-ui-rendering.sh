# Palette must stay readable on dark and light themes: hierarchy comes from bold and
# spacing, never from grey text. Bright black (90) vanishes on Solarized Dark and similar
# schemes, so it is not used. Faint (C_DIM) is limited to dividers and empty slots;
# terminals without faint support render it as normal text.
po0_color_enabled() {
    [[ "${SCHEDULED_RUN:-0}" != 1 && -t 1 && -z "${NO_COLOR+x}" && "${TERM:-dumb}" != dumb ]]
}
setup_colors() {
    C_RESET='' C_BOLD='' C_DIM='' C_GREEN='' C_YELLOW='' C_RED='' C_CYAN='' C_PANEL=''
    C_TITLE='' C_SECTION='' C_KEY=''
    if po0_color_enabled; then
        C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m'
        C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_RED=$'\033[31m' C_CYAN=$'\033[36m'
        C_TITLE=$'\033[1m' C_SECTION=$'\033[1m' C_KEY=$'\033[36m'
        # Titles stay default-colored bold: bold cyan turns bright cyan on white themes that
        # brighten bold text. Labels, notes and version text use the default foreground.
    fi
}
setup_colors

# Count UTF-8 terminal cells without relying on the host locale or wc -L.
# The existing awk dependency also works on macOS and BusyBox.
po0_cell_width() {
    printf '%s' "$1" | LC_ALL=C awk '
    BEGIN { for (i=1;i<256;i++) ord[sprintf("%c",i)]=i }
    {
        for (i=1;i<=length($0);i++) {
            c=ord[substr($0,i,1)]; n=0
            if(c>=240){ c-=240;n=3 } else if(c>=224){ c-=224;n=2 } else if(c>=192){ c-=192;n=1 }
            while(n-- > 0 && i<length($0)) c=c*64+ord[substr($0,++i,1)]-128
            if((c>=768&&c<=879)||(c>=8203&&c<=8207)||(c>=65024&&c<=65039)) continue
            w+=((c>=4352&&c<=4447)||(c>=11904&&c<=42191)||(c>=44032&&c<=55203)||(c>=63744&&c<=64255)||(c>=65040&&c<=65135)||(c>=65281&&c<=65376)||(c>=65504&&c<=65510)||c>=127744)?2:1
        }
    } END { print w+0 }'
}
po0_pad_cell() {
    local text="$1" size="$2" length
    length="$(po0_cell_width "$text")"
    (( size > length )) || size="$length"
    printf '%s%*s' "$text" "$((size - length))" ''
}
po0_terminal_width() {
    local width="${COLUMNS:-}"
    [[ "$width" =~ ^[1-9][0-9]*$ ]] || width="$(tput cols 2>/dev/null || true)"
    [[ "$width" =~ ^[1-9][0-9]*$ ]] || width=80
    printf '%s' "$width"
}
print_panel_divider() {
    local width line='-' n=0
    width="$(po0_terminal_width)"; width=$((width-4))
    (( width <= 72 )) || width=72; (( width >= 12 )) || width=12
    if [[ -t 1 && "${TERM:-dumb}" != dumb ]]; then
        case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *UTF-8*|*utf8*|*utf-8*) line='─' ;; esac
    fi
    printf '  %b' "$C_DIM"
    while (( n < width )); do printf '%s' "$line"; n=$((n+1)); done
    printf '%b\n' "$C_RESET"
}
print_menu_divider() { print_panel_divider; }
print_menu_footer() { printf '\n'; }
po0_heading() {
    local name="$1" status="${2:-}" color="${3:-}" width gap end=''
    width="$(po0_terminal_width)"; width=$((width-4)); (( width <= 72 )) || width=72
    gap=$((width - $(po0_cell_width "$name") - $(po0_cell_width "$status")))
    [[ -z "$color" ]] || end="$C_RESET"
    if [[ -n "$status" ]] && (( gap >= 3 )); then
        printf '  %b%s%b%*s%b%s%b\n' "$C_TITLE" "$name" "$C_RESET" "$gap" '' "$color" "$status" "$end"
    else
        printf '  %b%s%b\n' "$C_TITLE" "$name" "$C_RESET"
        [[ -z "$status" ]] || printf '  %b%s%b\n' "$color" "$status" "$end"
    fi
    return 0
}
print_title() {
    printf '\n'; po0_heading "$1" "${2:-}"; print_panel_divider
}
print_menu_item() {
    if [[ "$1" == 0 ]]; then printf '    [%s]  %s\n' "$1" "$2"
    else printf '    %b[%s]%b  %s\n' "$C_KEY" "$1" "$C_RESET" "$2"; fi
}
print_panel_section() { printf '\n  %b%s%b\n' "$C_SECTION" "$1" "$C_RESET"; }
print_panel_value_column() { printf '  '; }
po0_panel_label() {
    local size
    size=$(($(po0_cell_width "$1") + 2)); (( size >= 12 )) || size=12
    po0_pad_cell "$1" "$size"
}
print_panel_row() {
    local label="$1"; shift
    printf '  %s%s\n' "$(po0_panel_label "$label")" "$*"
}
# Keyword tone for status values; priority error > warn > ok > plain.
po0_status_tone() {
    case "$1" in
        *异常*|*失败*|*无法*|*错误*|*无效*) printf 'error' ;;
        *已停用*|*已暂停*|*未安装*|*未配置*|*暂不使用*|*已关闭*|*待迁移*|*不一致*|*等待*|*未放行*|*暂无*|*状态未知*) printf 'warn' ;;
        *已启用*|*运行中*|*已配置*|*已放行*|*就绪*|*已安装*) printf 'ok' ;;
        *) printf 'plain' ;;
    esac
}
# print_panel_status_row LABEL VALUE [ok|warn|error|plain]: print_panel_row layout with a
# semantic value color. Without a valid TONE the value keywords decide.
print_panel_status_row() {
    local label="$1" value="${2:-}" tone="${3:-}" color=''
    case "$tone" in ok|warn|error|plain) ;; *) tone="$(po0_status_tone "$value")" ;; esac
    case "$tone" in ok) color="$C_GREEN" ;; warn) color="$C_YELLOW" ;; error) color="$C_RED" ;; esac
    if [[ -n "$color" ]]; then
        printf '  %s%b%s%b\n' "$(po0_panel_label "$label")" "$color" "$value" "$C_RESET"
    else
        printf '  %s%s\n' "$(po0_panel_label "$label")" "$value"
    fi
}
print_panel_note() { printf '  %s\n' "$*"; }
po0_duration() {
    local seconds="$1" result=''
    if (( seconds >= 3600 )); then result="$((seconds/3600)) 小时 "; seconds=$((seconds%3600)); fi
    if (( seconds >= 60 )); then result="$result$((seconds/60)) 分钟 "; seconds=$((seconds%60)); fi
    if (( seconds > 0 )) || [[ -z "$result" ]]; then result="$result$seconds 秒 "; fi
    printf '%s' "${result% }"
}
