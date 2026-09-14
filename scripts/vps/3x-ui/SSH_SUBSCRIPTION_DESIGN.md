# SSH subscription export contract

Status: design only, 2026-09-14. The CLI and server entry points below are
proposed; exporter 1.2.0 does not implement them. Existing interactive and
Windows ZIP exports keep their current behavior.

## Purpose and ownership

Provide bounded, non-interactive node exports to a trusted collector. The VPS
supplies node data; the collector owns scheduling, validation, cached HTTP
delivery and subscription-manager integration. No public subscription listener
or permanent SSH tunnel is required on the VPS.

This public repository owns the reusable exporter and transient execution protocol.
Instance addresses, client/subscription selectors, keys and collected nodes
belong only in private runtime configuration. The deployment repository owns
the collector lifecycle and subscription-manager integration.

## Proposed producer

Add `--subscription-json` to `3x-ui-node-exporter.sh`, sharing existing SQLite
snapshot and local subscription-reading helpers. This differs from `--stream`,
which transfers a ZIP containing a database snapshot.

- Read a consistent SQLite snapshot in memory; never edit the live database.
  Keep intermediate responses in memory. If a file is unavoidable, use a verified
  tmpfs private directory, clean it on completion and handled signals, and reject
  persistent-disk fallback. tmpfs is not a secure-erasure guarantee against swap,
  crash dumps or host snapshots. Recover owned leftovers after an interrupted run.
- A collector-owned instance configuration selects the intended active inbound
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
- No prompts, package installation, internet script download or self-update during
  collection. Send the collector's reviewed, pinned exporter through SSH and run
  it in memory with preflighted dependencies; leave no installed script on the VPS.
- Validate before stdout. Sanitized stderr must exclude raw curl errors,
  subIds, request URLs, node lines and private paths.
- Initial limits: 120 seconds total, 1 MiB normalized node text, 1,000 nodes,
  16 KiB per URI line. Raising limits requires a reviewed instance change.

## Transport schema

Success exits 0 and writes exactly one UTF-8 JSON object plus a final newline:

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Integer `1` |
| `exporterVersion` | Collector-pinned exporter version |
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

## Existing SSH identity and transient execution

Reuse the instance owner's existing SSH user and key. Do not create an export
account, add an authorized key, install a dispatcher, or change sudo/sshd policy.
The key retains its existing account privileges; disabling PTY and forwarding in
the collector is a client-side choice, not a server-enforced privilege boundary.

Store the reviewed exporter and instance configuration on the collector. A fixed
bootstrap receives bounded, separate code/config inputs over SSH stdin and an
anonymous inherited descriptor, runs the exporter without writing a script file,
and returns the existing JSON protocol. Do not concatenate private config into
executable shell strings or command-line arguments. Installed Bash/Python/curl
dependencies are checked in advance; a missing dependency fails the run.

The scheduler needs access to the existing key and, if required, its passphrase.
Provide them through protected collector credentials, never argv, general logs or
HTTP containers. Do not depend on an interactive desktop SSH agent being online.
Pin the VPS host key using a trusted verification path; keyscan is not verification.

## Cleanup and system-log limits

Leave no exporter installation, instance configuration or retained export files
on the VPS. Exporter-generated temporary logs are avoided or cleaned with its
private session. The collector retains its own sanitized outcome and node cache.

System SSH/authentication/audit logs are separate from exporter artifacts. An
instance request to remove this run's records requires inspecting the actual log
backends and proving an exact scope, including records emitted after disconnect.
Do not silently substitute whole-file/shared-journal deletion or stop auditing
to meet that request. journalctl vacuum acts on archived journal files, not a
single SSH session. If exact cleanup is unavailable, report that requirement as
unmet; do not claim a trace-free run or silently change the user's requirement.
Remote log copies, swap, snapshots and provider-side records are outside local
file cleanup. No system-log mutation is implemented or executed by this design.

## Implementation and validation

Add the mode, transient execution support and regression tests; bump the exporter
version when behavior changes. Keep both existing ZIP regression suites.
New tests cover complete/partial fetches, disabled or missing clients, malformed
output, bounds, snapshot consistency, signal/disconnect cleanup and redaction.
Linux integration must verify existing-key authentication, passphrase handling,
no PTY/forwarding requested, bounded stdin/config delivery and no retained script
or export files. Do not test or advertise server-enforced key restrictions that
this design no longer configures. System-log cleanup remains a separate preflight.

References: [OpenSSH remote execution](https://man.openbsd.org/ssh),
[journalctl retention semantics](https://www.freedesktop.org/software/systemd/man/255/journalctl.html).
