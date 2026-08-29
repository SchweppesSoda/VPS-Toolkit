#!/usr/bin/env bash
set -uo pipefail

# 3x-ui node exporter.
# Reads the local 3x-ui SQLite database and exports subscription/node links.

SCRIPT_VERSION="1.1.0"
RAW_URL="https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/3x-ui/3x-ui-node-exporter.sh"

ADDR=""
DB_OVERRIDE=""
OUT_OVERRIDE=""
RAW_ONLY="0"
YES="0"
SHOW_LINKS="0"
NO_COLOR="0"
CLI_MODE="0"
SELF_DESTRUCT="0"
OUT_OPTION_SET="0"
SELF_DESTRUCT_TIMEOUT_SECONDS="900"
SELF_DESTRUCT_TEMP_ROOT=""
SELF_DESTRUCT_SESSION_DIR=""
SELF_DESTRUCT_ARCHIVE=""
SCRIPT_SOURCE_DELETED="0"

C_RESET=""
C_BOLD=""
C_DIM=""
C_GREEN=""
C_YELLOW=""
C_RED=""
C_CYAN=""
C_PANEL=""

setup_colors() {
  if [[ "${NO_COLOR}" == "0" && -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_CYAN=$'\033[96m'
    C_PANEL=$'\033[38;5;208m'
  fi
}

info() { printf '%b[信息]%b %s\n' "${C_GREEN}" "${C_RESET}" "$1"; }
warn() { printf '%b[警告]%b %s\n' "${C_YELLOW}" "${C_RESET}" "$1"; }
err() { printf '%b[错误]%b %s\n' "${C_RED}" "${C_RESET}" "$1" >&2; }
success() { printf '%b[完成]%b %s\n' "${C_GREEN}" "${C_RESET}" "$1"; }

print_divider() {
  printf '%s\n' "------------------------------------------------------------"
}

print_title() {
  echo ""
  print_divider
  printf '%b%s%b\n' "${C_BOLD}${C_CYAN}" "$1" "${C_RESET}"
  print_divider
}

print_menu_divider() {
  printf '%b%s%b\n' "${C_CYAN}" "------------------------" "${C_RESET}"
}

print_menu_section() {
  print_menu_divider
  printf '%b%s%b\n' "${C_BOLD}${C_CYAN}" "$1" "${C_RESET}"
}

print_menu_item() {
  local number="$1"
  local label="$2"
  printf '  %b%2s%b) %s\n' "${C_CYAN}" "${number}" "${C_RESET}" "${label}"
}

print_menu_footer() {
  print_menu_divider
}

has_tty() {
  [[ -r /dev/tty ]]
}

menu_clear_screen() {
  [[ "${MENU_CLEAR:-1}" == "0" ]] && return 0
  [[ -t 1 && -n "${TERM:-}" && "${TERM}" != "dumb" ]] || return 0
  command -v clear >/dev/null 2>&1 && clear || printf '\033[H\033[2J'
}

read_tty() {
  local prompt="$1"
  local value=""

  if has_tty; then
    read -r -p "${prompt}" value </dev/tty
  else
    read -r -p "${prompt}" value
  fi

  printf '%s\n' "${value}"
}

read_tty_timeout() {
  local prompt="$1"
  local timeout_seconds="$2"
  local input_path="${3:-/dev/tty}"
  local value=""

  if ! read -r -t "${timeout_seconds}" -p "${prompt}" value <"${input_path}"; then
    return 1
  fi

  printf '%s\n' "${value}"
}

confirm_yes() {
  local prompt="$1"
  local default_answer="${2:-n}"
  local suffix="[y/N]"
  local value

  if [[ "${YES}" == "1" ]]; then
    return 0
  fi

  if ! has_tty; then
    return 1
  fi

  [[ "${default_answer}" =~ ^[Yy]$ ]] && suffix="[Y/n]"

  while true; do
    value="$(read_tty "${prompt} ${suffix}: ")"
    value="${value:-${default_answer}}"
    case "${value}" in
      y|Y|yes|YES|Yes) return 0 ;;
      n|N|no|NO|No) return 1 ;;
      *) warn "请输入 y 或 n。" ;;
    esac
  done
}

pause_before_return() {
  if has_tty; then
    echo ""
    read_tty "按回车返回菜单..." >/dev/null
  fi
}

print_usage() {
  cat <<EOF
3x-ui 节点导出工具 ${SCRIPT_VERSION}

用法:
  bash 3x-ui-node-exporter.sh [选项]
  bash <(curl -fsSL ${RAW_URL})

选项:
  --addr HOST        指定节点对外域名或公网 IP，用于订阅 Host 头
  --db PATH          指定 3x-ui SQLite 数据库路径
  --out DIR          指定导出目录
  --raw-only         只导出原始 inbound 配置，不抓取订阅链接
  --self-destruct    临时导出 ZIP，等待下载后自动清理本次产物
  --yes, -y          非交互确认：自动安装缺失依赖并直接导出
  --show-links       导出后预览 links.txt 前 20 行
  --no-color         关闭彩色输出
  --version          显示版本
  --help, -h         显示帮助

说明:
  默认不会把完整节点链接打印到屏幕。导出的敏感文件权限会设置为 600。
  自销毁模式需要交互式终端，不能与 --out、--show-links 或 --yes 同时使用。
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --addr)
        shift || true
        [[ $# -gt 0 ]] || { err "--addr 需要一个值。"; exit 2; }
        ADDR="$1"
        CLI_MODE="1"
        ;;
      --addr=*)
        ADDR="${1#*=}"
        CLI_MODE="1"
        ;;
      --db)
        shift || true
        [[ $# -gt 0 ]] || { err "--db 需要一个路径。"; exit 2; }
        DB_OVERRIDE="$1"
        CLI_MODE="1"
        ;;
      --db=*)
        DB_OVERRIDE="${1#*=}"
        CLI_MODE="1"
        ;;
      --out)
        shift || true
        [[ $# -gt 0 ]] || { err "--out 需要一个目录。"; exit 2; }
        OUT_OVERRIDE="$1"
        OUT_OPTION_SET="1"
        CLI_MODE="1"
        ;;
      --out=*)
        OUT_OVERRIDE="${1#*=}"
        OUT_OPTION_SET="1"
        CLI_MODE="1"
        ;;
      --raw-only)
        RAW_ONLY="1"
        CLI_MODE="1"
        ;;
      --yes|-y)
        YES="1"
        CLI_MODE="1"
        ;;
      --show-links)
        SHOW_LINKS="1"
        CLI_MODE="1"
        ;;
      --self-destruct)
        SELF_DESTRUCT="1"
        CLI_MODE="1"
        ;;
      --no-color)
        NO_COLOR="1"
        ;;
      --version)
        printf '%s\n' "${SCRIPT_VERSION}"
        exit 0
        ;;
      --help|-h)
        print_usage
        exit 0
        ;;
      *)
        err "未知选项：$1"
        print_usage
        exit 2
        ;;
    esac
    shift || true
  done
}

validate_args() {
  if [[ ! "${SELF_DESTRUCT_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] ||
    ((SELF_DESTRUCT_TIMEOUT_SECONDS < 1)); then
    err "内部自销毁等待时间必须是正整数秒。"
    exit 2
  fi

  [[ "${SELF_DESTRUCT}" == "1" ]] || return 0

  if [[ "${OUT_OPTION_SET}" == "1" ]]; then
    err "--self-destruct 不能与 --out 同时使用。"
    exit 2
  fi
  if [[ "${SHOW_LINKS}" == "1" ]]; then
    err "--self-destruct 不能与 --show-links 同时使用，以免节点链接留在终端回滚中。"
    exit 2
  fi
  if [[ "${YES}" == "1" ]]; then
    err "--self-destruct 不能与 --yes 同时使用；下载窗口需要人工确认。"
    exit 2
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

script_source_path() {
  local src="${BASH_SOURCE[0]:-}"

  [[ -n "${src}" ]] || return 1

  if [[ "${src}" != */* ]]; then
    src="$(command -v "${src}" 2>/dev/null || printf '%s' "${src}")"
  fi

  if [[ "${src}" != /* ]]; then
    src="$(pwd)/${src}"
  fi

  printf '%s\n' "${src}"
}

ensure_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    return 0
  fi

  if ! command_exists sudo; then
    err "当前不是 root，且系统没有 sudo。请切换到 root 后再运行。"
    echo "推荐命令：bash <(curl -fsSL ${RAW_URL})"
    exit 1
  fi

  info "当前不是 root，正在尝试使用 sudo 重新运行。"

  local src
  src="$(script_source_path || true)"
  if [[ -n "${src}" && -r "${src}" && "${src}" != /dev/fd/* && "${src}" != /proc/self/fd/* ]]; then
    exec sudo --preserve-env=TERM,COLORTERM,NO_COLOR bash "${src}" "$@"
  fi

  if command_exists curl; then
    exec sudo --preserve-env=TERM,COLORTERM,NO_COLOR bash -c \
      'curl -fsSL "$1" | bash -s -- "${@:2}"' \
      _ "${RAW_URL}" "$@"
  fi

  if command_exists wget; then
    exec sudo --preserve-env=TERM,COLORTERM,NO_COLOR bash -c \
      'wget -qO- "$1" | bash -s -- "${@:2}"' \
      _ "${RAW_URL}" "$@"
  fi

  err "无法读取当前脚本，也没有 curl/wget 重新下载。请使用 root 直接执行 raw 链接。"
  exit 1
}

detect_pkg_manager() {
  if command_exists apt-get; then
    printf 'apt\n'
  elif command_exists dnf; then
    printf 'dnf\n'
  elif command_exists yum; then
    printf 'yum\n'
  elif command_exists apk; then
    printf 'apk\n'
  elif command_exists pacman; then
    printf 'pacman\n'
  else
    printf 'unknown\n'
  fi
}

package_for_command() {
  local pm="$1"
  local cmd="$2"

  case "${cmd}" in
    python3) printf 'python3\n' ;;
    curl) printf 'curl\n' ;;
    awk)
      case "${pm}" in
        apk|pacman) printf 'gawk\n' ;;
        *) printf 'gawk\n' ;;
      esac
      ;;
    grep) printf 'grep\n' ;;
    find) printf 'findutils\n' ;;
    base64|cat|chmod|date|head|mkdir|mktemp|mv|rm|sort|wc)
      case "${pm}" in
        apk) printf 'coreutils\n' ;;
        pacman) printf 'coreutils\n' ;;
        *) printf 'coreutils\n' ;;
      esac
      ;;
    *) printf '%s\n' "${cmd}" ;;
  esac
}

dedupe_words() {
  local item
  local seen=" "
  for item in "$@"; do
    [[ -n "${item}" ]] || continue
    if [[ "${seen}" != *" ${item} "* ]]; then
      printf '%s\n' "${item}"
      seen="${seen}${item} "
    fi
  done
}

packages_for_missing_commands() {
  local pm="$1"
  shift

  local packages=()
  local cmd
  for cmd in "$@"; do
    packages+=("$(package_for_command "${pm}" "${cmd}")")
  done

  dedupe_words "${packages[@]}"
}

manual_install_command() {
  local pm="$1"
  shift
  local packages=("$@")

  case "${pm}" in
    apt) printf 'apt-get update && apt-get install -y %s\n' "${packages[*]}" ;;
    dnf) printf 'dnf install -y %s\n' "${packages[*]}" ;;
    yum) printf 'yum install -y %s\n' "${packages[*]}" ;;
    apk) printf 'apk add --no-cache %s\n' "${packages[*]}" ;;
    pacman) printf 'pacman -Sy --noconfirm %s\n' "${packages[*]}" ;;
    *) printf '请手动安装：%s\n' "${packages[*]}" ;;
  esac
}

install_packages() {
  local pm="$1"
  shift
  local packages=("$@")

  case "${pm}" in
    apt)
      apt-get update
      apt-get install -y "${packages[@]}"
      ;;
    dnf)
      dnf install -y "${packages[@]}"
      ;;
    yum)
      yum install -y "${packages[@]}"
      ;;
    apk)
      apk add --no-cache "${packages[@]}"
      ;;
    pacman)
      pacman -Sy --noconfirm "${packages[@]}"
      ;;
    *)
      return 1
      ;;
  esac
}

missing_commands() {
  local required=(python3 curl base64 awk mktemp chmod date find head sort grep cat mkdir mv rm wc)
  local cmd
  for cmd in "${required[@]}"; do
    command_exists "${cmd}" || printf '%s\n' "${cmd}"
  done
}

ensure_dependencies() {
  local missing=()
  mapfile -t missing < <(missing_commands)

  if [[ "${#missing[@]}" -eq 0 ]]; then
    return 0
  fi

  print_title "依赖检查"
  warn "检测到缺少依赖命令：${missing[*]}"

  local pm
  pm="$(detect_pkg_manager)"

  local packages=()
  mapfile -t packages < <(packages_for_missing_commands "${pm}" "${missing[@]}")

  if [[ "${pm}" == "unknown" ]]; then
    err "无法识别包管理器，请手动安装后重试：${packages[*]}"
    exit 1
  fi

  echo "建议安装命令："
  manual_install_command "${pm}" "${packages[@]}"
  echo ""

  if confirm_yes "是否现在安装缺失依赖" "y"; then
    install_packages "${pm}" "${packages[@]}" || {
      err "依赖安装失败，请手动安装后重试。"
      exit 1
    }
  else
    err "缺少依赖，已停止。"
    exit 1
  fi

  mapfile -t missing < <(missing_commands)
  if [[ "${#missing[@]}" -gt 0 ]]; then
    err "安装后仍缺少命令：${missing[*]}"
    exit 1
  fi

  success "依赖检查通过。"
}

trim_outer_quotes() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s' "${value}"
}

read_xui_db_folder() {
  local value=""

  [[ -r /etc/default/x-ui ]] || return 1

  value="$(
    awk -F= '
      /^[[:space:]]*(export[[:space:]]+)?XUI_DB_FOLDER[[:space:]]*=/ {
        v=$0
        sub(/^[^=]*=/, "", v)
      }
      END { print v }
    ' /etc/default/x-ui 2>/dev/null
  )"

  value="$(trim_outer_quotes "${value}")"
  [[ -n "${value}" ]] || return 1
  printf '%s\n' "${value}"
}

locate_db() {
  if [[ -n "${DB_OVERRIDE}" ]]; then
    if [[ -f "${DB_OVERRIDE}" ]]; then
      printf '%s\n' "${DB_OVERRIDE}"
      return 0
    fi
    err "指定数据库不存在：${DB_OVERRIDE}"
    return 1
  fi

  local folder=""
  local candidate=""

  folder="$(read_xui_db_folder || true)"
  candidate="${folder:-/etc/x-ui}/x-ui.db"
  if [[ -f "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  candidate="$(
    find /etc /usr/local /opt /root /home /var/lib/docker/volumes \
      -type f -name 'x-ui.db' 2>/dev/null | head -n 1
  )"

  if [[ -n "${candidate}" && -f "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  err "找不到 x-ui.db。如果 3x-ui 使用 PostgreSQL 后端，第一版脚本暂不支持自动导出。"
  return 1
}

prepare_output_dir() {
  local out="${1:-${OUT_OVERRIDE}}"

  if [[ -z "${out}" ]]; then
    out="/root/3xui-node-export-$(date +%Y%m%d-%H%M%S)"
  fi

  mkdir -p "${out}" || return 1
  chmod 700 "${out}" || return 1
  printf '%s\n' "${out}"
}

resolve_temp_root() {
  local root="${TMPDIR:-/tmp}"

  [[ "${root}" == /* ]] || {
    err "临时目录必须是绝对路径：${root}"
    return 1
  }
  [[ "${root}" != "/" && -d "${root}" && -w "${root}" ]] || {
    err "临时目录不可用：${root}"
    return 1
  }

  root="$(cd -P -- "${root}" 2>/dev/null && pwd -P)" || return 1
  [[ -n "${root}" && "${root}" != "/" ]] || return 1
  printf '%s\n' "${root}"
}

is_safe_self_destruct_session() {
  local path="$1"
  local root="${SELF_DESTRUCT_TEMP_ROOT}"
  local base=""

  [[ -n "${path}" && -n "${root}" ]] || return 1
  [[ "${path}" == "${root}"/* ]] || return 1
  base="${path#"${root}"/}"
  [[ "${base}" != */* ]] || return 1
  [[ "${base}" =~ ^3xui-self-destruct\.[A-Za-z0-9]+$ ]] || return 1
}

cleanup_self_destruct_session() {
  local path="${SELF_DESTRUCT_SESSION_DIR:-}"

  [[ -n "${path}" ]] || return 0
  if ! is_safe_self_destruct_session "${path}"; then
    err "拒绝清理未通过安全校验的路径：${path}"
    return 1
  fi

  if [[ -e "${path}" || -L "${path}" ]]; then
    rm -rf -- "${path}" || {
      err "未能清理临时导出目录：${path}"
      return 1
    }
  fi

  SELF_DESTRUCT_SESSION_DIR=""
  SELF_DESTRUCT_ARCHIVE=""
}

handle_self_destruct_signal() {
  local exit_code="$1"
  cleanup_self_destruct_session || true
  trap - EXIT
  exit "${exit_code}"
}

install_self_destruct_traps() {
  trap cleanup_self_destruct_session EXIT
  trap 'handle_self_destruct_signal 129' HUP
  trap 'handle_self_destruct_signal 130' INT
  trap 'handle_self_destruct_signal 143' TERM
}

clear_self_destruct_traps() {
  trap - EXIT HUP INT TERM
}

finalize_self_destruct_cleanup() {
  cleanup_self_destruct_session || return 1
  clear_self_destruct_traps
}

prepare_self_destruct_session() {
  local root=""
  local raw_session=""
  local session=""

  root="$(resolve_temp_root)" || return 1
  raw_session="$(mktemp -d "${root}/3xui-self-destruct.XXXXXXXX")" || return 1
  chmod 700 "${raw_session}" || {
    rm -rf -- "${raw_session}"
    return 1
  }
  session="$(cd -P -- "${raw_session}" 2>/dev/null && pwd -P)" || {
    rm -rf -- "${raw_session}"
    return 1
  }

  SELF_DESTRUCT_TEMP_ROOT="${root}"
  SELF_DESTRUCT_SESSION_DIR="${session}"
  is_safe_self_destruct_session "${session}" || {
    err "临时导出目录未通过安全校验。"
    rm -rf -- "${session}"
    SELF_DESTRUCT_SESSION_DIR=""
    return 1
  }

  install_self_destruct_traps
  mkdir -p "${session}/data" || return 1
  chmod 700 "${session}/data" || return 1
}

secure_output_files() {
  local out="$1"
  local file

  chmod 700 "${out}" 2>/dev/null || true
  for file in "${out}"/*; do
    [[ -e "${file}" ]] || continue
    [[ -f "${file}" ]] && chmod 600 "${file}" 2>/dev/null || true
  done
}

create_self_destruct_archive() {
  local source_dir="$1"
  local archive="$2"
  local archive_name=""

  [[ "${source_dir}" == "${SELF_DESTRUCT_SESSION_DIR}/data" ]] || {
    err "拒绝打包未受控的导出目录：${source_dir}"
    return 1
  }
  [[ "${archive}" == "${SELF_DESTRUCT_SESSION_DIR}"/* ]] || {
    err "拒绝写入未受控的归档路径：${archive}"
    return 1
  }
  archive_name="${archive#"${SELF_DESTRUCT_SESSION_DIR}"/}"
  [[ "${archive_name}" != */* && "${archive_name}" == *.zip ]] || {
    err "拒绝写入未受控的归档文件名：${archive_name}"
    return 1
  }

  python3 - "${source_dir}" "${archive}" <<'PY'
import sys
import zipfile
from pathlib import Path

source = Path(sys.argv[1])
archive = Path(sys.argv[2])

files = sorted(path for path in source.iterdir() if path.is_file())
if not files:
    raise SystemExit("no export files to archive")

with zipfile.ZipFile(
    archive,
    "w",
    compression=zipfile.ZIP_DEFLATED,
    compresslevel=6,
) as bundle:
    for path in files:
        bundle.write(path, arcname=path.name)
PY
  chmod 600 "${archive}" || return 1
}

remove_self_destruct_staging() {
  local staging="${SELF_DESTRUCT_SESSION_DIR}/data"

  is_safe_self_destruct_session "${SELF_DESTRUCT_SESSION_DIR}" || return 1
  [[ -d "${staging}" && ! -L "${staging}" ]] || return 1
  rm -rf -- "${staging}"
}

read_archive_metadata() {
  local archive="$1"

  python3 - "${archive}" <<'PY'
import hashlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
digest = hashlib.sha256()
with path.open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
print(path.stat().st_size)
print(digest.hexdigest())
PY
}

run_python_export() {
  local db="$1"
  local out="$2"
  local addr="$3"

  python3 - "${db}" "${out}" "${addr}" <<'PY'
import base64
import json
import shlex
import socket
import sqlite3
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

db = sys.argv[1]
out = Path(sys.argv[2])
addr = sys.argv[3].strip()
snap = out / "x-ui.snapshot.db"

def normalize_host(value):
    value = (value or "").strip()
    if not value:
        return ""
    if "://" in value:
        parsed = urllib.parse.urlsplit(value)
        value = parsed.netloc or parsed.path
    value = value.strip().strip("/")
    if "/" in value:
        value = value.split("/", 1)[0]
    return value

def detect_public_ip():
    for url in ("https://api.ipify.org", "https://ifconfig.me/ip"):
        try:
            return urllib.request.urlopen(url, timeout=3).read().decode().strip()
        except Exception:
            pass
    try:
        return subprocess.check_output(["hostname", "-I"], text=True, timeout=2).split()[0]
    except Exception:
        try:
            return socket.gethostbyname(socket.gethostname())
        except Exception:
            return "127.0.0.1"

def json_safe(value):
    if isinstance(value, bytes):
        try:
            return value.decode("utf-8")
        except Exception:
            return base64.b64encode(value).decode("ascii")
    return value

src = sqlite3.connect(f"file:{db}?mode=ro", uri=True, timeout=10)
dst = sqlite3.connect(str(snap))
src.backup(dst)
src.close()
dst.close()

con = sqlite3.connect(str(snap))
con.row_factory = sqlite3.Row

def table_exists(name):
    return con.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
        (name,),
    ).fetchone() is not None

def table_columns(name):
    if not table_exists(name):
        return []
    return [row["name"] for row in con.execute(f"PRAGMA table_info({name})")]

def setting(key, default=""):
    if not table_exists("settings"):
        return default
    try:
        row = con.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
    except Exception:
        return default
    if row and row["value"] not in (None, ""):
        return str(row["value"])
    return default

sub_port = setting("subPort", "2096")
sub_path = setting("subPath", "/sub/")
if not sub_path.startswith("/"):
    sub_path = "/" + sub_path
if not sub_path.endswith("/"):
    sub_path += "/"

host = (
    normalize_host(addr)
    or normalize_host(setting("subDomain"))
    or normalize_host(setting("webDomain"))
    or detect_public_ip()
)

subids = set()
raw_inbounds = []

if table_exists("inbounds"):
    rows = con.execute("SELECT * FROM inbounds ORDER BY id").fetchall()
    for row in rows:
        data = {key: json_safe(row[key]) for key in row.keys()}

        for key in ("settings", "stream_settings", "streamSettings", "sniffing", "allocate"):
            if key in data and isinstance(data[key], str) and data[key].strip():
                try:
                    data[f"{key}_parsed"] = json.loads(data[key])
                except Exception:
                    pass

        raw_inbounds.append(data)

        try:
            settings = json.loads(data.get("settings") or "{}")
            for client in settings.get("clients", []) or []:
                if not isinstance(client, dict):
                    continue
                sid = client.get("subId") or client.get("sub_id") or client.get("subid")
                if sid:
                    subids.add(str(sid))
        except Exception:
            pass

if table_exists("clients"):
    cols = table_columns("clients")
    for field in ("sub_id", "subId", "subid"):
        if field not in cols:
            continue
        try:
            for row in con.execute(f'SELECT "{field}" AS subid FROM clients WHERE "{field}" IS NOT NULL AND "{field}" != ""'):
                subids.add(str(row["subid"]))
        except Exception:
            pass

(out / "raw_inbounds.json").write_text(
    json.dumps(raw_inbounds, ensure_ascii=False, indent=2),
    encoding="utf-8",
)
(out / "subids.txt").write_text(
    "\n".join(sorted(subids)) + ("\n" if subids else ""),
    encoding="utf-8",
)
(out / "env.sh").write_text(
    "\n".join(
        [
            f"SUB_PORT={shlex.quote(str(sub_port))}",
            f"SUB_PATH={shlex.quote(str(sub_path))}",
            f"HOST_FOR_LINKS={shlex.quote(str(host))}",
            f"DB_PATH={shlex.quote(str(db))}",
            f"SNAPSHOT_PATH={shlex.quote(str(snap))}",
        ]
    )
    + "\n",
    encoding="utf-8",
)

print(f"DB={db}")
print(f"SNAPSHOT={snap}")
print(f"OUT={out}")
print(f"SUB_PORT={sub_port}")
print(f"SUB_PATH={sub_path}")
print(f"HOST_FOR_LINKS={host}")
print(f"SUBIDS={len(subids)}")
PY
}

fetch_links() {
  local out="$1"
  local tmp=""
  local sid=""
  local scheme=""
  local url=""
  local ok="0"
  local fetched=0
  local failed=0

  # shellcheck disable=SC1090
  . "${out}/env.sh"

  : > "${out}/links.raw"
  : > "${out}/links.txt"
  : > "${out}/curl-errors.log"

  if [[ ! -s "${out}/subids.txt" ]]; then
    warn "没有找到 subId，已保留 raw_inbounds.json 供手动恢复。"
    return 0
  fi

  while IFS= read -r sid; do
    [[ -n "${sid}" ]] || continue

    tmp="$(mktemp "${out}/.subscription.XXXXXXXX")" || {
      err "无法创建订阅抓取临时文件。"
      return 1
    }
    ok="0"

    for scheme in http https; do
      url="${scheme}://127.0.0.1:${SUB_PORT}${SUB_PATH}${sid}"
      if curl -fksS --max-time 8 \
        -H "Host: ${HOST_FOR_LINKS}" \
        -H "Accept: text/plain" \
        "${url}" -o "${tmp}" 2>>"${out}/curl-errors.log"; then
        if [[ -s "${tmp}" ]]; then
          ok="1"
          break
        fi
      fi
    done

    if [[ "${ok}" == "1" ]]; then
      {
        printf '### subId=%s\n' "${sid}"
        cat "${tmp}"
        printf '\n'
      } >> "${out}/links.raw"

      if base64 -d "${tmp}" > "${tmp}.dec" 2>/dev/null &&
        grep -Eq '(vmess|vless|trojan|ss|hysteria2?|hy2)://' "${tmp}.dec"; then
        cat "${tmp}.dec" >> "${out}/links.txt"
      else
        cat "${tmp}" >> "${out}/links.txt"
      fi
      printf '\n' >> "${out}/links.txt"
      fetched=$((fetched + 1))
    else
      printf 'FAILED subId=%s\n' "${sid}" >> "${out}/curl-errors.log"
      failed=$((failed + 1))
    fi

    rm -f "${tmp}" "${tmp}.dec"
  done < "${out}/subids.txt"

  awk 'NF && !seen[$0]++' "${out}/links.txt" > "${out}/links.dedup.txt"
  mv "${out}/links.dedup.txt" "${out}/links.txt"

  info "订阅抓取完成：成功 ${fetched} 个，失败 ${failed} 个。"
}

count_nonempty_lines() {
  local file="$1"
  if [[ -s "${file}" ]]; then
    awk 'NF { c++ } END { print c + 0 }' "${file}"
  else
    printf '0\n'
  fi
}

preview_links() {
  local out="$1"

  if [[ ! -s "${out}/links.txt" ]]; then
    warn "links.txt 为空，没有可预览的节点链接。"
    return 0
  fi

  print_title "links.txt 前 20 行"
  head -n 20 "${out}/links.txt"
}

print_export_summary() {
  local out="$1"
  local raw_only="$2"
  local link_count="0"
  local subid_count="0"

  link_count="$(count_nonempty_lines "${out}/links.txt")"
  subid_count="$(count_nonempty_lines "${out}/subids.txt")"

  print_title "导出完成"
  echo "输出目录        : ${out}"
  echo "数据库快照      : ${out}/x-ui.snapshot.db"
  echo "原始 inbound    : ${out}/raw_inbounds.json"
  echo "subId 列表      : ${out}/subids.txt (${subid_count})"
  if [[ "${raw_only}" == "1" ]]; then
    echo "节点链接        : 已跳过（raw-only）"
  else
    echo "节点链接        : ${out}/links.txt (${link_count})"
    echo "原始订阅响应    : ${out}/links.raw"
    echo "抓取错误日志    : ${out}/curl-errors.log"
  fi
  echo ""
  warn "这些文件包含可直接连接的敏感信息，请不要提交到仓库或公开分享。"
}

maybe_preview_after_export() {
  local out="$1"
  local allow_prompt="$2"

  if [[ "${SHOW_LINKS}" == "1" ]]; then
    preview_links "${out}"
    return 0
  fi

  if [[ "${allow_prompt}" == "1" && "${YES}" != "1" ]] &&
    confirm_yes "是否预览 links.txt 前 20 行" "n"; then
    preview_links "${out}"
  fi
}

run_export() {
  local raw_only="${1:-0}"
  local allow_preview_prompt="${2:-0}"
  local forced_out="${3:-}"
  local show_summary="${4:-1}"
  local db=""
  local out=""

  print_title "3x-ui 节点导出"

  db="$(locate_db)" || return 1
  out="$(prepare_output_dir "${forced_out}")" || {
    err "无法创建导出目录。"
    return 1
  }

  info "数据库：${db}"
  info "输出目录：${out}"

  if ! run_python_export "${db}" "${out}" "${ADDR}"; then
    err "数据库读取失败。"
    secure_output_files "${out}"
    return 1
  fi

  : > "${out}/links.raw"
  : > "${out}/links.txt"
  : > "${out}/curl-errors.log"

  if [[ "${raw_only}" != "1" ]]; then
    fetch_links "${out}" || {
      secure_output_files "${out}"
      return 1
    }
  else
    info "已按 raw-only 模式跳过订阅抓取。"
  fi

  secure_output_files "${out}"
  if [[ "${show_summary}" == "1" ]]; then
    print_export_summary "${out}" "${raw_only}"
  fi
  maybe_preview_after_export "${out}" "${allow_preview_prompt}"
}

print_self_destruct_download_page() {
  local archive="$1"
  local metadata=""
  local archive_size=""
  local archive_sha256=""
  local archive_name="${archive##*/}"

  metadata="$(read_archive_metadata "${archive}")" || return 1
  archive_size="${metadata%%$'\n'*}"
  archive_sha256="${metadata#*$'\n'}"

  print_title "临时导出已就绪"
  echo "临时 ZIP       : ${archive}"
  echo "文件大小       : ${archive_size} 字节"
  echo "SHA-256        : ${archive_sha256}"
  echo ""
  echo "请在自己电脑的另一个终端下载："
  printf "  scp 'root@<VPS地址>:%s' .\n" "${archive}"
  echo ""
  echo "Windows PowerShell 校验："
  echo "  Get-FileHash .\\${archive_name} -Algorithm SHA256"
  echo "Linux 校验："
  echo "  sha256sum ./${archive_name}"
  echo "macOS 校验："
  echo "  shasum -a 256 ./${archive_name}"
  echo ""
  warn "下载完成后回到本窗口按回车；最多等待 $((SELF_DESTRUCT_TIMEOUT_SECONDS / 60)) 分钟。"
  warn "ZIP 未加密，请只通过 SSH/SFTP 下载并妥善保管。"
}

wait_for_self_destruct_download() {
  local input=""
  local input_path=""

  if ! has_tty; then
    err "自销毁模式需要交互式终端，以确认下载完成。"
    return 1
  fi

  input_path="$(self_destruct_input_path)"
  if input="$(read_tty_timeout \
    "下载完成后按回车立即清理: " \
    "${SELF_DESTRUCT_TIMEOUT_SECONDS}" \
    "${input_path}")"; then
    info "已收到清理确认。"
  else
    warn "等待时间已到或终端已断开，开始自动清理。"
  fi
}

self_destruct_input_path() {
  printf '%s\n' "/dev/tty"
}

maybe_delete_script_source() {
  local src=""
  local answer=""

  src="$(script_source_path || true)"
  if [[ -z "${src}" || "${src}" == /dev/fd/* || "${src}" == /proc/self/fd/* ]]; then
    info "当前通过管道或临时文件描述符运行，没有脚本文件需要删除。"
    return 0
  fi
  if [[ ! -f "${src}" && ! -L "${src}" ]]; then
    info "没有找到可删除的脚本文件。"
    return 0
  fi

  echo ""
  warn "当前脚本文件仍在磁盘上：${src}"
  answer="$(read_tty "如需删除这个文件，请输入 DELETE；直接回车保留: ")"
  if [[ "${answer}" != "DELETE" ]]; then
    info "已保留脚本文件。"
    return 0
  fi

  rm -f -- "${src}" || {
    err "无法删除脚本文件：${src}"
    return 1
  }
  SCRIPT_SOURCE_DELETED="1"
  success "已删除脚本文件：${src}"
}

run_self_destruct_export() {
  local raw_only="${1:-0}"
  local data_dir=""
  local timestamp=""

  if ! has_tty; then
    err "自销毁模式需要在已登录 VPS 的交互式终端中运行。"
    return 1
  fi

  umask 077
  prepare_self_destruct_session || {
    err "无法创建受控临时导出目录。"
    finalize_self_destruct_cleanup || true
    return 1
  }

  data_dir="${SELF_DESTRUCT_SESSION_DIR}/data"
  timestamp="$(date +%Y%m%d-%H%M%S)"
  SELF_DESTRUCT_ARCHIVE="${SELF_DESTRUCT_SESSION_DIR}/3xui-node-export-${timestamp}.zip"

  if ! run_export "${raw_only}" "0" "${data_dir}" "0"; then
    err "临时导出失败，正在清理本次产物。"
    finalize_self_destruct_cleanup || true
    return 1
  fi

  if ! create_self_destruct_archive "${data_dir}" "${SELF_DESTRUCT_ARCHIVE}"; then
    err "无法生成临时 ZIP，正在清理本次产物。"
    finalize_self_destruct_cleanup || true
    return 1
  fi
  if ! remove_self_destruct_staging; then
    err "无法删除归档前的散装文件，正在清理整个临时目录。"
    finalize_self_destruct_cleanup || true
    return 1
  fi

  if ! print_self_destruct_download_page "${SELF_DESTRUCT_ARCHIVE}"; then
    err "无法读取临时 ZIP 信息，正在清理本次产物。"
    finalize_self_destruct_cleanup || true
    return 1
  fi

  wait_for_self_destruct_download || true
  finalize_self_destruct_cleanup || return 1
  success "本次临时导出目录、ZIP、数据库快照和中间文件已清理。"
  warn "Shell 历史、终端回滚、系统审计/网络日志和文件系统快照不在清理范围内。"
  maybe_delete_script_source
}

run_diagnostics() {
  print_title "环境诊断"

  if [[ "${EUID}" -eq 0 ]]; then
    success "权限：root"
  else
    warn "权限：非 root"
  fi

  local cmd
  for cmd in python3 curl base64 awk mktemp chmod date find head sort grep; do
    if command_exists "${cmd}"; then
      success "命令：${cmd}"
    else
      warn "命令缺失：${cmd}"
    fi
  done

  local db=""
  db="$(locate_db || true)"
  if [[ -n "${db}" ]]; then
    success "数据库：${db}"
    if command_exists python3; then
      python3 - "${db}" <<'PY' || true
import sqlite3
import sys

db = sys.argv[1]
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True, timeout=5)
con.row_factory = sqlite3.Row

def table_exists(name):
    return con.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
        (name,),
    ).fetchone() is not None

print("表检查：")
for name in ("settings", "inbounds", "clients"):
    print(f"  {name}: {'存在' if table_exists(name) else '不存在'}")
if table_exists("inbounds"):
    count = con.execute("SELECT COUNT(*) AS c FROM inbounds").fetchone()["c"]
    print(f"inbounds 数量：{count}")
PY
    fi
  else
    warn "数据库：未找到"
  fi
}

show_help_screen() {
  print_title "帮助"
  print_usage
  echo ""
  echo "也可以这样运行："
  echo "curl -fsSL ${RAW_URL} | bash"
}

prompt_addr_and_export() {
  local value=""
  value="$(read_tty "请输入节点对外域名或公网 IP（留空自动判断）: ")"
  ADDR="${value}"
  run_export "0" "1"
}

print_main_menu() {
  print_title "3x-ui 节点导出工具"
  print_menu_section "导出"
  print_menu_item 1 "一键导出订阅/节点链接"
  print_menu_item 2 "指定域名/IP 后导出"
  print_menu_item 3 "只导出原始 inbound 配置"
  print_menu_item 4 "临时导出并自动清理"
  print_menu_section "工具"
  print_menu_item 5 "环境诊断"
  print_menu_item 6 "查看帮助和一行命令"
  print_menu_footer
  print_menu_item 0 "退出"
  print_menu_footer
}

main_menu() {
  local choice=""

  while true; do
    menu_clear_screen
    print_main_menu
    choice="$(read_tty "请选择操作 [0-6]: ")"

    case "${choice}" in
      1)
        ADDR=""
        run_export "0" "1"
        pause_before_return
        ;;
      2)
        prompt_addr_and_export
        pause_before_return
        ;;
      3)
        run_export "1" "0"
        pause_before_return
        ;;
      4)
        ADDR=""
        run_self_destruct_export "0"
        if [[ "${SCRIPT_SOURCE_DELETED}" == "1" ]]; then
          exit 0
        fi
        pause_before_return
        ;;
      5)
        run_diagnostics
        pause_before_return
        ;;
      6)
        show_help_screen
        pause_before_return
        ;;
      0)
        exit 0
        ;;
      *)
        warn "无效选择。"
        pause_before_return
        ;;
    esac
  done
}

main() {
  local original_args=("$@")

  parse_args "$@"
  setup_colors
  validate_args
  ensure_root "${original_args[@]}"
  ensure_dependencies

  if [[ "${SELF_DESTRUCT}" == "1" ]]; then
    run_self_destruct_export "${RAW_ONLY}"
  elif [[ "${CLI_MODE}" == "1" ]]; then
    run_export "${RAW_ONLY}" "0"
  else
    main_menu
  fi
}

if [[ "${XUI_EXPORTER_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
