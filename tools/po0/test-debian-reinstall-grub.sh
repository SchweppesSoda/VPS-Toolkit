#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script_path="${repo_root}/scripts/po0/reinstall/po0-debian-reinstall.sh"
tmp_root="$(mkdir -p "${repo_root}/.tmp" && cd "${repo_root}/.tmp" && pwd -P)"
tmp_dir="$(mktemp -d "${tmp_root}/po0-debian-reinstall-grub.XXXXXX")"
tmp_dir="$(cd "${tmp_dir}" && pwd -P)"
mkdir -p "${tmp_dir}/bin"
trap 'rm -rf "${tmp_dir}"' EXIT

export PO0_DEBIAN_REINSTALL_LIB_ONLY=1
source "${script_path}"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1" expected="$2"
  grep -Fq -- "${expected}" "${file}" || fail "missing expected GRUB line: ${expected}"
}

assert_not_contains() {
  local file="$1" unexpected="$2"
  if grep -Fq -- "${unexpected}" "${file}"; then
    fail "unexpected GRUB content: ${unexpected}"
  fi
}

GRUB_MENU_TITLE="PO0 Debian reinstall test"
GRUB_MENU_ID="po0-reinstall-test"
DISK="/dev/vda"
MIRROR_HOST="mirror.test"
DEBIAN_RELEASE="bookworm"
HOSTNAME="debian-test"

[[ "${SCRIPT_VERSION}" == "2026.07.22+build.2" ]] || fail "unexpected reinstall script version"
version_output="$(PO0_DEBIAN_REINSTALL_LIB_ONLY=0 bash "${script_path}" --version)"
[[ "${version_output}" == *'script_name=po0-debian-reinstall'* ]] || fail "reinstall --version lacks script name"
[[ "${version_output}" == *'version=2026.07.22+build.2'* ]] || fail "reinstall --version lacks current version"
changelog_output="$(PO0_DEBIAN_REINSTALL_LIB_ONLY=0 bash "${script_path}" --changelog)"
[[ "${changelog_output}" == *'DISABLE_IPV6=false'* ]] || fail "reinstall --changelog lacks IPv6 fix"
[[ "${changelog_output}" == *'独立 /boot'* ]] || fail "reinstall --changelog lacks GRUB path fix"
[[ "$(installer_ipv6_kernel_arg true)" == "ipv6.disable=1" ]] || fail "DISABLE_IPV6=true lost its kernel argument"
[[ -z "$(installer_ipv6_kernel_arg false)" ]] || fail "DISABLE_IPV6=false still disables IPv6"

separate_dir="$(grub_installer_asset_dir /boot)"
root_dir="$(grub_installer_asset_dir /)"
[[ "${separate_dir}" == "/debian-autoinstall" ]] || fail "independent /boot path is wrong: ${separate_dir}"
[[ "${root_dir}" == "/boot/debian-autoinstall" ]] || fail "root-filesystem /boot path changed: ${root_dir}"

separate_false="${tmp_dir}/separate-false.grub"
separate_true="${tmp_dir}/separate-true.grub"
root_false="${tmp_dir}/root-false.grub"
root_true="${tmp_dir}/root-true.grub"

render_grub_installer_entry "${separate_dir}" "$(installer_ipv6_kernel_arg false)" > "${separate_false}"
render_grub_installer_entry "${separate_dir}" "$(installer_ipv6_kernel_arg true)" > "${separate_true}"
render_grub_installer_entry "${root_dir}" "$(installer_ipv6_kernel_arg false)" > "${root_false}"
render_grub_installer_entry "${root_dir}" "$(installer_ipv6_kernel_arg true)" > "${root_true}"

for file in "${separate_false}" "${separate_true}"; do
  assert_contains "${file}" 'search --no-floppy --file /debian-autoinstall/linux --set=root'
  assert_contains "${file}" 'linux /debian-autoinstall/linux'
  assert_contains "${file}" 'initrd /debian-autoinstall/initrd.gz'
  assert_not_contains "${file}" '/boot/debian-autoinstall/'
done

for file in "${root_false}" "${root_true}"; do
  assert_contains "${file}" 'search --no-floppy --file /boot/debian-autoinstall/linux --set=root'
  assert_contains "${file}" 'linux /boot/debian-autoinstall/linux'
  assert_contains "${file}" 'initrd /boot/debian-autoinstall/initrd.gz'
done

assert_not_contains "${separate_false}" 'ipv6.disable=1'
assert_not_contains "${root_false}" 'ipv6.disable=1'
assert_contains "${separate_true}" 'hostname=debian-test domain=localdomain ipv6.disable=1'
assert_contains "${root_true}" 'hostname=debian-test domain=localdomain ipv6.disable=1'

cat > "${tmp_dir}/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_BOOT_MOUNT_TARGET:?}"
EOF
chmod +x "${tmp_dir}/bin/findmnt"

detected="$(PATH="${tmp_dir}/bin:${PATH}" FAKE_BOOT_MOUNT_TARGET=/boot detect_boot_mount_target)"
[[ "${detected}" == "/boot" ]] || fail "independent /boot detection failed: ${detected}"
detected="$(PATH="${tmp_dir}/bin:${PATH}" FAKE_BOOT_MOUNT_TARGET=/ detect_boot_mount_target)"
[[ "${detected}" == "/" ]] || fail "root-filesystem /boot detection failed: ${detected}"

printf 'Debian reinstall GRUB tests passed\n'
