# Xray JSON transient producer contract

Implementation: `xray-subscription-exporter.py` 1.0.0. It is a separate producer
from the SQLite/native-subscription [3x-ui exporter](../3x-ui/SSH_SUBSCRIPTION_DESIGN.md).
Private configuration uses schema 2 and explicit `selection: all-public-clients`;
the success envelope remains schema 1, for the existing collector transaction.
See [README.md](README.md) for the collector configuration and scope.

## Consistency and selection

The configured absolute `configPath` is read as a bounded regular nonsymlink
file, with inode/device, size, mtime and ctime checked before/after reading.
After all selected inbounds render, the current path is read again. Both content
and metadata must match, including the current path's inode after an atomic
replacement. This is a consistent-file export, not proof that the currently
running Xray process has loaded those bytes. Agent reload/rotation needs its
own deployment validation. JSON comments, NaN and duplicate keys are rejected.

Missing/wildcard `listen` selects a public inbound. Private/reserved/loopback IP
listeners and Unix sockets are excluded. `api.tag` and `metrics.tag` explicitly
identify internal management inbounds. Unknown listener formats fail instead
of being guessed. Every remaining inbound must be supported and have valid
clients; exporting only a successful subset is prohibited.

This scope accepts only VLESS with decryption `none`, TCP/RAW without a nontrivial
header, and REALITY. Legacy `network` and newer `method` must describe TCP/RAW
and agree when both exist; omission uses Xray's TCP/RAW default. Unsupported
nonempty transport, FinalMask, encryption or client options are rejected.
Server socket options and non-wire client metadata (`email`, `level`) are not
client subscription parameters. Email is not used for naming.

Inbounds sort by port/tag; overlapping selected ports are rejected. Clients sort
by canonical UUID, with duplicate identities rejected within an inbound.
Node names use configured prefix, inbound tag/port and the first 12 SHA-256 hex
characters of the UUID. A hash collision fails. Adding/removing another client
does not rename an existing client. URI query and fragment values are fully
percent encoded; IPv6 addresses use brackets. Each client preserves its own
empty or `xtls-rprx-vision` flow.

## REALITY and dependency boundary

Validate every `serverNames` and `shortIds` member. Choose the lexicographically
first lower-case exact DNS server name; wildcards and malformed names fail.
Choose the lexicographically first lower-case nonempty short ID, or empty only
when every configured ID is empty. Short IDs must be even-length hex, at most
16 characters. This deterministic policy emits one node per inbound/client,
rather than multiplying nodes for every accepted SNI or short ID.

Decode the canonical unpadded base64url 32-byte server `privateKey` only on the
VPS. Wrap it in the RFC 8410 X25519 PKCS8 DER structure and send those 48 bytes
through stdin to the fixed `/usr/bin/openssl pkey -inform DER -pubout -outform DER`.
Require a root-owned, executable, non-group/world-writable regular binary and
trusted parent. Use a minimal environment and `OPENSSL_CONF=/dev/null`.
The key never enters argv, an environment variable, a file or diagnostic output.
Require the exact X25519 SubjectPublicKeyInfo DER prefix and 32-byte public key.
When the server configuration also contains `publicKey`, validate its canonical
format and equality to the newly derived value; a stale public key fails.

No cryptography package, manual X25519 arithmetic, automatic dependency install
or agent token is used. OpenSSL timeout is five seconds, each output stream is
limited to 4 KiB, and its raw diagnostics are discarded. This protects output
secrecy; it does not claim erasure from swap, process memory or system snapshots.

`fingerprint` is the collector's explicit client setting (default `chrome`),
with a small supported set validated by the producer. Necessary parameters are
`encryption=none`, `security=reality`, `type=tcp`, `flow`, `sni`, `fp`, `pbk`, `sid`.
The normalizer validates this exact shape before envelope acceptance.

## Envelope and failure

Success emits one UTF-8 JSON object and one newline: `schemaVersion: 1`,
`exporterVersion`, UTC `exportedAt`, `expectedGroups`, `successfulGroups`,
`nodeCount`, `bytes`, `sha256`, and `links`. A group is a selected public inbound.
Every group must succeed. `links` contains LF-separated URIs and one final LF;
the collector checks counts, digest, exact normalized bytes and pinned version.

Private configuration input is limited to 64 KiB; Xray configuration to 2 MiB;
node text to 1 MiB, 1,000 nodes and 16 KiB per URI; envelope to 2 MiB. The producer
has a 120-second wall-clock alarm on Linux. No persistent remote state is created.

Failure writes no stdout and exits nonzero, with exactly
`XRAY_EXPORT_ERROR <category>` on stderr. Categories are `config`, `xray-config`,
`selection`, `key-derivation`, `format`, `limit`, `timeout`. The collector must
whitelist exact complete error lines and suppress all other SSH diagnostics.

## Verification

[`test_xray_subscription_exporter.py`](../../../tools/vps/test_xray_subscription_exporter.py)
uses six synthetic UUIDs, RFC 7748 keys and a loopback tunnel. It covers all-client
selection, encoding, stable names/order, multi-SNI/short-ID policy, file changes
and replacement, rejected public transports, missing/bad keys, envelope bounds
and redacted CLI failures. The OpenSSL vector and transient success CLI run on
Linux; pure rendering and validation also run on Windows. The original 3x-ui
tests remain independent. Formal deployment additionally validates the pinned
collector, conversion semantics, last-known-good and existing Linux/container
release gates.
