#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="${repo_root}/.tmp/po0-lan-worker-self-report-concurrency"
assets_dir="${tmp_dir}/assets"
bin_dir="${tmp_dir}/bin"
log_file="${tmp_dir}/server.log"
config_file="${tmp_dir}/targets.tsv"
port="$((18000 + ($$ % 20000)))"
webauth_port="$((port + 1))"

if command -v python3 >/dev/null 2>&1; then
    py=python3
elif command -v python >/dev/null 2>&1; then
    py=python
else
    printf 'python3/python is required for this test.\n' >&2
    exit 1
fi

rm -rf "${tmp_dir}"
mkdir -p "${assets_dir}" "${bin_dir}"

bash "${repo_root}/tools/po0/build-po0-assets.sh" "${assets_dir}" >/dev/null

cat > "${bin_dir}/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
host=""
for arg in "$@"; do
    case "${arg}" in
        *@slow-a.test|*@slow-b.test)
            host="${arg#*@}"
            ;;
    esac
done
case "${host}" in
    slow-a.test|slow-b.test)
        end=$((SECONDS + 2))
        while (( SECONDS < end )); do
            :
        done
        printf 'OK|client ip source updated\n'
        ;;
    *)
        printf 'unexpected ssh target: %s\n' "${host:-<none>}" >&2
        exit 2
        ;;
esac
EOF
chmod +x "${bin_dir}/ssh"

cat > "${bin_dir}/ssh.cmd" <<EOF
@echo off
ping -n 3 127.0.0.1 >nul
echo OK^|client ip source updated
exit /b 0
EOF

cat > "${config_file}" <<'EOF'
# enabled|label|source_key(optional if resource_token)|report_key|po0_host|po0_port|po0_user|po0_script|source_token|ssh_extra_args|resource_token|report_mode|ddns_domain|client_ip_token|client_ip_source|client_ip_ttl|webauth_token|webauth_source|webauth_ttl|report_ssh_extra_args
1|SlowA|||slow-a.test|22|root|/root/nftables-relay-manager.sh||||none||token-a|self-report|43200|webauth-a|cf-access|43200|
1|SlowB|||slow-b.test|22|root|/root/nftables-relay-manager.sh||||none||token-b|self-report|43200|webauth-b|cf-access|43200|
EOF

PATH="${bin_dir}:${PATH}" bash "${assets_dir}/po0-lan-client.sh" \
    --config "${config_file}" \
    --self-report-server \
    --self-report-listen "127.0.0.1:${port}" \
    --self-report-secret "test-secret" > "${log_file}" 2>&1 &
server_pid=$!

cleanup() {
    kill "${server_pid}" >/dev/null 2>&1 || true
    wait "${server_pid}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in $(seq 1 50); do
    if curl -fsS --max-time 1 "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

curl -fsS --max-time 1 "http://127.0.0.1:${port}/health" >/dev/null

start="$("${py}" -c 'import time; print(time.monotonic())')"
body="$(curl -fsS --max-time 10 "http://127.0.0.1:${port}/report?source=device-a&ip=220.191.185.210&identity=device-a&token=test-secret")"
elapsed_ms="$("${py}" - "${start}" <<'PY'
import sys
import time

start = float(sys.argv[1])
print(int((time.monotonic() - start) * 1000))
PY
)"

printf '%s\n' "${body}"
printf 'elapsed_ms=%s\n' "${elapsed_ms}"

case "${body}" in
    *"targets=2"*) ;;
    *)
        printf 'expected response to report two successful targets\n' >&2
        cat "${log_file}" >&2
        exit 1
        ;;
esac

if [[ "${elapsed_ms}" -ge 3200 ]]; then
    printf 'expected concurrent reporting to finish below 3200 ms, got %s ms\n' "${elapsed_ms}" >&2
    cat "${log_file}" >&2
    exit 1
fi

cleanup

PATH="${bin_dir}:${PATH}" bash "${assets_dir}/po0-lan-client.sh" \
    --config "${config_file}" \
    --webauth-server \
    --listen "127.0.0.1:${webauth_port}" > "${log_file}" 2>&1 &
server_pid=$!

for _ in $(seq 1 50); do
    if curl -fsS --max-time 1 "http://127.0.0.1:${webauth_port}/health" >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

curl -fsS --max-time 1 "http://127.0.0.1:${webauth_port}/health" >/dev/null

start="$("${py}" -c 'import time; print(time.monotonic())')"
body="$(curl -fsS --max-time 10 \
    -H "CF-Connecting-IP: 220.191.185.210" \
    -H "CF-Access-Authenticated-User-Email: device-a@example.com" \
    "http://127.0.0.1:${webauth_port}/auth")"
elapsed_ms="$("${py}" - "${start}" <<'PY'
import sys
import time

start = float(sys.argv[1])
print(int((time.monotonic() - start) * 1000))
PY
)"

printf '%s\n' "${body}"
printf 'webauth_elapsed_ms=%s\n' "${elapsed_ms}"

case "${body}" in
    *"PO0 WebAuth OK"*cf-access@slow-a.test*cf-access@slow-b.test*) ;;
    *)
        printf 'expected WebAuth response to report two successful targets\n' >&2
        cat "${log_file}" >&2
        exit 1
        ;;
esac

if [[ "${elapsed_ms}" -ge 3200 ]]; then
    printf 'expected concurrent WebAuth reporting to finish below 3200 ms, got %s ms\n' "${elapsed_ms}" >&2
    cat "${log_file}" >&2
    exit 1
fi
