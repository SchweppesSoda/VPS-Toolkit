#!/bin/bash
# =========================================
#  po0-debian-reinstall.sh
#  Auto Install Debian 12 (bookworm)
#  via Tencent mirrors (无人值守 DD)
#
#  来源：
#    - 基于 vpsbuy/po0 仓库的 po0dd.sh 修改
#    - https://github.com/vpsbuy/po0
#    - https://github.com/vpsbuy/po0/blob/main/po0dd.sh
#
#  特性：
#    - 优先从当前 / 挂载点反推系统盘，失败再回退常见设备名
#    - 腾讯镜像自动选择：mirrors.tencentyun.com -> mirrors.tencent.com
#    - 支持 -passwd 指定 root 密码，不传则随机生成
#    - 支持 -port   指定 SSH 端口，默认 22
#    - 安装完成后开启 root 密码登录 + SSH
#    - preseed 中写入密码哈希，随机密码才写入 /root/initial_root_password.txt
#    - GRUB 只对“下次重启”进入安装，避免长期残留危险默认项
#
#  使用示例：
#    bash po0-debian-reinstall.sh
#    bash po0-debian-reinstall.sh -passwd MyStrongPwd
#    bash po0-debian-reinstall.sh -port 60022
#    bash po0-debian-reinstall.sh -passwd ExampleStrongPassword -port 2222
#
#  注意：会整盘重装系统盘，数据全部清空！
# =========================================

set -e

SCRIPT_VERSION="2026.07.22+build.1"
SCRIPT_RELEASE_DATE="2026-07-22"
# CHANGELOG_BEGIN
# - 修复 DISABLE_IPV6=false 时仍向安装内核传入 ipv6.disable=1。
# - 独立 /boot 分区会使用 GRUB 视角的 /debian-autoinstall 路径；其余环境保持原路径。
# CHANGELOG_END

# ======== 默认配置（可改） ========
DEBIAN_RELEASE="bookworm"       # Debian 12 = bookworm
HOSTNAME="debian"               # 安装后主机名
TIMEZONE="Asia/Shanghai"        # 时区
MIRROR_HOST=""
MIRROR_HOSTS=("mirrors.tencentyun.com" "mirrors.tencent.com")

ROOT_PASSWORD=""                # 默认留空，后面用 -passwd 覆盖，留空则随机
ROOT_PASSWORD_HASH=""           # preseed 中使用 crypt(3) 哈希，避免写入明文密码
ALLOW_WEAK_PASSWORD=true        # 是否允许弱密码（true/false）

SSH_PORT="22"                   # 默认 SSH 端口，可被 -port 覆盖

# 是否禁止安装过程中的 IPv6（部分国内网络 IPv6 有坑，可选）
DISABLE_IPV6=true
# ================================

GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
NC="\033[0m"

installer_ipv6_kernel_arg() {
  if [[ "${1:-}" == "true" ]]; then
    printf 'ipv6.disable=1'
  fi
}

detect_boot_mount_target() {
  local target=""

  if command -v findmnt >/dev/null 2>&1; then
    target="$(findmnt -nro TARGET --target /boot 2>/dev/null || true)"
  fi

  printf '%s\n' "${target:-/}"
}

grub_installer_asset_dir() {
  local boot_mount_target="${1:-}"

  if [[ -z "$boot_mount_target" ]]; then
    boot_mount_target="$(detect_boot_mount_target)"
  fi

  if [[ "$boot_mount_target" == "/boot" ]]; then
    printf '/debian-autoinstall\n'
  else
    printf '/boot/debian-autoinstall\n'
  fi
}

render_grub_installer_entry() {
  local asset_dir="$1"
  local ipv6_kernel_arg="$2"

  cat <<EOF
#!/bin/sh
exec tail -n +3 \$0

menuentry '${GRUB_MENU_TITLE}' --id ${GRUB_MENU_ID} {
    insmod gzio
    insmod part_msdos
    insmod part_gpt
    insmod ext2
    search --no-floppy --file ${asset_dir}/linux --set=root

    linux ${asset_dir}/linux \
        auto=true priority=critical \
        preseed/file=/preseed.cfg \
        debian-installer/locale=en_US.UTF-8 \
        keyboard-configuration/xkb-keymap=us \
        netcfg/choose_interface=auto \
        netcfg/disable_dhcp=false \
        mirror/country=manual \
        mirror/http/hostname=${MIRROR_HOST} \
        mirror/http/directory=/debian \
        mirror/http/proxy= \
        mirror/suite=${DEBIAN_RELEASE} \
        hostname=${HOSTNAME} domain=localdomain ${ipv6_kernel_arg}

    initrd ${asset_dir}/initrd.gz
}
EOF
}

if [[ "${PO0_DEBIAN_REINSTALL_LIB_ONLY:-0}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

resolve_disk_from_device() {
  local dev="$1"
  local dev_type=""
  local parent=""

  while [[ -n "$dev" && -b "$dev" ]]; do
    dev_type="$(lsblk -ndo TYPE "$dev" 2>/dev/null | head -1)"
    if [[ "$dev_type" == "disk" ]]; then
      echo "$dev"
      return 0
    fi

    parent="$(lsblk -ndo PKNAME "$dev" 2>/dev/null | head -1)"
    if [[ -z "$parent" ]]; then
      break
    fi
    dev="/dev/${parent}"
  done

  return 1
}

show_version() {
  cat <<EOF
script_name=po0-debian-reinstall
version=${SCRIPT_VERSION}
release_date=${SCRIPT_RELEASE_DATE}
EOF
}

show_changelog() {
  awk '
    /^# CHANGELOG_BEGIN$/ { printing = 1; next }
    /^# CHANGELOG_END$/ { exit }
    printing { sub(/^# ?/, ""); print }
  ' "${BASH_SOURCE[0]}"
}

usage() {
  cat <<EOF
用法:
  bash po0-debian-reinstall.sh [-passwd MyPassword] [-port 22]
  bash po0-debian-reinstall.sh --version
  bash po0-debian-reinstall.sh --changelog

说明:
  -passwd  指定 root 密码；不指定则自动生成随机密码
  -port    指定 SSH 端口（默认: ${SSH_PORT}）

示例:
  bash po0-debian-reinstall.sh                     # 随机 root 密码 + SSH 22
  bash po0-debian-reinstall.sh -passwd MyStrongPwd # 自定义密码 + SSH 22
  bash po0-debian-reinstall.sh -port 60022         # 随机密码 + SSH 60022
  bash po0-debian-reinstall.sh -passwd P@ss -port 2222
EOF
}

# ------- 参数解析 -------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -passwd|--passwd)
      ROOT_PASSWORD="$2"
      shift 2
      ;;
    -port|--port)
      SSH_PORT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -V|--version)
      show_version
      exit 0
      ;;
    --changelog)
      show_changelog
      exit 0
      ;;
    *)
      echo -e "${YELLOW}[!] 未知参数: $1${NC}"
      usage
      exit 1
      ;;
  esac
done

# ------- 自动检测系统盘 DISK -------
detect_disk() {
  local root_source=""
  local resolved_source=""
  local detected_disk=""

  if command -v findmnt >/dev/null 2>&1; then
    root_source="$(findmnt -nro SOURCE / 2>/dev/null || true)"
  fi

  if [[ -n "$root_source" ]]; then
    resolved_source="$(readlink -f "$root_source" 2>/dev/null || printf '%s' "$root_source")"
    detected_disk="$(resolve_disk_from_device "$resolved_source" || true)"
    if [[ -n "$detected_disk" ]]; then
      echo "$detected_disk"
      return 0
    fi
  fi

  if [[ -b /dev/vda ]]; then
    echo "/dev/vda"
  elif [[ -b /dev/xvda ]]; then
    echo "/dev/xvda"
  elif [[ -b /dev/sda ]]; then
    echo "/dev/sda"
  elif [[ -b /dev/nvme0n1 ]]; then
    echo "/dev/nvme0n1"
  else
    echo ""
  fi
}

DISK="$(detect_disk)"

if [[ -z "$DISK" ]]; then
  echo -e "${YELLOW}[!] 未能自动检测到系统盘。${NC}"
  echo -e "${YELLOW}[!] 请手动检查 findmnt / lsblk 输出后再修改脚本重试。${NC}"
  exit 1
fi

# ------- 校验端口 -------
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]]; then
  echo -e "${YELLOW}[!] 端口必须是数字: $SSH_PORT${NC}"
  exit 1
fi
if (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
  echo -e "${YELLOW}[!] 端口范围必须在 1-65535 之间: $SSH_PORT${NC}"
  exit 1
fi

# ------- 生成随机密码（如需要） -------
gen_random_password() {
  # 仅使用 A-Za-z0-9，避免 preseed 解析问题
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20
}

gen_password_hash() {
  local password="$1"
  local salt=""

  salt="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)"

  if command -v openssl >/dev/null 2>&1; then
    printf '%s\n' "$password" | openssl passwd -6 -salt "$salt" -stdin
    return 0
  fi

  if command -v perl >/dev/null 2>&1; then
    PASSWORD="$password" HASH_SALT="$salt" perl -e 'print crypt($ENV{"PASSWORD"}, "\$6\$" . $ENV{"HASH_SALT"} . "\$"), "\n";'
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    PASSWORD="$password" HASH_SALT="$salt" python3 -c 'import crypt, os; print(crypt.crypt(os.environ["PASSWORD"], "$6$" + os.environ["HASH_SALT"] + "$"))'
    return 0
  fi

  return 1
}

if [[ -z "$ROOT_PASSWORD" || "$ROOT_PASSWORD" == "RANDOM" ]]; then
  ROOT_PASSWORD="$(gen_random_password)"
  RANDOM_PW=1
else
  RANDOM_PW=0
fi

if ! ROOT_PASSWORD_HASH="$(gen_password_hash "$ROOT_PASSWORD")"; then
  echo -e "${YELLOW}[!] 无法生成 root 密码哈希（缺少 openssl / perl / python3 之一）${NC}"
  exit 1
fi

if [[ $RANDOM_PW -eq 1 ]]; then
  ROOT_PASSWORD_FILE_LATE_COMMAND="printf \"Initial root password: ${ROOT_PASSWORD}\\n\" > /root/initial_root_password.txt; chmod 600 /root/initial_root_password.txt 2>/dev/null || true;"
else
  ROOT_PASSWORD_FILE_LATE_COMMAND="rm -f /root/initial_root_password.txt 2>/dev/null || true;"
fi

echo -e "${BLUE}[*] po0dd 无人值守 Debian 12 安装启动...${NC}"

# ------- 基础检查 -------
if [[ $EUID -ne 0 ]]; then
  echo -e "${YELLOW}[!] 请用 root 运行本脚本${NC}"
  exit 1
fi

if [[ ! -b "$DISK" ]]; then
  echo -e "${YELLOW}[!] 自动检测到的系统盘 ${DISK} 不存在，请检查宿主环境${NC}"
  lsblk
  exit 1
fi

echo
echo -e "${YELLOW}严重警告：本操作将【整盘重装】 ${DISK}，所有数据将被彻底清空且无法恢复！${NC}"
echo -e "${YELLOW}当前配置：${NC}"
echo "  系统盘     : $DISK"
echo "  Debian 版本: $DEBIAN_RELEASE"
echo "  主机名     : $HOSTNAME"
echo "  时区       : $TIMEZONE"
echo "  镜像源     : 自动选择（优先内网 mirrors.tencentyun.com，失败回退 mirrors.tencent.com）"
echo "  SSH 端口   : $SSH_PORT"
if [[ $RANDOM_PW -eq 1 ]]; then
  echo -e "  root 密码  : （已自动生成随机密码，下方会显示）"
else
  echo "  root 密码  : $ROOT_PASSWORD"
fi

if [[ $RANDOM_PW -eq 1 ]]; then
  echo
  echo -e "${GREEN}[+] 本次随机生成的 root 密码：${ROOT_PASSWORD}${NC}"
  echo -e "${YELLOW}[!] 请务必先记下此密码，安装完成后用它 SSH 登录${NC}"
fi

echo
read -rp "请键入 YES （大写）以确认继续： " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo -e "${YELLOW}[!] 用户取消${NC}"
  exit 1
fi

# ======= 安装依赖（优先尝试用腾讯源） =======
write_temp_debian_sources() {
  local host="$1"
  local output="$2"

  cat >"$output" <<EOF
deb http://${host}/debian/ stable main contrib non-free non-free-firmware
deb http://${host}/debian/ stable-updates main contrib non-free non-free-firmware
deb http://${host}/debian-security stable-security main contrib non-free non-free-firmware
EOF
}

apt_install_with_temp_tencent_sources() {
  local host=""
  local tmp_sources=""

  for host in "${MIRROR_HOSTS[@]}"; do
    echo -e "${BLUE}[*] 尝试通过腾讯镜像安装依赖：${host}${NC}"
    tmp_sources="$(mktemp)"
    write_temp_debian_sources "$host" "$tmp_sources"

    if apt-get \
      -o Dir::Etc::sourcelist="$tmp_sources" \
      -o Dir::Etc::sourceparts="-" \
      update -y >/dev/null 2>&1 && \
      apt-get \
      -o Dir::Etc::sourcelist="$tmp_sources" \
      -o Dir::Etc::sourceparts="-" \
      install -y cpio gzip wget >/dev/null 2>&1; then
      MIRROR_HOST="$host"
      rm -f "$tmp_sources"
      return 0
    fi

    rm -f "$tmp_sources"
  done

  return 1
}

ensure_tools() {
  need_cpio=0
  need_gzip=0
  need_wget=0

  command -v cpio >/dev/null 2>&1 || need_cpio=1
  command -v gzip >/dev/null 2>&1 || need_gzip=1
  command -v wget >/dev/null 2>&1 || need_wget=1

  if [[ $need_cpio -eq 0 && $need_gzip -eq 0 && $need_wget -eq 0 ]]; then
    return 0
  fi

  echo -e "${BLUE}[*] 正在尝试安装依赖：cpio gzip wget${NC}"

  if command -v apt-get >/dev/null 2>&1; then
    if apt-get update -y >/dev/null 2>&1 && apt-get install -y cpio gzip wget >/dev/null 2>&1; then
      :
    elif [[ -f /etc/debian_version ]] && apt_install_with_temp_tencent_sources; then
      :
    else
      echo -e "${YELLOW}[!] apt 安装依赖失败，且未能使用腾讯镜像临时安装依赖${NC}"
      exit 1
    fi
  elif command -v yum >/dev/null 2>&1; then
    yum install -y cpio gzip wget || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y cpio gzip wget || true
  elif command -v apk >/dev/null 2>&1; then
    apk update
    apk add cpio gzip wget
  else
    echo -e "${YELLOW}[!] 无法识别包管理器，请手动安装 cpio/gzip/wget 后重试${NC}"
    exit 1
  fi

  for cmd in cpio gzip wget; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo -e "${YELLOW}[!] 依赖安装失败：缺少 $cmd${NC}"
      exit 1
    fi
  done
}

ensure_tools

# ======= 准备目录与下载内核和 initrd =======
download_installer_assets() {
  local host=""
  local kernel_url=""
  local initrd_url=""

  for host in "${MIRROR_HOSTS[@]}"; do
    echo -e "${BLUE}[*] 尝试从腾讯镜像下载 debian-installer kernel & initrd：${host}${NC}"
    kernel_url="http://${host}/debian/dists/${DEBIAN_RELEASE}/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"
    initrd_url="http://${host}/debian/dists/${DEBIAN_RELEASE}/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"

    rm -f linux initrd.gz
    if wget --tries=3 --timeout=20 -O linux "$kernel_url" && \
       wget --tries=3 --timeout=20 -O initrd.gz "$initrd_url" && \
       [[ -s linux && -s initrd.gz ]]; then
      MIRROR_HOST="$host"
      return 0
    fi
  done

  return 1
}

WORK_DIR="/boot/debian-autoinstall"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

if ! download_installer_assets; then
  echo -e "${YELLOW}[!] 下载 linux/initrd.gz 失败，请检查能否访问腾讯镜像${NC}"
  exit 1
fi

echo -e "${GREEN}[+] 已选用腾讯镜像：${MIRROR_HOST}${NC}"
echo -e "${GREEN}[+] debian-installer kernel & initrd 已下载${NC}"

# ======= 解包 initrd 并注入 preseed.cfg =======
echo -e "${BLUE}[*] 解包 initrd 并注入 preseed.cfg（无人值守参数 + SSH 修正 + 密码写入）...${NC}"

rm -rf initrd-dir
mkdir -p initrd-dir
cd initrd-dir

# 解包原 initrd
gzip -d -c ../initrd.gz | cpio -idmv

# 生成 preseed.cfg
cat > preseed.cfg <<EOF
### 本 preseed 由 po0-debian-reinstall.sh 自动生成 ###

# 语言与键盘
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us

# 网络（自动获取 IP）
d-i netcfg/choose_interface select auto
d-i netcfg/disable_dhcp boolean false
d-i netcfg/get_hostname string ${HOSTNAME}
d-i netcfg/get_domain string localdomain

# 时区与时钟
d-i clock-setup/utc boolean true
d-i time/zone string ${TIMEZONE}
d-i clock-setup/ntp boolean true

# 镜像设置（使用腾讯镜像）
d-i mirror/country string manual
d-i mirror/http/hostname string ${MIRROR_HOST}
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

d-i mirror/suite string ${DEBIAN_RELEASE}
d-i mirror/udeb/suite string ${DEBIAN_RELEASE}

# APT 相关（安全更新与更新源）
d-i apt-setup/use_mirror boolean true
d-i apt-setup/services-select multiselect security, updates
d-i apt-setup/security_host string ${MIRROR_HOST}
d-i apt-setup/security_path string /debian-security
d-i apt-setup/security_suite string ${DEBIAN_RELEASE}-security

# 分区（整盘自动分区，使用所有空间）
d-i partman-auto/method string regular
d-i partman-auto/disk string ${DISK}
d-i partman-auto/choose_recipe select atomic

d-i partman-lvm/device_remove_lvm boolean true
d-i partman-md/device_remove_md boolean true
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

# ROOT 用户设置
d-i passwd/root-login boolean true
d-i passwd/root-password-crypted password ${ROOT_PASSWORD_HASH}
d-i user-setup/allow-password-weak boolean ${ALLOW_WEAK_PASSWORD}
d-i passwd/make-user boolean false

# 软件选择（最小系统 + SSH）
tasksel tasksel/first multiselect standard, ssh-server
d-i pkgsel/include string curl wget vim openssh-server

# 禁用参与软件包普及度调查
popularity-contest popularity-contest/participate boolean false

# GRUB 安装
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
d-i grub-installer/bootdev string ${DISK}

# 安装结束自动重启
d-i finish-install/reboot_in_progress note

# ------- late_command：安装结束阶段强制打开 SSH/root 密码登录，设置端口，并写入密码文件 -------
d-i preseed/late_command string in-target sh -c 'apt-get update || true; \
  apt-get install -y openssh-server || true; \
  cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true; \
  if grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then \
    sed -i "s/^PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config; \
  else \
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config; \
  fi; \
  if grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then \
    sed -i "s/^PasswordAuthentication.*/PasswordAuthentication yes/" /etc/ssh/sshd_config; \
  else \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config; \
  fi; \
  sed -i "/^Port /d" /etc/ssh/sshd_config; \
  echo "Port ${SSH_PORT}" >> /etc/ssh/sshd_config; \
  ${ROOT_PASSWORD_FILE_LATE_COMMAND} \
  systemctl enable ssh || true; \
  systemctl restart ssh || true'
EOF

# 重新打包 initrd，包含 preseed.cfg
find . | cpio -H newc -o | gzip -9 > ../initrd-preseed.gz

cd ..
mv initrd-preseed.gz initrd.gz
rm -rf initrd-dir

echo -e "${GREEN}[+] 已将 preseed.cfg 注入 initrd（无人值守安装 + SSH 修正 + 端口 + 密码文件）${NC}"

# ======= 写入 GRUB 启动项 =======
update_grub_config() {
  if command -v update-grub >/dev/null 2>&1; then
    update-grub
    return 0
  fi

  if command -v grub-mkconfig >/dev/null 2>&1; then
    CFG_PATH=""
    if [[ -f /boot/grub/grub.cfg ]]; then
      CFG_PATH="/boot/grub/grub.cfg"
    elif [[ -f /boot/grub2/grub.cfg ]]; then
      CFG_PATH="/boot/grub2/grub.cfg"
    fi
    if [[ -n "$CFG_PATH" ]]; then
      grub-mkconfig -o "$CFG_PATH"
      return 0
    fi
  fi

  return 1
}

find_grubenv_path() {
  if [[ -f /boot/grub/grubenv ]]; then
    echo "/boot/grub/grubenv"
  elif [[ -f /boot/grub2/grubenv ]]; then
    echo "/boot/grub2/grubenv"
  fi
}

manual_grub_reboot_hint() {
  local grubenv_path=""

  if command -v grub-reboot >/dev/null 2>&1; then
    echo "grub-reboot ${GRUB_MENU_ID}"
    return 0
  fi

  if command -v grub2-reboot >/dev/null 2>&1; then
    echo "grub2-reboot ${GRUB_MENU_ID}"
    return 0
  fi

  grubenv_path="$(find_grubenv_path)"
  if [[ -n "$grubenv_path" ]] && command -v grub-editenv >/dev/null 2>&1; then
    echo "grub-editenv ${grubenv_path} set next_entry=${GRUB_MENU_ID}"
    return 0
  fi

  if [[ -n "$grubenv_path" ]] && command -v grub2-editenv >/dev/null 2>&1; then
    echo "grub2-editenv ${grubenv_path} set next_entry=${GRUB_MENU_ID}"
    return 0
  fi

  echo ""
}

schedule_one_time_grub_entry() {
  local grubenv_path=""
  local entry_id="$1"

  if command -v grub-reboot >/dev/null 2>&1 && grub-reboot "$entry_id"; then
    return 0
  fi

  if command -v grub2-reboot >/dev/null 2>&1 && grub2-reboot "$entry_id"; then
    return 0
  fi

  grubenv_path="$(find_grubenv_path)"
  if [[ -n "$grubenv_path" ]] && command -v grub-editenv >/dev/null 2>&1 && \
     grub-editenv "$grubenv_path" set "next_entry=$entry_id"; then
    return 0
  fi

  if [[ -n "$grubenv_path" ]] && command -v grub2-editenv >/dev/null 2>&1 && \
     grub2-editenv "$grubenv_path" set "next_entry=$entry_id"; then
    return 0
  fi

  return 1
}

echo -e "${BLUE}[*] 写入 GRUB 启动项（仅下次重启进入安装）...${NC}"

GRUB_SCRIPT="/etc/grub.d/42_po0_autoinstall"
LEGACY_GRUB_SCRIPT="/etc/grub.d/05_po0_autoinstall"
GRUB_MENU_TITLE="*** po0 Auto Install Debian 12 (DD ALL ${DISK}) via Tencent ***"
GRUB_MENU_ID="po0-autoinstall"
GRUB_INSTALLER_ASSET_DIR="$(grub_installer_asset_dir)"
GRUB_IPV6_KERNEL_ARG="$(installer_ipv6_kernel_arg "$DISABLE_IPV6")"

if [[ -f "$LEGACY_GRUB_SCRIPT" ]]; then
  rm -f "$LEGACY_GRUB_SCRIPT"
  echo -e "${YELLOW}[!] 已移除旧版持久 GRUB 启动项：${LEGACY_GRUB_SCRIPT}${NC}"
fi

render_grub_installer_entry "${GRUB_INSTALLER_ASSET_DIR}" "${GRUB_IPV6_KERNEL_ARG}" > "$GRUB_SCRIPT"

chmod +x "$GRUB_SCRIPT"

if ! update_grub_config; then
  echo -e "${YELLOW}[!] 未找到 update-grub 或 grub-mkconfig，请手动更新 GRUB 配置${NC}"
  exit 1
fi

ONE_TIME_BOOT_READY=0
if schedule_one_time_grub_entry "$GRUB_MENU_ID"; then
  ONE_TIME_BOOT_READY=1
else
  echo -e "${YELLOW}[!] 未能自动设置一次性 GRUB 启动项。${NC}"
  GRUB_REBOOT_HINT="$(manual_grub_reboot_hint)"
fi

echo
echo -e "${GREEN}[+] GRUB 自动安装入口已写入：${GRUB_SCRIPT}${NC}"
echo -e "${GREEN}[+] debian-installer 内核与 initrd 已准备完成${NC}"
if [[ $ONE_TIME_BOOT_READY -eq 1 ]]; then
  echo -e "${GREEN}[+] 已设置为【仅下次重启】进入自动安装${NC}"
else
  echo -e "${YELLOW}[!] 当前尚未成功设置“下次重启自动进入安装”${NC}"
  if [[ -n "$GRUB_REBOOT_HINT" ]]; then
    echo -e "${YELLOW}[!] 可先手动执行：${GRUB_REBOOT_HINT}${NC}"
  else
    echo -e "${YELLOW}[!] 如需继续，请手动在下次开机时选择该 GRUB 菜单项${NC}"
  fi
fi
echo
echo -e "${YELLOW}下次重启时，将进入以下 GRUB 条目进行一次性安装：${NC}"
echo -e "${YELLOW}  ${GRUB_MENU_TITLE}${NC}"
echo -e "${YELLOW}安装过程将全自动完成，结束后会自动重启。${NC}"
echo -e "${YELLOW}安装完成后，用以下命令登录（示例）：${NC}"
echo -e "${YELLOW}  ssh -p ${SSH_PORT} root@你的IP${NC}"
if [[ $RANDOM_PW -eq 1 ]]; then
  echo -e "${YELLOW}如忘记随机密码，可在商家 VNC 登录后查看 /root/initial_root_password.txt。${NC}"
else
  echo -e "${YELLOW}root 密码即为你通过 -passwd 传入的密码。${NC}"
fi
echo
read -rp "是否立刻重启？(y/N): " RB
if [[ "$RB" == "y" || "$RB" == "Y" ]]; then
  if [[ $ONE_TIME_BOOT_READY -eq 1 ]]; then
    reboot
  else
    echo -e "${YELLOW}[!] 当前未设置成功一次性启动项，直接 reboot 不会自动进入安装。${NC}"
    if [[ -n "$GRUB_REBOOT_HINT" ]]; then
      echo -e "${YELLOW}[!] 请先执行：${GRUB_REBOOT_HINT}${NC}"
    fi
  fi
else
  if [[ $ONE_TIME_BOOT_READY -eq 1 ]]; then
    echo -e "${YELLOW}[!] 请稍后手动执行 reboot 完成重装流程${NC}"
  else
    echo -e "${YELLOW}[!] 如需稍后继续，请先手动设置一次性启动项后再 reboot${NC}"
    if [[ -n "$GRUB_REBOOT_HINT" ]]; then
      echo -e "${YELLOW}[!] 参考命令：${GRUB_REBOOT_HINT}${NC}"
    fi
  fi
fi
