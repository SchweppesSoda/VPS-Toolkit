# SSH subscription export contract

Status: design only, 2026-09-14. The CLI and server entry points below are
proposed; exporter 1.2.0 does not implement them. Existing interactive and
Windows ZIP exports keep their current behavior.

## Purpose and ownership

Provide bounded, non-interactive node exports to a trusted collector. The VPS
supplies node data; the collector owns scheduling, validation, cached HTTP
delivery and subscription-manager integration. No public subscription listener
or permanent SSH tunnel is required on the VPS.

This public repository owns the reusable exporter and restricted server entry.
Instance addresses, client/subscription selectors, keys and collected nodes
belong only in private runtime configuration. The deployment repository owns
the collector lifecycle and subscription-manager integration.

## Proposed producer

Add `--subscription-json` to `3x-ui-node-exporter.sh`, sharing existing SQLite
snapshot and local subscription-reading helpers. This differs from `--stream`,
which transfers a ZIP containing a database snapshot.

- Read a consistent SQLite snapshot; never edit the live database. Keep
  intermediate data in a private temporary directory, cleaned on success,
  failure and handled signals. SIGKILL/power-loss cleanup remains best effort;
  stale-session cleanup must verify ownership and paths.
- A root-owned instance configuration selects the intended active inbound
  clients and subscription groups. Export all and only that selection. Missing
  selectors, empty selection or any failed group reject the attempt.
- Reuse the panel's local subscription renderer. Do not reconstruct private
  protocol settings using guessed defaults. Validate the outward address and
  preserve SNI, transport and REALITY fields.
- Require every expected group to succeed. Reject HTML/JSON errors, invalid
  node URIs, empty output and unsupported protocols. A partial fetch must never
  silently become a smaller valid subscription.
- Deduplicate exact URI lines while preserving order and names. Decreased node
  count is allowed if every selected group succeeded; deliberate empty-service
  retirement is an explicit operation.
- No prompts, package installation, script download or self-update during
  collection. Run the installed, reviewed version with preflighted dependencies.
- Validate before stdout. Sanitized stderr must exclude raw curl errors,
  subIds, request URLs, node lines and private paths.
- Initial limits: 120 seconds total, 1 MiB normalized node text, 1,000 nodes,
  16 KiB per URI line. Raising limits requires a reviewed instance change.

## Transport schema

Success exits 0 and writes exactly one UTF-8 JSON object plus a final newline:

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Integer `1` |
| `exporterVersion` | Installed exporter version |
| `exportedAt` | UTC RFC 3339 diagnostic timestamp |
| `expectedGroups` | Positive count of selected active subscription groups |
| `successfulGroups` | Must equal `expectedGroups` |
| `nodeCount` | Positive count after deduplication |
| `bytes` | Exact UTF-8 byte length of `links` |
| `sha256` | SHA-256 of those exact bytes |
| `links` | LF-separated URI lines with one final LF |

No database, private-key, panel-password or subId fields are included. Node
URIs themselves contain credentials and remain sensitive. Receivers bound the
envelope to 2 MiB, validate schema/counts/length/digest and require SSH exit 0.
The digest detects data errors; SSH and pinned host keys establish identity.

Failures detected before transmission exit nonzero with no data on stdout.
Interrupted transmissions may be partial and must be discarded by the receiver.
Stable error classes cover config, database, selection, fetch, format, limit and
cleanup failures; receivers never copy untrusted error bodies into routine logs.

## Restricted SSH entry

Use a dedicated export account and one dedicated key per collector. The account
has a valid shell for OpenSSH's forced command, but the credential permits no
interactive session, PTY, agent/X11 forwarding, TCP forwarding or password
login. Existing administrator login policy is preserved.

The authorized key uses `restrict` and a root-owned forced-command dispatcher.
It accepts only the exact request token `export-v1`; other commands, empty
requests and SFTP/SCP are rejected. It never evaluates or passes through
`SSH_ORIGINAL_COMMAND`.

For root-only databases, grant one exact sudo command: a fixed root-owned export
entry with **no arguments**, no `SETENV`, and a controlled environment. It reads
a fixed root-owned config and calls `--subscription-json`. Caller-selected
paths, URLs, selectors and shell fragments are forbidden. Database permissions
remain intact. The unprivileged dispatcher checks the request before sudo.

Keep the dedicated private key only on the collector. Install its public key
and the dispatcher once through existing admin access. Pin the VPS host key
using a trusted verification path; keyscan alone is not verification. Verify
the restrictions against the deployed OpenSSH version before enabling timers.

## Implementation and validation

Add the mode, dispatcher/installer and regression tests; bump the exporter
version when behavior changes. Keep both existing ZIP regression suites.
New tests cover complete/partial fetches, disabled or missing clients, malformed
output, bounds, snapshot consistency, signal/disconnect cleanup and redaction.
Linux integration must test actual sshd/authorized_keys/sudo enforcement,
including rejected arbitrary commands, arguments, SFTP and forwarding.

Reference: [OpenSSH authorized key options](https://man.openbsd.org/sshd.8).
