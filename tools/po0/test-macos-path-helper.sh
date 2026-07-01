#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/bin:/bin:${PATH:-}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/macos/src/010-core-string-path-config.sh"
# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/macos/src/040-prompt-and-input-helpers.sh"
# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/macos/src/080-install-and-upgrade.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_file_contains() {
    local file="$1" expected="$2"
    grep -Fqx "${expected}" "${file}" || fail "missing line in ${file}: ${expected}"
}

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/po0-macos-path-test.XXXXXX")"
trap 'rm -rf "${tmp_root}"' EXIT

HOME="${tmp_root}/home"
mkdir -p "${HOME}"
dest="${HOME}/.local/bin/po0-outbound-ip-report"
install_dir="${HOME}/.local/bin"
profile="${HOME}/.zprofile"

PATH="/usr/bin:/bin"
if path_dir_in_path "${install_dir}"; then
    fail "path_dir_in_path matched a missing PATH entry"
fi

PATH="/usr/bin:${install_dir}:/bin"
path_dir_in_path "${install_dir}" || fail "path_dir_in_path did not match exact PATH entry"

expected_line='export PATH="$HOME/.local/bin:$PATH"'
actual_line="$(shell_path_export_line "${install_dir}")"
[[ "${actual_line}" == "${expected_line}" ]] || fail "unexpected export line: ${actual_line}"

append_shell_path_profile "${profile}" "${install_dir}" || fail "append_shell_path_profile failed"
append_shell_path_profile "${profile}" "${install_dir}" || fail "append_shell_path_profile was not idempotent"
line_count="$(grep -Fc "${expected_line}" "${profile}")"
[[ "${line_count}" == "1" ]] || fail "expected one PATH export line, got ${line_count}"
assert_file_contains "${profile}" "${expected_line}"

rm -f "${profile}"
PATH="/usr/bin:/bin"
ensure_install_path_visible "${dest}" "0" >/tmp/po0-macos-path-helper.out 2>"${tmp_root}/noninteractive.err"
[[ ! -e "${profile}" ]] || fail "non-interactive guidance should not write ${profile}"
grep -Fq "${install_dir}" "${tmp_root}/noninteractive.err" || fail "non-interactive guidance did not mention install dir"

prompt_yes_no() {
    return 0
}

ensure_install_path_visible "${dest}" "1" >/tmp/po0-macos-path-helper.out 2>"${tmp_root}/interactive.err"
assert_file_contains "${profile}" "${expected_line}"
grep -Fq "已写入 PATH 配置" "${tmp_root}/interactive.err" || fail "interactive guidance did not confirm profile update"

printf 'macOS PATH helper tests passed.\n'
