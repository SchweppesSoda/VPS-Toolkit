# Xray transient subscription export

[`xray-subscription-exporter.py`](xray-subscription-exporter.py) reads an existing
Xray JSON configuration in memory and exports all clients of public VLESS
TCP/RAW REALITY inbounds. This also supports an agent-managed Xray configuration
when its file has this shape; it does not call or change the agent.

The collector sends reviewed, SHA-256-pinned source and a separate private JSON
configuration over SSH stdin, using `python3 -I -B`. No script, private key,
snapshot or output is written on the VPS. Existing Python 3.9+ and the trusted
root-owned `/usr/bin/openssl` with X25519 support are required; dependencies are
never installed. Authentication and system audit logs remain intact.

Private collector configuration:

```json
{
  "schemaVersion": 2,
  "selection": "all-public-clients",
  "configPath": "/usr/local/etc/xray/config.json",
  "address": "nodes.example.com",
  "fingerprint": "chrome",
  "namePrefix": "DMIT_PRO"
}
```

The mode and schema are mandatory. `address` is the public host used by clients,
not the inbound's wildcard `listen`. `fingerprint` is a client choice, defaulting
to `chrome`; it is not inferred from server settings. `namePrefix` defaults to
`Xray`. The old `database` and `clientIds` fields are rejected. The original
[3x-ui producer](../3x-ui/SSH_SUBSCRIPTION_DESIGN.md) retains its separate schema
and behavior; changing source requires a reviewed collector migration.

Selection includes omitted/wildcard `listen` and globally routable IP listeners.
Loopback, private/reserved listeners, Unix sockets, and explicitly tagged Xray
API/metrics inbounds are excluded. An unsupported public inbound fails the whole
export. This first implementation only supports VLESS, TCP or its equivalent
RAW spelling, REALITY, and empty flow or `xtls-rprx-vision`. Nontrivial TCP headers,
FinalMask, VLESS Encryption and unsupported wire settings fail closed. It does
not reinterpret `method: xhttp` as default TCP.

All selected clients need distinct nonzero canonical UUIDs within their inbound.
No fixed identity list is used. Empty/malformed clients, unsupported settings,
bad or duplicate-key JSON, missing REALITY fields, mismatched public keys and a
changing configuration all fail without partial stdout. See the
[implementation contract](SSH_SUBSCRIPTION_DESIGN.md) for exact selection,
REALITY choices, limits and response format.

Checks use synthetic configurations only:

```text
python -B tools/vps/test_xray_subscription_exporter.py
python -B tools/vps/test_3x_ui_subscription_exporter.py
```

OpenSSL and full transient CLI checks require Linux. Collector publication and
conversion checks belong to its deployment repository; a successful conversion
does not demonstrate that a real client authenticated to the server.
