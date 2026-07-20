#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_file="${repo_root}/scripts/po0/relay/lan-worker/src/180-self-report-server.sh"

if command -v python3 >/dev/null 2>&1; then
    python_bin="python3"
elif command -v python >/dev/null 2>&1; then
    python_bin="python"
else
    printf 'python3/python is required for LAN Worker Stash report tests.\n' >&2
    exit 1
fi

"${python_bin}" - "${source_file}" <<'PY'
import json
import os
import pathlib
import shlex
import sys
import threading
import time
import urllib.error
import urllib.request

source_path = pathlib.Path(sys.argv[1])
text = source_path.read_text(encoding="utf-8")
marker = '<<\'PY\'\n'
start = text.index(marker) + len(marker)
end = text.index('\nPY\n}', start)
server_code = text[start:end]
server_code = server_code.rsplit("\nwith socketserver.ThreadingTCPServer", 1)[0]

old_argv = sys.argv[:]
old_targets = os.environ.get("PO0_SELF_REPORT_TARGETS")
old_secret = os.environ.get("SELF_REPORT_SECRET")
os.environ["PO0_SELF_REPORT_TARGETS"] = "self-report|po0.example|22|root|/root/nftables-relay-manager.sh|manager-token|43200|"
os.environ["SELF_REPORT_SECRET"] = "test-secret"
sys.argv = [str(source_path), "127.0.0.1", "0"]
namespace = {"__name__": "po0_lan_stash_report_test", "__file__": str(source_path)}
try:
    exec(compile(server_code, str(source_path), "exec"), namespace)
finally:
    sys.argv = old_argv

captured_commands = []
real_subprocess_run = namespace["subprocess"].run

class Completed:
    returncode = 0
    stdout = ""
    stderr = ""

def fake_subprocess_run(command, **kwargs):
    captured_commands.append(command)
    return Completed()

namespace["subprocess"].run = fake_subprocess_run
try:
    namespace["report_target"](namespace["TARGETS"][0], "8.8.8.8", "stash-ios", "stash-ios", 24)
finally:
    namespace["subprocess"].run = real_subprocess_run
assert captured_commands, "report_target did not invoke SSH"
remote_command = captured_commands[0][-1]
assert shlex.split(remote_command)[-1] == "24", remote_command

report_calls = []
def fake_report_all(ip, identity, source_override, cidr_prefix=None):
    report_calls.append((ip, identity, source_override, cidr_prefix))
    return [namespace["target_label"](namespace["TARGETS"][0], source_override)], []

namespace["report_all"] = fake_report_all
server = namespace["socketserver"].ThreadingTCPServer(("127.0.0.1", 0), namespace["Handler"])
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
base_url = "http://127.0.0.1:%d" % server.server_address[1]

def request(path, payload=None, auth=True, method=None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {}
    if payload is not None:
        headers["Content-Type"] = "application/json"
    if auth:
        headers["Authorization"] = "Bearer test-secret"
    req = urllib.request.Request(base_url + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, response.read().decode("utf-8"), response.headers.get("Content-Type", "")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8"), exc.headers.get("Content-Type", "")

try:
    now = int(time.time())
    wifi_payload = {
        "source_id": "stash-ios",
        "ip": "8.8.8.8",
        "network": "wifi",
        "observed_at": now,
        "request_id": "wifi-0001",
    }
    status, body, content_type = request("/stash-report/v1", wifi_payload)
    parsed = json.loads(body)
    assert status == 200 and content_type.startswith("application/json"), (status, body)
    assert parsed["ok"] is True and parsed["accepted_cidr"] == "8.8.8.8/32", parsed
    assert parsed["targets"] == [{"name": "stash-ios@po0.example", "ok": True}], parsed
    assert report_calls[-1][-1] == 32, report_calls[-1]

    cellular_payload = dict(wifi_payload, ip="8.8.8.99", network="cellular", request_id="cell-0001")
    status, body, _ = request("/stash-report/v1", cellular_payload)
    parsed = json.loads(body)
    assert status == 200 and parsed["accepted_cidr"] == "8.8.8.0/24", (status, parsed)
    assert report_calls[-1][-1] == 24, report_calls[-1]

    status, body, _ = request("/stash-report/v1", cellular_payload)
    assert status == 409 and json.loads(body)["error"] == "duplicate_request", (status, body)

    status, body, _ = request("/stash-report/v1", dict(wifi_payload, request_id="stale-0001", observed_at=now - 601))
    assert status == 400 and json.loads(body)["error"] == "stale_observation", (status, body)

    status, body, _ = request("/stash-report/v1", dict(wifi_payload, request_id="bad-ip-0001", ip=1234))
    assert status == 400 and json.loads(body)["error"] == "invalid_public_ipv4", (status, body)

    status, body, _ = request("/stash-report/v1", dict(wifi_payload, request_id="bad-time-0001", observed_at="nan"))
    assert status == 400 and json.loads(body)["error"] == "invalid_observed_at", (status, body)

    status, body, _ = request("/stash-report/v1", dict(wifi_payload, request_id="auth-0001"), auth=False)
    assert status == 401 and json.loads(body)["error"] == "unauthorized", (status, body)

    status, body, _ = request("/stash-report/v1", method="GET")
    assert status == 405 and json.loads(body)["error"] == "method_not_allowed", (status, body)

    status, body, content_type = request("/report?token=test-secret&ip=8.8.4.4&source=legacy", auth=False)
    assert status == 200 and content_type.startswith("text/plain") and body.startswith("OK 8.8.4.4;"), (status, body)
    assert report_calls[-1][-1] is None, report_calls[-1]
finally:
    server.shutdown()
    server.server_close()
    if old_targets is None:
        os.environ.pop("PO0_SELF_REPORT_TARGETS", None)
    else:
        os.environ["PO0_SELF_REPORT_TARGETS"] = old_targets
    if old_secret is None:
        os.environ.pop("SELF_REPORT_SECRET", None)
    else:
        os.environ["SELF_REPORT_SECRET"] = old_secret

print("LAN Worker Stash report tests passed.")
PY
