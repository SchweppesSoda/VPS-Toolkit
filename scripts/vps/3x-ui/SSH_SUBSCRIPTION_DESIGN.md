# Transient SSH subscription export

Implementation: `3x-ui-subscription-exporter.py` 1.0.0. The original Bash 1.2.0
ZIP exporter and Windows helper retain their existing behavior. A separate Python
entry point avoids embedding another file-based recovery path in the daily job.

## Execution

The collector sends a reviewed, SHA-256-pinned Python source and a separate JSON
configuration over SSH stdin. A fixed Python bootstrap reads at most 256 KiB,
parses `{code, config}`, and executes the code with `CONFIG` set to that object.
Private configuration is never interpolated into code or command-line arguments.
Use `python3 -I -B` to avoid import-path overrides and bytecode files.

The existing SSH user/key is reused. The collector pins the existing host key,
disables agent, PTY and forwarding requests, and bounds the SSH process. These
client settings do not reduce the account's server-side administrator privileges.
An encrypted desktop key may be unlocked during provisioning; its automation copy
must remain in protected collector credentials, inaccessible to HTTP containers.

Private config has `database` (absolute SQLite path), `address` (outward host), and
`clientIds` (explicit nonempty list of existing VLESS/VMess UUIDs or Trojan passwords).
Other protocols or database layouts fail closed. No default export-all selection.

## Producer behavior

- Read SQLite through a read-only connection and copy a consistent snapshot to
  `:memory:`. No snapshot, script, request body or response file is written on VPS.
- Select active, unexpired inbound clients by identity. Removed/disabled members
  may reduce a nonempty selection. A completely empty selection fails.
- Read the panel's subscription listener on loopback, using its configured TLS
  mode, port and path. Do not follow redirects or environment proxies. Loopback
  TLS uses the local host trust boundary, as the original curl `-k` export did.
- Reuse native node rendering, including REALITY and transport parameters.
  Reject shared groups containing unselected identities and require the native
  output to match every selected active inbound/client pair. Native rendering
  may itself update the panel's normal subscription-access metadata.
- Every selected group must succeed. Validate URI structure and identities;
  deduplicate exact lines while preserving order. Reject HTML, error JSON, empty,
  partial, unrelated-client and unsupported-protocol output.
- Require existing Python 3.9+ and standard-library SQLite/TLS support. Never
  install dependencies, download scripts, self-update or create a remote timer.
- Producer timeout 120 seconds; responses/node text at most 1 MiB, 1,000 nodes,
  16 KiB per line. Receiver envelope limit 2 MiB. SSH exit must be zero.

## Response

Success writes one UTF-8 JSON object followed by a newline. Fields:
`schemaVersion: 1`, `exporterVersion`, `exportedAt` (UTC), `expectedGroups`,
`successfulGroups`, `nodeCount`, `bytes`, `sha256`, and `links`.
`links` contains LF-separated URIs with exactly one final LF. Counts, byte length,
digest and producer version are checked by the receiver before publication.
No database, panel password, SSH key or subId field is transmitted; node URIs
themselves are credentials and must remain private.

Failure exits nonzero and emits only `3XUI_EXPORT_ERROR <category>` to stderr.
Interrupted or partial transmissions are discarded. Raw exceptions, URLs and
response bodies never enter routine collector logs.

## Cleanup

No persistent exporter artifacts are created on VPS. Normal SSH/authentication,
system audit and panel logs are preserved, as agreed for this implementation.
This is file-free execution, not a claim of trace-free execution or secure erasure
of memory, swap, snapshots or provider records.

## Checks

`python -B tools/vps/test_3x_ui_subscription_exporter.py` covers native preservation,
snapshot consistency, partial groups, removed/disabled clients, selection leakage,
malformed responses, limits and stderr redaction. Collector integration adds
transport timeout/overflow, atomic versions, failed-slot deduplication and cache
visibility tests. Instance details and deployment records belong to the deployment
repository; never put real configuration or nodes in fixtures.
