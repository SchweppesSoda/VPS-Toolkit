const STORE_KEY = "proxyconfig.po0.stash-report.v1";
const RUN_LOCK_KEY = STORE_KEY + ".run-lock";
const NETWORK_GROUP = "📡 PO0 网络识别（自动）";
const FORCE_URL = "http://po0-report.invalid/report-now";
const FIREWALL_TOKENS_KEY = "PO0_FIREWALL_TOKENS";
const OFFICIAL_API_URL = "https://124.221.69.228/api/firewall";
const OFFICIAL_INTERVAL_SECONDS = 600;
const OFFICIAL_USER_AGENT = "ProxyConfig-PO0-Firewall/Stash";
const MAX_FIREWALL_TOKENS = 16;
// One persistent guard covers every report/status mode and network context.
// Stash exposes persistent storage but no atomic lock primitive, so a bounded
// expiry is the safest recoverable approximation for a whole run.
const RUN_LOCK_TTL_MS = 120000;

function readStore(key) {
  try { return $persistentStore.read(key); }
  catch (_) { return null; }
}

function readJSON(key, fallback) {
  try { return JSON.parse(readStore(key) || "null") || fallback; }
  catch (_) { return fallback; }
}

function writeJSON(key, value) {
  try { return $persistentStore.write(JSON.stringify(value), key); }
  catch (_) { return false; }
}

function writeStore(key, value) {
  try { return $persistentStore.write(String(value), key); }
  catch (_) { return false; }
}

function firstNonEmpty(values) {
  for (const value of values) {
    if (value !== undefined && value !== null && String(value).trim()) return String(value).trim();
  }
  return "";
}

function firewallInput(args) {
  return firstNonEmpty([
    args.PO0_FIREWALL_TOKENS, args.po0_firewall_tokens, args.firewall_tokens,
    readStore(FIREWALL_TOKENS_KEY),
  ]);
}

function saveLocalFirewall(args, clear) {
  const input = clear ? "" : firewallInput(args);
  const tokens = input === "-" ? "" : input;
  parseFirewallTokens(tokens);
  if (!writeJSON(STORE_KEY + ".official-config", { version: 1, tokens })) throw new Error("无法保存本机官方配置");
  return tokens;
}

function firewallRawValue(args) {
  // Module parameters may arrive from iCloud. A saved device choice wins;
  // only the explicit save/clear actions can replace it, including a clear.
  const saved = readStore(STORE_KEY + ".official-config");
  if (saved !== null && saved !== undefined && String(saved).trim() !== "") {
    let local;
    try { local = JSON.parse(saved); } catch (_) { throw new Error("本机官方配置损坏，请重新保存"); }
    if (!local || local.version !== 1 || typeof local.tokens !== "string") throw new Error("本机官方配置格式错误");
    return local.tokens;
  }
  const input = firewallInput(args);
  if (!input) return "";
  return saveLocalFirewall(args, input === "-");
}

function parseFirewallTokens(raw) {
  const text = String(raw || "").trim();
  if (!text) return [];
  const items = text.split(",");
  if (!items.length || items.some((item) => !String(item).trim())) {
    throw new Error("PO0 官方防火墙 token 列表包含空项");
  }
  const tokens = [];
  const seen = [];
  for (const rawItem of items) {
    const item = String(rawItem).trim();
    const match = item.match(/^(pgnfw_[A-Za-z0-9._~-]{1,240})(?:@([0-4]))?$/);
    if (!match) {
      throw new Error("PO0 官方防火墙 token 配置无效：请使用 pgnfw_...，槽位可写为 @0 到 @4");
    }
    const token = match[1];
    const fixedSlot = match[2] === undefined ? null : Number(match[2]);
    // A token identifies one official account; slot hints are not separate accounts.
    const key = token;
    if (seen.indexOf(key) >= 0) throw new Error("PO0 官方防火墙 token 列表包含重复项");
    seen.push(key);
    tokens.push({ token, fixedSlot });
    if (tokens.length > MAX_FIREWALL_TOKENS) throw new Error("PO0 官方防火墙 token 数量超过上限");
  }
  return tokens;
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
      const result = await request("get", { url, headers: selectedHeaders("DIRECT"), node: "DIRECT", timeout: 5 });
      const ip = parse(result.data);
      if (validIPv4(ip)) return ip;
      lastError = "invalid IPv4 from probe";
    } catch (error) { lastError = String(error && error.message || error); }
  }
  throw new Error(lastError);
}

function validIPv4(value) {
  const parts = String(value || "").trim().split(".");
  return parts.length === 4 && parts.every((part) => /^\d{1,3}$/.test(part) && Number(part) <= 255);
}

function validIPv4Cidr24(value) {
  const text = String(value || "").trim();
  return /\/24$/.test(text) && validIPv4(text.slice(0, -3));
}

function responseStatus(result) {
  return Number(result && result.response && (result.response.status || result.response.statusCode) || 0);
}

function normalizeSlot(value) {
  if (value === undefined || value === null) return null;
  if (typeof value === "string" && value.trim() === "") return null;
  if (typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= 4) return value;
  throw new Error("官方白名单槽位无效");
}

function parseOfficialResponse(result, phase) {
  const status = responseStatus(result);
  if (status < 200 || status >= 300) {
    throw new Error("官方防火墙 " + phase + " 请求失败（HTTP " + (status || "?") + "）");
  }
  let body;
  try { body = JSON.parse(result.data); }
  catch (_) { throw new Error("官方防火墙 " + phase + " 返回非 JSON"); }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new Error("官方防火墙 " + phase + " 响应格式无效");
  }
  if (body.enabled !== true) throw new Error("官方防火墙未启用");
  if (!validIPv4Cidr24(body.currentIp)) throw new Error("官方防火墙当前出口 IPv4 无效");
  if (!Number.isInteger(body.limit) || body.limit < 1 || body.limit > 5) {
    throw new Error("官方防火墙名额无效");
  }
  if (!Array.isArray(body.whitelist) || body.whitelist.length > body.limit || body.whitelist.length > 5) {
    throw new Error("官方防火墙白名单状态无效");
  }
  const slots = [];
  const whitelist = body.whitelist.map((entry) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry) || !validIPv4Cidr24(entry.ip)) {
      throw new Error("官方防火墙白名单 IP 无效");
    }
    const slot = normalizeSlot(entry.slot);
    if (slot !== null) {
      if (slots.indexOf(slot) >= 0) throw new Error("官方防火墙白名单槽位重复");
      slots.push(slot);
    }
    return { ip: String(entry.ip).trim(), slot };
  });
  return {
    enabled: true,
    currentIp: String(body.currentIp).trim(),
    limit: body.limit,
    whitelist,
    used: whitelist.length,
  };
}

function officialUrl(token, operation, fixedSlot) {
  const base = OFFICIAL_API_URL + "/" + token;
  if (operation === "status") return base;
  if (operation !== "add") throw new Error("官方防火墙操作无效");
  return base + "/add" + (fixedSlot === null ? "" : "?slot=" + fixedSlot);
}

async function officialRequest(item, operation) {
  return request(operation === "status" ? "get" : "post", {
    url: officialUrl(item.token, operation, item.fixedSlot),
    headers: {
      Accept: "application/json",
      "User-Agent": OFFICIAL_USER_AGENT,
    },
    node: "DIRECT",
    timeout: 20,
  });
}

function officialHit(response, item) {
  return response.whitelist.some((entry) => entry.ip === response.currentIp &&
    (item.fixedSlot === null || entry.slot === item.fixedSlot));
}

function officialAccountState(index, item, response, nowSeconds, status, added, error) {
  return {
    account: index,
    fixed_slot: item.fixedSlot,
    enabled: response ? response.enabled : false,
    current: response ? response.currentIp : "",
    current_ip: response ? response.currentIp : "",
    current_exit: response ? response.currentIp : "",
    whitelist: response ? response.whitelist : [],
    used: response ? response.used : 0,
    limit: response ? response.limit : 0,
    status,
    added: added === true,
    last_checked_at: nowSeconds,
    last_error: error || "",
  };
}

function redactedError(error, args, items) {
  let message = String(error && error.message || error);
  const tokens = [];
  if (args) tokens.push(args.secret, args.token, args.PO0_FIREWALL_TOKENS, args.po0_firewall_tokens, args.firewall_tokens);
  if (Array.isArray(items)) items.forEach((item) => tokens.push(item && item.token));
  const persisted = readStore(FIREWALL_TOKENS_KEY);
  if (persisted) tokens.push(persisted);
  for (const token of tokens) {
    if (token !== undefined && token !== null && String(token)) message = message.split(String(token)).join("[REDACTED]");
  }
  return message
    .replace(/pgnfw_[A-Za-z0-9._~-]+/g, "[REDACTED]")
    .replace(/Bearer\s+[^\s,;]+/gi, "Bearer [REDACTED]");
}

function officialSummary(official) {
  if (!official || !Array.isArray(official.accounts) || !official.accounts.length) return "官方防火墙：未启用";
  const ok = official.accounts.filter((account) => account.status !== "error").length;
  const missing = official.accounts.filter((account) => account.status === "missing" || account.status === "slot-mismatch").length;
  const added = official.accounts.filter((account) => account.added).length;
  let text = "官方防火墙 " + ok + "/" + official.accounts.length + " · 已用状态已保存";
  const first = official.accounts.find((account) => account.status !== "error");
  if (first) {
    text += " · 当前 " + (first.current || "-") + " · " + first.used + "/" + first.limit;
    if (first.fixed_slot !== null && first.fixed_slot !== undefined) text += " · 固定槽位 " + (first.fixed_slot + 1);
  }
  if (official.network) text += " · " + official.network;
  if (missing) text += " · 未命中 " + missing;
  if (added) text += " · 新增 " + added;
  if (official.last_error) text += " · 最近失败";
  return text;
}

function officialDue(mode, state, nowSeconds) {
  if (mode === "force") return true;
  if (mode !== "auto") return false;
  const last = Number(state && state.last_attempt_at || 0);
  return !last || nowSeconds < last || nowSeconds - last >= OFFICIAL_INTERVAL_SECONDS;
}

function parseRunLock(raw) {
  const lock = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  return {
    owner: String(lock.owner || ""),
    at: Number(lock.at),
    expiresAt: Number(lock.expires_at || lock.expiresAt),
  };
}

function acquireRunLock(mode, context, now) {
  const old = parseRunLock(readJSON(RUN_LOCK_KEY, {}));
  const activeByExpiry = Number.isFinite(old.expiresAt) && old.expiresAt > now;
  const activeByLegacyAt = Number.isFinite(old.at) && old.at > 0 && (now < old.at || now - old.at < RUN_LOCK_TTL_MS);
  if (activeByExpiry || activeByLegacyAt) return null;
  const owner = String(now) + "-" + Math.random().toString(36).slice(2, 10);
  const lock = {
    version: 1,
    owner,
    at: now,
    expires_at: now + RUN_LOCK_TTL_MS,
    context: String(context || ""),
    mode: String(mode || "auto"),
  };
  // Without a persisted lock, another invocation cannot observe this owner;
  // fail closed instead of allowing concurrent official/worker reports.
  if (!writeJSON(RUN_LOCK_KEY, lock)) return null;
  const confirmed = parseRunLock(readJSON(RUN_LOCK_KEY, {}));
  return confirmed.owner === owner ? lock : null;
}

function releaseRunLock(lock) {
  if (!lock || !lock.owner) return;
  const current = parseRunLock(readJSON(RUN_LOCK_KEY, {}));
  if (current.owner === lock.owner) writeJSON(RUN_LOCK_KEY, {});
}

async function runOfficialAccount(item, index, tokens, mode, previous, nowSeconds) {
  try {
    // Each account remains GET-first; only independent accounts overlap.
    const status = parseOfficialResponse(await officialRequest(item, "status"), "状态");
    if (officialHit(status, item)) {
      return {
        account: officialAccountState(index + 1, item, status, nowSeconds, "ok", false, ""),
        added: false,
      };
    }
    if (mode === "status") {
      return {
        account: officialAccountState(index + 1, item, status, nowSeconds, item.fixedSlot === null ? "missing" : "slot-mismatch", false, ""),
        added: false,
      };
    }

    const response = parseOfficialResponse(await officialRequest(item, "add"), "加白");
    if (response.currentIp !== status.currentIp || !officialHit(response, item)) {
      throw new Error("加白后未确认当前出口或固定槽位");
    }
    return {
      account: officialAccountState(index + 1, item, response, nowSeconds, "ok", true, ""),
      added: true,
    };
  } catch (error) {
    const oldAccount = previous && Array.isArray(previous.accounts) ? previous.accounts[index] : null;
    return {
      account: oldAccount
        ? Object.assign({}, oldAccount, {
          account: index + 1,
          fixed_slot: item.fixedSlot,
          status: "error",
          added: false,
          last_checked_at: nowSeconds,
          last_error: redactedError(error, null, tokens),
        })
        : officialAccountState(index + 1, item, null, nowSeconds, "error", false, redactedError(error, null, tokens)),
      added: false,
    };
  }
}

async function runOfficial(tokens, mode, previous, nowSeconds) {
  // Start every account's GET together, but never overlap an account's POST
  // with its own GET. Promise.all preserves the configured account order.
  const results = await Promise.all(tokens.map((item, index) =>
    runOfficialAccount(item, index, tokens, mode, previous, nowSeconds)));
  const accounts = results.map((result) => result.account);
  const failures = accounts.filter((account) => account.status === "error").length;
  const added = results.filter((result) => result.added).length;

  return {
    ok: failures === 0,
    added,
    attempted: true,
    official: {
      accounts,
      last_attempt_at: mode === "status" ? Number(previous && previous.last_attempt_at || 0) : nowSeconds,
      last_checked_at: nowSeconds,
      last_error: failures ? "部分官方防火墙账号检查或上报失败" : "",
    },
  };
}

async function runWorker(args, state, network, mode, nowSeconds) {
  const workerUrl = String(args.worker_url || "").trim();
  if (!workerUrl) return { ok: true, enabled: false, skipped: true };
  const secureWorker = /^https:\/\//.test(workerUrl);
  const loopbackPoC = args.allow_loopback_http === true && /^http:\/\/127\.0\.0\.1:8790\/stash-report\/v1\/?$/.test(workerUrl);
  if ((!secureWorker && !loopbackPoC) || !/\/stash-report\/v1\/?$/.test(workerUrl)) {
    throw new Error("worker_url 必须是 HTTPS；仅 SSH PoC 可用 127.0.0.1:8790");
  }
  if (!args.source_id || !args.secret || /^CHANGE_ME/.test(args.secret)) {
    throw new Error("请先设置 source_id 与 secret");
  }

  const ip = await detectIPv4();
  const lastAcceptedMs = Number(state.accepted_at || 0) * 1000;
  const unchanged = state.ip === ip && state.network === network.network;
  if (mode === "auto" && unchanged && nowSeconds * 1000 - lastAcceptedMs < 3600000) {
    return { ok: true, enabled: true, skipped: true };
  }
  const requestId = String(args.source_id) + "-" + nowSeconds + "-" + Math.random().toString(36).slice(2, 10);
  const payload = { source_id: String(args.source_id), ip, network: network.network, observed_at: nowSeconds, request_id: requestId };
  const result = await request("post", {
    url: workerUrl,
    headers: {
      "Authorization": "Bearer " + args.secret,
      "Content-Type": "application/json",
      "User-Agent": "ProxyConfig-Stash-PO0/1.0",
      ...(args.selected_proxy ? { "X-Stash-Selected-Proxy": encodeURIComponent(args.selected_proxy) } : {}),
    },
    body: JSON.stringify(payload),
    timeout: 12,
  });
  const status = responseStatus(result);
  let response;
  try { response = JSON.parse(result.data); }
  catch (_) { throw new Error("LAN Worker returned non-JSON (" + (status || "?") + ")"); }
  if (status < 200 || status >= 300 || !response.ok || !response.accepted_cidr) {
    throw new Error("LAN Worker rejected (" + (status || "?") + ")");
  }
  return {
    ok: true,
    enabled: true,
    skipped: false,
    state: {
      ok: true,
      source_id: response.source_id || args.source_id,
      ip,
      network: network.network,
      context: network.context,
      accepted_cidr: response.accepted_cidr,
      accepted_at: epochSeconds(response.accepted_at, nowSeconds),
      expires_at: epochSeconds(response.expires_at, nowSeconds + 43200),
      targets: response.targets || [],
      last_error: "",
    },
  };
}

function tile(state) {
  if (!state || !state.accepted_at) {
    const error = state && state.last_error ? String(state.last_error).replace(/pgnfw_[A-Za-z0-9._~-]+/g, "[REDACTED]").replace(/Bearer\s+[^\s,;]+/gi, "Bearer [REDACTED]") : "";
    return { title: "PO0 未上报", content: officialSummary(state && state.official) + "\n" + (error || "等待首次定时任务"), icon: "antenna.radiowaves.left.and.right", backgroundColor: "#6b7280", url: FORCE_URL };
  }
  const remaining = Math.max(0, Math.floor((Number(state.expires_at) * 1000 - Date.now()) / 1000));
  const age = Math.max(0, Math.floor((Date.now() - Number(state.accepted_at) * 1000) / 60000));
  const savedError = state.last_error ? String(state.last_error).replace(/pgnfw_[A-Za-z0-9._~-]+/g, "[REDACTED]").replace(/Bearer\s+[^\s,;]+/gi, "Bearer [REDACTED]") : "";
  const suffix = savedError ? `\n错误：${savedError}` : "";
  return {
    title: remaining > 0 ? "PO0 已上报" : "PO0 已过期",
    content: `${state.accepted_cidr || state.ip}\n${state.network} · ${age} 分钟前 · 剩余 ${Math.floor(remaining / 60)} 分钟${suffix}\n${officialSummary(state.official)}`,
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

function finish(mode, ok, message, state, meta) {
  const details = meta || {};
  if ($script.type === "tile") return $done(tile(state));
  if (mode === "status") {
    if ($script.type === "request") {
      return $done({ response: { status: ok ? 200 : 502, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" }, body: htmlResult(ok, message, state) } });
    }
    return $done(tile(state));
  }
  if (mode === "auto" && (!ok || Number(details.added || 0) > 0)) {
    $notification.post("PO0 自动上报", ok ? "新增官方白名单" : "部分失败", message);
  }
  if ($script.type === "request" || mode === "force") {
    if (mode === "force") $notification.post("PO0 上报", ok ? "成功" : "失败", message);
    return $done({ response: { status: ok ? 200 : 502, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" }, body: htmlResult(ok, message, state) } });
  }
  return $done();
}

async function runUnlocked() {
  const args = parseArgument();
  const mode = $script.type === "tile" ? "status" : String(args.mode || "auto").toLowerCase();
  if (mode === "save-official" || mode === "clear-official") {
    saveLocalFirewall(args, mode === "clear-official");
    return finish("force", true, mode === "clear-official" ? "已清除本机官方配置；同步参数不会自动恢复它" : "已保存本机官方 Token 和槽位；后续同步参数不会覆盖", readJSON(STORE_KEY, {}), {});
  }
  if (["auto", "status", "force", "save-official", "clear-official"].indexOf(mode) < 0) throw new Error("不支持的模式：" + mode);
  let state = readJSON(STORE_KEY, {});
  if (!state || typeof state !== "object" || Array.isArray(state)) state = {};
  const now = Date.now();
  const nowSeconds = Math.floor(now / 1000);

  if (mode === "status") {
    const tokens = parseFirewallTokens(firewallRawValue(args));
    if (!tokens.length) return finish(mode, true, "status", state, {});
    const officialResult = await runOfficial(tokens, mode, state.official || {}, nowSeconds);
    state.official = officialResult.official;
    if (!officialResult.ok) state.last_error = officialResult.official.last_error;
    writeJSON(STORE_KEY, state);
    return finish(mode, officialResult.ok, officialSummary(state.official), state, officialResult);
  }

  // Validate official credentials before any network probe so malformed or
  // duplicate-account input fails closed without touching the network.
  const tokens = parseFirewallTokens(firewallRawValue(args));
  const detectedNetwork = await detectNetwork();
  if (detectedNetwork === "unknown" && mode !== "force") {
    return finish(mode, false, "无法可靠识别网络，已按 fail-closed 跳过", state, {});
  }
  const network = { network: detectedNetwork, context: detectedNetwork };
  const needsOfficial = tokens.length > 0 && officialDue(mode, state.official || {}, nowSeconds);

  let officialResult = { ok: true, added: 0, attempted: false };
  if (tokens.length && (needsOfficial || mode === "force")) {
    officialResult = await runOfficial(tokens, mode, state.official || {}, nowSeconds);
    state.official = officialResult.official;
    state.official.network = network.network;
  }

  let workerResult = { ok: true, enabled: false, skipped: true };
  try {
    workerResult = await runWorker(args, state, network, mode, nowSeconds);
    if (workerResult.state) {
      const official = state.official;
      state = workerResult.state;
      if (official) state.official = official;
    }
  } catch (error) {
    workerResult = {
      ok: false,
      enabled: Boolean(args.worker_url),
      skipped: false,
      error: redactedError(error, args, tokens),
    };
  }

  const ok = officialResult.ok && workerResult.ok;
  const parts = [];
  if (officialResult.attempted) parts.push("官方" + (officialResult.added ? "新增 " + officialResult.added : "检查完成"));
  if (workerResult.enabled) parts.push(workerResult.skipped ? "Worker 一小时内跳过" : workerResult.ok ? "Worker 完成" : "Worker 失败");
  if (!parts.length) parts.push("没有启用的上报通道");
  const message = parts.join("；") + (ok ? "" : "；本轮部分失败");
  state.last_error = ok
    ? ""
    : officialResult.ok
      ? workerResult.error || "上报失败"
      : officialResult.official && officialResult.official.last_error || "官方通道失败";
  writeJSON(STORE_KEY, state);
  return finish(mode, ok, message, state, { added: officialResult.added });
}

async function run() {
  const args = parseArgument();
  const mode = $script.type === "tile" ? "status" : String(args.mode || "auto").toLowerCase();
  if (["auto", "status", "force", "save-official", "clear-official"].indexOf(mode) < 0) throw new Error("不支持的模式：" + mode);

  // A status request with no configured official channel has no report-side
  // work and keeps the historical read-only/no-write behavior.
  if (mode === "save-official" || mode === "clear-official") return runUnlocked();
  const needsLock = mode !== "status" || parseFirewallTokens(firewallRawValue(args)).length > 0;
  if (!needsLock) return await runUnlocked();

  const lock = acquireRunLock(mode, mode === "status" ? "status" : "pending", Date.now());
  if (!lock) {
    const state = readJSON(STORE_KEY, {});
    finish(mode, true, "去抖窗口内跳过重复触发", state, {});
    return;
  }
  try {
    return await runUnlocked();
  } finally {
    releaseRunLock(lock);
  }
}

run().catch((error) => {
  const args = parseArgument();
  const mode = $script.type === "tile" ? "status" : String(args.mode || "auto").toLowerCase();
  const state = readJSON(STORE_KEY, {});
  const message = redactedError(error, args, null);
  if (mode !== "status") {
    state.last_error = message;
    state.last_error_at = Math.floor(Date.now() / 1000);
    writeJSON(STORE_KEY, state);
  }
  console.log("[PO0] " + message);
  finish(mode, false, message, state);
});
