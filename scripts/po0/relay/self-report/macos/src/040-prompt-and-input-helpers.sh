read_prompt() {
    local prompt="$1"
    local value
    if [[ -r /dev/tty && -w /dev/tty ]]; then
        if { printf '%s' "${prompt}" > /dev/tty && IFS= read -r value < /dev/tty; } 2>/dev/null; then
            printf '%s\n' "${value}"
            return 0
        fi
    fi
    printf '%s' "${prompt}" >&2
    IFS= read -r value || return 1
    printf '%s\n' "${value}"
}

prompt_default() {
    local prompt="$1"
    local default="$2"
    local value
    if [[ -n "${default}" ]]; then
        value="$(read_prompt "${prompt} [${default}]: ")" || value=""
        value="$(trim "${value}")"
        [[ -n "${value}" ]] || value="${default}"
    else
        value="$(read_prompt "${prompt}: ")" || value=""
        value="$(trim "${value}")"
    fi
    printf '%s\n' "${value}"
}

to_lower() {
    local value="$1" out="" ch i
    for ((i = 0; i < ${#value}; i++)); do
        ch="${value:i:1}"
        case "${ch}" in
            A) out="${out}a" ;;
            B) out="${out}b" ;;
            C) out="${out}c" ;;
            D) out="${out}d" ;;
            E) out="${out}e" ;;
            F) out="${out}f" ;;
            G) out="${out}g" ;;
            H) out="${out}h" ;;
            I) out="${out}i" ;;
            J) out="${out}j" ;;
            K) out="${out}k" ;;
            L) out="${out}l" ;;
            M) out="${out}m" ;;
            N) out="${out}n" ;;
            O) out="${out}o" ;;
            P) out="${out}p" ;;
            Q) out="${out}q" ;;
            R) out="${out}r" ;;
            S) out="${out}s" ;;
            T) out="${out}t" ;;
            U) out="${out}u" ;;
            V) out="${out}v" ;;
            W) out="${out}w" ;;
            X) out="${out}x" ;;
            Y) out="${out}y" ;;
            Z) out="${out}z" ;;
            *) out="${out}${ch}" ;;
        esac
    done
    printf '%s\n' "${out}"
}

digits_only() {
    local value="$1" out="" ch i
    for ((i = 0; i < ${#value}; i++)); do
        ch="${value:i:1}"
        case "${ch}" in
            [0-9]) out="${out}${ch}" ;;
        esac
    done
    printf '%s\n' "${out}"
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local suffix value
    case "$(to_lower "${default}")" in
        y|yes|1|true) suffix="Y/n"; default="y" ;;
        *) suffix="y/N"; default="n" ;;
    esac
    while true; do
        value="$(read_prompt "${prompt} [${suffix}]: ")" || return 1
        value="$(trim "${value}")"
        [[ -n "${value}" ]] || value="${default}"
        case "$(to_lower "${value}")" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) printf '请输入 y 或 n。\n' >&2 ;;
        esac
    done
}
