setup_colors() {
    C_RESET='' C_BOLD='' C_DIM='' C_GREEN='' C_YELLOW='' C_RED='' C_CYAN='' C_PANEL=''
    if [[ "${SCHEDULED_RUN:-0}" != 1 && -t 1 && -z "${NO_COLOR+x}" && "${TERM:-dumb}" != dumb ]]; then
        C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[90m'
        C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_RED=$'\033[31m' C_CYAN=$'\033[36m'
        C_PANEL="$C_DIM"
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
    local name="$1" status="${2:-}" color="${3:-$C_DIM}" width gap
    width="$(po0_terminal_width)"; width=$((width-4)); (( width <= 72 )) || width=72
    gap=$((width - $(po0_cell_width "$name") - $(po0_cell_width "$status")))
    if [[ -n "$status" ]] && (( gap >= 3 )); then
        printf '  %b%s%*s%b%b%s%b\n' "$C_CYAN" "$name" "$gap" '' "$C_RESET" "$color" "$status" "$C_RESET"
    else
        printf '  %b%s%b\n' "$C_CYAN" "$name" "$C_RESET"
        [[ -z "$status" ]] || printf '  %b%s%b\n' "$color" "$status" "$C_RESET"
    fi
    return 0
}
print_title() {
    printf '\n'; po0_heading "$1" "${2:-}"; print_panel_divider
}
print_menu_item() {
    local color="$C_CYAN"
    [[ "$1" != 0 ]] || color="$C_DIM"
    printf '    %b[%s]%b  %s\n' "$color" "$1" "$C_RESET" "$2"
}
print_panel_section() { printf '\n  %b%s%b\n' "$C_DIM" "$1" "$C_RESET"; }
print_panel_value_column() { printf '  '; }
print_panel_row() {
    local label="$1" size; shift
    size=$(($(po0_cell_width "$label") + 2)); (( size >= 12 )) || size=12
    printf '  %b%s%b%s\n' "$C_DIM" "$(po0_pad_cell "$label" "$size")" "$C_RESET" "$*"
}
print_panel_note() { printf '  %b%s%b\n' "$C_DIM" "$*" "$C_RESET"; }
po0_duration() {
    local seconds="$1" result=''
    if (( seconds >= 3600 )); then result="$((seconds/3600)) 小时 "; seconds=$((seconds%3600)); fi
    if (( seconds >= 60 )); then result="$result$((seconds/60)) 分钟 "; seconds=$((seconds%60)); fi
    if (( seconds > 0 )) || [[ -z "$result" ]]; then result="$result$seconds 秒 "; fi
    printf '%s' "${result% }"
}
