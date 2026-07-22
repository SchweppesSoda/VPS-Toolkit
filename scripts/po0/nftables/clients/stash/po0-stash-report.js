const STORE_KEY = "proxyconfig.po0.stash-report.v1";
const FORCE_LOCK_KEY = `${STORE_KEY}.force-lock`;
const NETWORK_GROUP = "📡 PO0 网络识别（自动）";
const FORCE_URL = "http://po0-report.invalid/report-now";

function readJSON(key, fallback) {
  try { return JSON.parse($persistentStore.read(key) || "null") || fallback; }
  catch (_) { return fallback; }
}

function writeJSON(key, value) {
  return $persistentStore.write(JSON.stringify(value), key);
}

function epochSeconds(value, fallback) {
  const numeric = Number(value);
  if (Number.isFinite(numeric) && numeric > 0) return numeric;
  const parsed = Date.parse(String(value || ""));
  return Number.isFinite(parsed) ? Math.floor(parsed / 1000) : fallback;
}

function parseArgument() {
  try { return JSON.parse($argument || "{}"); }
  catch (_) { return {}; }
}

function request(method, options) {
  return new Promise((resolve, reject) => {
    $httpClient[method](options, (error, response, data) => {
      if (error) reject(new Error(String(error)));
      else resolve({ response: response || {}, data: data || "" });
    });
  });
}

function selectedHeaders(proxy) {
  return {
    "User-Agent": "ProxyConfig-Stash-PO0/1.0",
    "X-Stash-Selected-Proxy": encodeURIComponent(proxy),
  };
}

async function detectNetwork() {
  try {
    await request("get", {
      url: "https://www.gstatic.com/generate_204",
      headers: selectedHeaders(NETWORK_GROUP),
      timeout: 5,
    });
    return "wifi";
  } catch (_) {
    return "unknown";
  }
}

async function detectIPv4() {
  const probes = [
    ["https://api.ipify.org?format=json", (body) => JSON.parse(body).ip],
    ["https://api.ip.sb/ip", (body) => String(body).trim()],
  ];
  let lastError = "IPv4 probe failed";
  for (const [url, parse] of probes) {
    try {
      const result = await request("get", { url, headers: selectedHeaders("DIRECT"), timeout: 5 });
      const ip = parse(result.data);
      if (/^(?:\d{1,3}\.){3}\d{1,3}$/.test(ip)) return ip;
      lastError = `invalid IPv4 from ${url}`;
    } catch (error) { lastError = error.message; }
  }
  throw new Error(lastError);
}

function tile(state) {
  if (!state || !state.accepted_at) {
    return { title: "PO0 未上报", content: state && state.last_error || "等待首次定时任务", icon: "antenna.radiowaves.left.and.right", backgroundColor: "#6b7280", url: FORCE_URL };
  }
  const remaining = Math.max(0, Math.floor((Number(state.expires_at) * 1000 - Date.now()) / 1000));
  const age = Math.max(0, Math.floor((Date.now() - Number(state.accepted_at) * 1000) / 60000));
  const suffix = state.last_error ? `\n错误：${state.last_error}` : "";
  return {
    title: remaining > 0 ? "PO0 已上报" : "PO0 已过期",
    content: `${state.accepted_cidr || state.ip}\n${state.network} · ${age} 分钟前 · 剩余 ${Math.floor(remaining / 60)} 分钟${suffix}`,
    icon: remaining > 0 ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
    backgroundColor: remaining > 0 ? "#178f55" : "#b45309",
    url: FORCE_URL,
  };
}

function htmlResult(ok, message, state) {
  const color = ok ? "#178f55" : "#b91c1c";
  const cidr = state && (state.accepted_cidr || state.ip) || "-";
  return `<!doctype html><meta name="viewport" content="width=device-width"><title>PO0 上报</title><body style="font-family:-apple-system;padding:28px;color:#111"><h2 style="color:${color}">${ok ? "PO0 上报成功" : "PO0 上报失败"}</h2><p>${message}</p><p>${cidr}</p><p><a href="stash://">返回 Stash</a></p></body>`;
}

function finish(mode, ok, message, state) {
  if ($script.type === "tile" || mode === "status") return $done(tile(state));
  if ($script.type === "request" || mode === "force") {
    if (mode === "force") $notification.post("PO0 上报", ok ? "成功" : "失败", message);
    return $done({ response: { status: ok ? 200 : 502, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" }, body: htmlResult(ok, message, state) } });
  }
  return $done();
}

async function run() {
  const args = parseArgument();
  const mode = $script.type === "tile" ? "status" : String(args.mode || "auto");
  let state = readJSON(STORE_KEY, {});
  if (mode === "status") return finish(mode, true, "status", state);

  const now = Date.now();
  if (mode === "force") {
    const lockedAt = Number($persistentStore.read(FORCE_LOCK_KEY) || 0);
    if (now - lockedAt < 10000) return finish(mode, false, "10 秒内请勿重复点击", state);
    $persistentStore.write(String(now), FORCE_LOCK_KEY);
  }

  const workerUrl = String(args.worker_url || "");
  const secureWorker = /^https:\/\//.test(workerUrl);
  const loopbackPoC = args.allow_loopback_http === true && /^http:\/\/127\.0\.0\.1:8790\/stash-report\/v1\/?$/.test(workerUrl);
  if ((!secureWorker && !loopbackPoC) || !/\/stash-report\/v1\/?$/.test(workerUrl)) {
    throw new Error("worker_url 必须是 HTTPS；仅 SSH PoC 可用 127.0.0.1:8790");
  }
  if (!args.source_id || !args.secret || /^CHANGE_ME/.test(args.secret)) throw new Error("请先设置 source_id 与 secret");

  const network = await detectNetwork();
  const ip = await detectIPv4();
  const lastAcceptedMs = Number(state.accepted_at || 0) * 1000;
  const unchanged = state.ip === ip && state.network === network;
  if (mode === "auto" && unchanged && now - lastAcceptedMs < 3600000) return finish(mode, true, "unchanged", state);

  const requestId = `${args.source_id}-${Math.floor(now / 1000)}-${Math.random().toString(36).slice(2, 10)}`;
  const payload = { source_id: String(args.source_id), ip, network, observed_at: Math.floor(now / 1000), request_id: requestId };
  const result = await request("post", {
    url: workerUrl,
    headers: {
      "Authorization": `Bearer ${args.secret}`,
      "Content-Type": "application/json",
      "User-Agent": "ProxyConfig-Stash-PO0/1.0",
      ...(args.selected_proxy ? { "X-Stash-Selected-Proxy": encodeURIComponent(args.selected_proxy) } : {}),
    },
    body: JSON.stringify(payload),
    timeout: 12,
  });
  let response;
  try { response = JSON.parse(result.data); }
  catch (_) { throw new Error(`LAN Worker returned non-JSON (${result.response.status || "?"})`); }
  if (!response.ok || !response.accepted_cidr) throw new Error(response.error || `LAN Worker rejected (${result.response.status || "?"})`);

  state = {
    ok: true,
    source_id: response.source_id || args.source_id,
    ip,
    network,
    accepted_cidr: response.accepted_cidr,
    accepted_at: epochSeconds(response.accepted_at, Math.floor(now / 1000)),
    expires_at: epochSeconds(response.expires_at, Math.floor(now / 1000) + 43200),
    targets: response.targets || [],
    last_error: "",
  };
  writeJSON(STORE_KEY, state);
  return finish(mode, true, `${state.accepted_cidr} · ${network}`, state);
}

run().catch((error) => {
  const args = parseArgument();
  const mode = $script.type === "tile" ? "status" : String(args.mode || "auto");
  const state = readJSON(STORE_KEY, {});
  state.last_error = String(error && error.message || error);
  state.last_error_at = Math.floor(Date.now() / 1000);
  writeJSON(STORE_KEY, state);
  console.log(`[PO0] ${state.last_error}`);
  finish(mode, false, state.last_error, state);
});
