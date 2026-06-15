#!/usr/bin/env bash
set -uo pipefail

# 3x-ui node exporter.
# Reads the local 3x-ui SQLite database and exports subscription/node links.

SCRIPT_VERSION="1.0.0"
RAW_URL="https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/3x-ui/3x-ui-node-exporter.sh"

ADDR=""
DB_OVERRIDE=""
OUT_OVERRIDE=""
RAW_ONLY="0"
YES="0"
SHOW_LINKS="0"
NO_COLOR="0"
CLI_MODE="0"

C_RESET=""
C_BOLD=""
C_DIM=""
C_GREEN=""
C_YELLOW=""
C_RED=""
C_CYAN=""

setup_colors() {
  if [[ "${NO_COLOR}" == "0" && -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_CYAN=$'\033[36m'
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

has_tty() {
  [[ -r /dev/tty ]]
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
  --yes, -y          非交互确认：自动安装缺失依赖并直接导出
  --show-links       导出后预览 links.txt 前 20 行
  --no-color         关闭彩色输出
  --help, -h         显示帮助

说明:
  默认不会把完整节点链接打印到屏幕。导出的敏感文件权限会设置为 600。
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
        CLI_MODE="1"
        ;;
      --out=*)
        OUT_OVERRIDE="${1#*=}"
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
      --no-color)
        NO_COLOR="1"
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
  local out="${OUT_OVERRIDE}"

  if [[ -z "${out}" ]]; then
    out="/root/3xui-node-export-$(date +%Y%m%d-%H%M%S)"
  fi

  mkdir -p "${out}" || return 1
  chmod 700 "${out}" || return 1
  printf '%s\n' "${out}"
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

    tmp="$(mktemp)"
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
  local db=""
  local out=""

  print_title "3x-ui 节点导出"

  db="$(locate_db)" || return 1
  out="$(prepare_output_dir)" || {
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
  print_export_summary "${out}" "${raw_only}"
  maybe_preview_after_export "${out}" "${allow_preview_prompt}"
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
  echo "1) 一键导出订阅/节点链接"
  echo "2) 指定域名/IP 后导出"
  echo "3) 只导出原始 inbound 配置"
  echo "4) 环境诊断"
  echo "5) 查看帮助和一行命令"
  echo "0) 退出"
  echo ""
}

main_menu() {
  local choice=""

  while true; do
    print_main_menu
    choice="$(read_tty "请选择操作 [0-5]: ")"

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
        run_diagnostics
        pause_before_return
        ;;
      5)
        show_help_screen
        pause_before_return
        ;;
      0|q|Q)
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
  ensure_root "${original_args[@]}"
  ensure_dependencies

  if [[ "${CLI_MODE}" == "1" ]]; then
    run_export "${RAW_ONLY}" "0"
  else
    main_menu
  fi
}

main "$@"
