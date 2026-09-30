#!/usr/bin/env python3
"""Transient, bounded VLESS TCP/RAW REALITY producer. Requires Python 3.9+.

Run reviewed source via SSH stdin with CONFIG, or supply configuration on stdin.
Only the explicit all-public-clients mode is supported. No files are created.
"""
import base64
import hashlib
import ipaddress
import json
import os
import pathlib
import re
import selectors
import signal
import stat
import subprocess
import sys
import time
import urllib.parse
import uuid

VERSION = "1.0.0"
MAX_CONFIG = 2 * 1024 * 1024
MAX_LINKS = 1024 * 1024
MAX_ENVELOPE = 2 * MAX_LINKS
MAX_NODES = 1000
MAX_LINE = 16384
OPENSSL = "/usr/bin/openssl"
PKCS8_PREFIX = bytes.fromhex("302e020100300506032b656e04220420")
SPKI_PREFIX = bytes.fromhex("302a300506032b656e032100")
ERROR_CATEGORIES = frozenset({"config", "xray-config", "selection", "key-derivation", "format", "limit", "timeout"})
FINGERPRINTS = frozenset({"chrome", "firefox", "safari", "ios", "android", "edge", "random", "randomized"})


class ExportError(Exception):
    pass


def require(ok, category):
    if not ok:
        raise ExportError(category)


def domain(value, category):
    require(isinstance(value, str) and 0 < len(value) <= 253, category)
    value = value.lower()
    require(value != "localhost" and not value.endswith(".local"), category)
    require(all(re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", x) for x in value.split(".")), category)
    return value


def address(value, category="config"):
    require(isinstance(value, str) and 0 < len(value) <= 253, category)
    try:
        parsed = ipaddress.ip_address(value)
    except ValueError:
        require(":" not in value and not re.fullmatch(r"[0-9.]+", value), category)
        return domain(value, category)
    require(parsed.is_global and not parsed.is_multicast and not parsed.is_unspecified, category)
    require("%" not in value, category)
    return str(parsed)


def validate_config(config):
    """Pure validation; safe to call on the collector before opening SSH."""
    require(isinstance(config, dict), "config")
    require(set(config) <= {"schemaVersion", "selection", "configPath", "address", "fingerprint", "namePrefix"}, "config")
    require(type(config.get("schemaVersion")) is int and config["schemaVersion"] == 2, "config")
    require(config.get("selection") == "all-public-clients", "config")
    path = config.get("configPath")
    require(isinstance(path, str) and path.startswith("/") and len(path) <= 4096, "config")
    require(not any(ord(x) <= 32 or ord(x) == 127 for x in path) and "\\" not in path, "config")
    require(str(pathlib.PurePosixPath(path)) == path and ".." not in pathlib.PurePosixPath(path).parts, "config")
    host = address(config.get("address"))
    fingerprint = config.get("fingerprint", "chrome")
    require(isinstance(fingerprint, str) and fingerprint in FINGERPRINTS, "config")
    prefix = config.get("namePrefix", "Xray")
    require(isinstance(prefix, str) and 0 < len(prefix.encode()) <= 256, "config")
    require(not any(ord(x) < 32 or ord(x) == 127 for x in prefix), "config")
    return {**config, "address": host, "fingerprint": fingerprint, "namePrefix": prefix}


def strict_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "xray-config")
            result[key] = value
        return result
    try:
        return json.loads(raw, object_pairs_hook=pairs,
                          parse_constant=lambda _: (_ for _ in ()).throw(ExportError("xray-config")))
    except (ValueError, UnicodeError, RecursionError):
        raise ExportError("xray-config") from None


def file_signature(info):
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def read_snapshot(path):
    """Read one regular file, detecting in-place writes and atomic replacement."""
    try:
        before = path.lstat()
        require(stat.S_ISREG(before.st_mode) and 0 < before.st_size <= MAX_CONFIG, "xray-config")
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
        with os.fdopen(os.open(path, flags), "rb") as stream:
            opened = os.fstat(stream.fileno())
            require(stat.S_ISREG(opened.st_mode) and file_signature(opened) == file_signature(before), "xray-config")
            raw = stream.read(MAX_CONFIG + 1)
            require(file_signature(os.fstat(stream.fileno())) == file_signature(opened), "xray-config")
        require(len(raw) == opened.st_size and file_signature(path.lstat()) == file_signature(opened), "xray-config")
        return raw, file_signature(opened)
    except OSError:
        raise ExportError("xray-config") from None


def decode_key(value, category="key-derivation"):
    require(isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_-]{43}", value), category)
    try:
        raw = base64.b64decode(value + "=", altchars=b"-_", validate=True)
    except ValueError:
        raise ExportError(category) from None
    require(len(raw) == 32 and base64.urlsafe_b64encode(raw).decode().rstrip("=") == value, category)
    return raw


def derive_public_key(private_key):
    """Existing trusted OpenSSL receives a PKCS8 key on stdin, never argv/disk."""
    private_der = PKCS8_PREFIX + decode_key(private_key)
    process = None
    streams = selectors.DefaultSelector()
    output, error = bytearray(), bytearray()
    try:
        info = os.stat(OPENSSL)
        parent = os.stat(pathlib.Path(OPENSSL).parent)
        require(stat.S_ISREG(info.st_mode) and info.st_uid == 0 and not info.st_mode & 0o022 and info.st_mode & 0o111, "key-derivation")
        require(stat.S_ISDIR(parent.st_mode) and parent.st_uid == 0 and not parent.st_mode & 0o022, "key-derivation")
        process = subprocess.Popen([OPENSSL, "pkey", "-inform", "DER", "-pubout", "-outform", "DER"],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   env={"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C", "OPENSSL_CONF": "/dev/null"})
        # The fixed 48-byte input fits in an empty pipe. Reads are bounded even
        # when an unexpected OpenSSL failure produces excessive diagnostics.
        process.stdin.write(private_der)
        process.stdin.close()
        for pipe in (process.stdout, process.stderr):
            os.set_blocking(pipe.fileno(), False)
            streams.register(pipe, selectors.EVENT_READ)
        deadline = time.monotonic() + 5
        while streams.get_map():
            remaining = deadline - time.monotonic()
            require(remaining > 0, "key-derivation")
            for key, _ in streams.select(min(remaining, .25)):
                chunk = os.read(key.fileobj.fileno(), 4096)
                if not chunk:
                    streams.unregister(key.fileobj)
                    continue
                (output if key.fileobj is process.stdout else error).extend(chunk)
                require(len(output) <= 4096 and len(error) <= 4096, "key-derivation")
        require(process.wait(timeout=max(.01, deadline - time.monotonic())) == 0 and not error, "key-derivation")
        require(len(output) == len(SPKI_PREFIX) + 32 and output.startswith(SPKI_PREFIX), "key-derivation")
        public = bytes(output[len(SPKI_PREFIX):])
        require(public != bytes(32), "key-derivation")
        return base64.urlsafe_b64encode(public).decode().rstrip("=")
    except ExportError:
        raise
    except Exception:
        raise ExportError("key-derivation") from None
    finally:
        streams.close()
        if process is not None:
            if process.poll() is None:
                process.kill()
            process.wait()
            for pipe in (process.stdin, process.stdout, process.stderr):
                if not pipe.closed:
                    pipe.close()


def public_inbound(inbound, management_tags):
    require(isinstance(inbound, dict), "xray-config")
    tag = inbound.get("tag", "")
    require(isinstance(tag, str), "xray-config")
    if tag and tag in management_tags:
        return False
    listen = inbound.get("listen", "0.0.0.0")
    require(isinstance(listen, str), "xray-config")
    if listen in {"", "0.0.0.0", "::"}:
        return True
    if listen == "localhost" or listen.startswith(("/", "@")):
        return False
    try:
        value = ipaddress.ip_address(listen)
    except ValueError:
        raise ExportError("xray-config") from None
    return value.is_global and not value.is_multicast and "%" not in listen


def supported_transport(stream):
    require(isinstance(stream, dict), "xray-config")
    aliases = {"tcp": "tcp", "raw": "tcp"}
    network, method = stream.get("network"), stream.get("method")
    require(network is None or isinstance(network, str) and network in aliases, "selection")
    require(method is None or isinstance(method, str) and method in aliases, "selection")
    require(network is None or method is None or aliases[network] == aliases[method], "selection")
    require(stream.get("security") == "reality", "selection")
    allowed = {"network", "method", "security", "tcpSettings", "rawSettings", "realitySettings", "sockopt"}
    require(all(key in allowed or value in ({}, None) for key, value in stream.items()), "selection")
    for key in ("tcpSettings", "rawSettings"):
        value = stream.get(key, {})
        require(isinstance(value, dict) and set(value) <= {"header"}, "selection")
        header = value.get("header", {})
        require(header in ({}, {"type": "none"}), "selection")


def reality_parameters(reality, derive):
    require(isinstance(reality, dict), "xray-config")
    allowed = {"dest", "target", "xver", "show", "privateKey", "publicKey", "serverNames", "shortIds", "maxTimeDiff", "limitFallbackUpload", "limitFallbackDownload"}
    require(all(key in allowed or value in ({}, [], "", None) for key, value in reality.items()), "selection")
    if "dest" in reality and "target" in reality:
        require(reality["dest"] == reality["target"], "selection")
    names, ids = reality.get("serverNames"), reality.get("shortIds")
    require(isinstance(names, list) and 0 < len(names) <= MAX_NODES, "selection")
    server_name = sorted({domain(x, "selection") for x in names})[0]
    require(isinstance(ids, list) and 0 < len(ids) <= MAX_NODES, "selection")
    require(all(isinstance(x, str) and re.fullmatch(r"(?:[a-fA-F0-9]{2}){0,8}", x) for x in ids), "selection")
    nonempty = sorted({x.lower() for x in ids if x})
    short_id = nonempty[0] if nonempty else ""
    # Validate before calling an injected derivation function, too.
    decode_key(reality.get("privateKey"))
    public_key = derive(reality["privateKey"])
    decode_key(public_key)
    if "publicKey" in reality:
        decode_key(reality["publicKey"])
        require(reality["publicKey"] == public_key, "key-derivation")
    return server_name, public_key, short_id


def client_id(value, category="selection"):
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", value), category)
    identity = uuid.UUID(value)
    require(identity.int != 0, category)
    return str(identity)


def node_parameters(line):
    require(isinstance(line, str) and 0 < len(line.encode()) <= MAX_LINE, "format")
    require(not any(ord(c) <= 32 or ord(c) == 127 for c in line), "format")
    try:
        uri = urllib.parse.urlsplit(line)
        require(uri.scheme == "vless" and uri.password is None and bool(uri.fragment), "format")
        identity = client_id(urllib.parse.unquote(uri.username or ""), "format")
        host = address(uri.hostname, "format")
        port = uri.port
        require(isinstance(port, int) and 0 < port <= 65535, "format")
        pairs = urllib.parse.parse_qsl(uri.query, keep_blank_values=True, strict_parsing=True, max_num_fields=16)
        query = dict(pairs)
        require(len(query) == len(pairs) and set(query) == {"encryption", "security", "type", "flow", "sni", "fp", "pbk", "sid"}, "format")
        require(query["encryption"] == "none" and query["security"] == "reality" and query["type"] == "tcp", "format")
        require(query["flow"] in {"", "xtls-rprx-vision"} and query["fp"] in FINGERPRINTS, "format")
        domain(query["sni"], "format")
        decode_key(query["pbk"], "format")
        require(re.fullmatch(r"(?:[a-f0-9]{2}){0,8}", query["sid"]), "format")
        return {"uuid": identity, "server": host, "port": port, **query}
    except ExportError:
        raise
    except (ValueError, TypeError):
        raise ExportError("format") from None


def normalize(raw):
    require(isinstance(raw, bytes) and len(raw) <= MAX_LINKS, "limit")
    raw = raw.strip()
    if b"://" not in raw:
        try:
            raw = base64.b64decode(b"".join(raw.split()), validate=True)
        except ValueError:
            raise ExportError("format") from None
    try:
        lines = raw.decode("utf-8").splitlines()
    except UnicodeError:
        raise ExportError("format") from None
    require(0 < len(lines) <= MAX_NODES, "limit")
    for line in lines:
        node_parameters(line)
    require(len(set(lines)) == len(lines), "format")
    require(len(("\n".join(lines) + "\n").encode()) <= MAX_LINKS, "limit")
    return lines


def export(config, derive=derive_public_key):
    config = validate_config(config)
    path = pathlib.Path(config["configPath"])
    raw, signature = read_snapshot(path)
    document = strict_json(raw)
    require(isinstance(document, dict), "xray-config")
    inbounds = document.get("inbounds")
    require(isinstance(inbounds, list) and 0 < len(inbounds) <= MAX_NODES, "xray-config")
    management = set()
    for key in ("api", "metrics"):
        if key in document:
            require(isinstance(document[key], dict), "xray-config")
            if "tag" in document[key]:
                require(isinstance(document[key]["tag"], str), "xray-config")
                management.add(document[key]["tag"])
    selected = [x for x in inbounds if public_inbound(x, management)]
    require(bool(selected), "selection")
    for inbound in selected:
        require(type(inbound.get("port")) is int and 0 < inbound["port"] <= 65535, "selection")
    selected.sort(key=lambda x: (x["port"], x.get("tag", "")))
    require(len({x["port"] for x in selected}) == len(selected), "selection")
    lines = []
    host = config["address"]
    authority = "[" + host + "]" if ":" in host else host
    for inbound in selected:
        require(inbound.get("protocol") == "vless", "selection")
        settings = inbound.get("settings")
        require(isinstance(settings, dict), "xray-config")
        require(settings.get("decryption", "none") == "none", "selection")
        require(all(key in {"clients", "decryption"} or value in ({}, [], "", None) for key, value in settings.items()), "selection")
        supported_transport(inbound.get("streamSettings"))
        sni, public_key, sid = reality_parameters(inbound["streamSettings"].get("realitySettings"), derive)
        clients = settings.get("clients")
        require(isinstance(clients, list) and 0 < len(clients) <= MAX_NODES, "selection")
        chosen = []
        for client in clients:
            require(isinstance(client, dict), "selection")
            require(all(key in {"id", "flow", "email", "level"} or value in ({}, [], "", None) for key, value in client.items()), "selection")
            identity = client_id(client.get("id"))
            flow = client.get("flow", "")
            require(isinstance(flow, str) and flow in {"", "xtls-rprx-vision"}, "selection")
            chosen.append((identity, flow))
        require(len({x[0] for x in chosen}) == len(chosen), "selection")
        tag = inbound.get("tag") or "vless"
        require(len(tag.encode()) <= 256 and not any(ord(x) < 32 or ord(x) == 127 for x in tag), "selection")
        labels = [hashlib.sha256(identity.encode()).hexdigest()[:12] for identity, _ in chosen]
        require(len(set(labels)) == len(labels), "selection")
        for identity, flow in sorted(chosen):
            query = urllib.parse.urlencode({"encryption": "none", "security": "reality", "type": "tcp", "flow": flow,
                                           "sni": sni, "fp": config["fingerprint"], "pbk": public_key, "sid": sid},
                                          quote_via=urllib.parse.quote, safe="")
            label = hashlib.sha256(identity.encode()).hexdigest()[:12]
            name = f'{config["namePrefix"]} {tag}:{inbound["port"]} client-{label}'
            lines.append(f'vless://{urllib.parse.quote(identity, safe="")}@{authority}:{inbound["port"]}?{query}#{urllib.parse.quote(name, safe="")}')
            require(len(lines) <= MAX_NODES, "limit")
    links = "\n".join(lines) + "\n"
    normalize(links.encode())
    final_raw, final_signature = read_snapshot(path)
    require(final_signature == signature and final_raw == raw, "xray-config")
    return {"schemaVersion": 1, "exporterVersion": VERSION,
            "exportedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "expectedGroups": len(selected), "successfulGroups": len(selected),
            "nodeCount": len(lines), "bytes": len(links.encode()),
            "sha256": hashlib.sha256(links.encode()).hexdigest(), "links": links}


def main(config=None):
    try:
        if hasattr(signal, "alarm"):
            def timeout(*_):
                raise ExportError("timeout")
            signal.signal(signal.SIGALRM, timeout)
            signal.alarm(120)
        if config is None:
            raw = sys.stdin.buffer.read(65537)
            require(len(raw) <= 65536, "config")
            config = json.loads(raw)
        result = json.dumps(export(config), ensure_ascii=False) + "\n"
        require(len(result.encode()) <= MAX_ENVELOPE, "limit")
        sys.stdout.write(result)
        return 0
    except Exception as exc:
        category = str(exc) if isinstance(exc, ExportError) and str(exc) in ERROR_CATEGORIES else "config"
        sys.stderr.write("XRAY_EXPORT_ERROR " + category + "\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main(globals().get("CONFIG")))
