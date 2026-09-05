"use strict";

const PO0_STORE_KEY = "proxyconfig.po0.loon-report.v1";
const PO0_RUN_LOCK_KEY = `${PO0_STORE_KEY}.run-lock`;
const PO0_WORKER_URL_KEY = "po0_worker_url";
const PO0_WORKER_TOKEN_KEY = "po0_worker_token";
const PO0_FIREWALL_TOKENS_KEY = "PO0_FIREWALL_TOKENS";
const PO0_HOME_SSID = "ZTE-47kTee";
const PO0_SOURCE_ID = "loon-ios";
const PO0_USER_AGENT = "AutoLoon-Loon/1";
const PO0_OFFICIAL_USER_AGENT = "ProxyConfig-PO0-Firewall/Loon";
const PO0_OFFICIAL_API_URL = "https://124.221.69.228/api/firewall";
const PO0_OFFICIAL_INTERVAL_SECONDS = 600;
const PO0_MAX_FIREWALL_TOKENS = 16;
// One persistent guard covers every report/status mode and network context.
// Loon exposes persistent storage but no atomic lock primitive, so a bounded
// expiry is the safest recoverable approximation for a whole run.
const PO0_RUN_LOCK_TTL_MS = 120_000;
const PO0_DEFAULT_REFRESH_TTL_SECONDS = 30 * 60;
const PO0_EXPIRY_SAFETY_SECONDS = 10 * 60;

let po0Finished = false;

function finish() {
  if (po0Finished) return;
  po0Finished = true;
  $done();
}

function log(message) {
  try {
    if (typeof console !== "undefined" && console.log) console.log(`[PO0] ${message}`);
  } catch (_) {
    // Logging must never prevent Loon from releasing the script context.
  }
}

function notify(title, subtitle, content) {
  try {
    if (typeof $notification !== "undefined" && $notification.post) {
      $notification.post(title, subtitle, content);
    }
  } catch (_) {
    // Notification permission/state must not affect the report lifecycle.
  }
}

function readStore(key) {
  try {
    return $persistentStore.read(key);
  } catch (_) {
    return null;
  }
}

function readJSON(key, fallback) {
  try {
    const value = readStore(key);
    return value ? JSON.parse(value) : fallback;
  } catch (_) {
    return fallback;
  }
}

function writeJSON(key, value) {
  try {
    return $persistentStore.write(JSON.stringify(value), key);
  } catch (_) {
    return false;
  }
}

function writeStore(key, value) {
  try {
    return $persistentStore.write(String(value), key);
  } catch (_) {
    return false;
  }
}

function parseArgument(raw) {
  if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
  if (Array.isArray(raw)) {
    if (raw.length === 1 && raw[0] && typeof raw[0] === "object") return raw[0];
    return { mode: String(raw[0] || "auto") };
  }

  const text = String(raw || "").trim();
  if (!text) return { mode: "auto" };
  try {
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) return parsed;
    if (typeof parsed === "string") return { mode: parsed };
  } catch (_) {
    // Loon plugin declarations deliberately pass the simple strings auto/status/force.
  }
  return { mode: text };
}

function getArgument() {
  return parseArgument(typeof $argument === "undefined" ? "" : $argument);
}

function readRuntimeConfig() {
  if (typeof $config === "undefined" || !$config.getConfig) {
    throw new Error("Loon config API unavailable");
  }

  // Loon documents getConfig() as returning a JSON string. Parse before use so
  // an absent or malformed SSID always fails closed instead of being guessed.
  const raw = $config.getConfig();
  const parsed = JSON.parse(raw);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("invalid Loon config payload");
  }
  return parsed;
}

function classifyNetwork(runtimeConfig) {
  const ssid = String(runtimeConfig.ssid || "").trim();
  const unknown = !ssid || /^(?:<?unknown(?: ssid)?>?|null|undefined|n\/a)$/i.test(ssid);
  if (unknown) {
    return { allowed: false, reason: "无法可靠识别 SSID，已按 fail-closed 跳过" };
  }
  if (ssid === PO0_HOME_SSID) {
    return { allowed: false, home: true, reason: `家庭 Wi-Fi ${PO0_HOME_SSID} 禁止上报` };
  }

  const cellular = /^(?:cellular|wwan|mobile|mobile data)$/i.test(ssid);
  return {
    allowed: true,
    network: cellular ? "cellular" : "wifi",
    ssid,
    context: `${cellular ? "cellular" : "wifi"}:${ssid}`,
  };
}

function forceNetwork(network) {
  if (network.allowed) return network;
  if (network.home) {
    return {
      allowed: true,
      forced: true,
      home: true,
      network: "wifi",
      ssid: PO0_HOME_SSID,
      context: "wifi:" + PO0_HOME_SSID,
    };
  }
  return {
    allowed: true,
    forced: true,
    unknown: true,
    network: "unknown",
    ssid: "",
    context: "unknown",
  };
}

function firstNonEmpty(values) {
  for (const value of values) {
    if (value !== undefined && value !== null && String(value).trim()) return String(value).trim();
  }
  return "";
}

function loadCredentials(args) {
  const workerUrl = firstNonEmpty([
    args.worker_url,
    args.workerUrl,
    readStore(PO0_WORKER_URL_KEY),
    readStore(`${PO0_STORE_KEY}.worker_url`),
  ]);
  const token = firstNonEmpty([
    args.token,
    args.secret,
    args.worker_token,
    readStore(PO0_WORKER_TOKEN_KEY),
    readStore(`${PO0_STORE_KEY}.worker_token`),
  ]);

  if (!workerUrl) return null;
  const endpoint = workerUrl.split(/[?#]/, 1)[0].replace(/\/+$/, "");
  if (!/^https:\/\/[^/?#]+/i.test(workerUrl) || !/\/stash-report\/v1$/i.test(endpoint)) {
    throw new Error("PO0 Worker URL 必须是 HTTPS /stash-report/v1 端点");
  }
  if (!token || /^CHANGE_ME/i.test(token)) throw new Error("PO0 Worker token 未配置");
  return { workerUrl, token };
}

function firewallRawValue(args) {
  const explicit = args && Object.prototype.hasOwnProperty.call(args, PO0_FIREWALL_TOKENS_KEY)
    ? args[PO0_FIREWALL_TOKENS_KEY]
    : undefined;
  if (String(explicit === undefined ? "" : explicit).trim() === "-") {
    writeStore(PO0_FIREWALL_TOKENS_KEY, "");
    return "";
  }
  const fromArgument = firstNonEmpty([
    args.PO0_FIREWALL_TOKENS,
    args.po0_firewall_tokens,
    args.firewall_tokens,
  ]);
  const fromStore = firstNonEmpty([readStore(PO0_FIREWALL_TOKENS_KEY)]);
  if (fromArgument) {
    if (fromArgument !== fromStore) writeStore(PO0_FIREWALL_TOKENS_KEY, fromArgument);
    return fromArgument;
  }
  return fromStore;
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
    if (tokens.length > 16) throw new Error("PO0 官方防火墙 token 数量超过上限");
  }
  return tokens;
}

function loadFirewallTokens(args) {
  return parseFirewallTokens(firewallRawValue(args));
}

function request(method, options) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const callback = (error, response, data) => {
      if (settled) return;
      settled = true;
      if (error) reject(new Error(String(error)));
      else resolve({ response: response || {}, data: data || "" });
    };

    try {
      $httpClient[method](options, callback);
    } catch (error) {
      callback(error);
    }
  });
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
  try {
    body = JSON.parse(result.data);
  } catch (_) {
    throw new Error("官方防火墙 " + phase + " 返回非 JSON");
  }
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
  const base = PO0_OFFICIAL_API_URL + "/" + token;
  if (operation === "status") return base;
  if (operation !== "add") throw new Error("官方防火墙操作无效");
  return base + "/add" + (fixedSlot === null ? "" : "?slot=" + fixedSlot);
}

async function officialRequest(item, operation) {
  return request(operation === "status" ? "get" : "post", {
    url: officialUrl(item.token, operation, item.fixedSlot),
    headers: {
      Accept: "application/json",
      "User-Agent": PO0_OFFICIAL_USER_AGENT,
    },
    node: "DIRECT",
    timeout: 20_000,
  });
}

function officialHit(response, item) {
  for (const entry of response.whitelist) {
    if (entry.ip !== response.currentIp) continue;
    if (item.fixedSlot === null || entry.slot === item.fixedSlot) return true;
  }
  return false;
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

function officialSummary(official) {
  if (!official || !Array.isArray(official.accounts) || !official.accounts.length) {
    return "官方防火墙：未启用";
  }
  const ok = official.accounts.filter((account) => account.status !== "error").length;
  const added = official.accounts.filter((account) => account.added).length;
  const missing = official.accounts.filter((account) => account.status === "missing" || account.status === "slot-mismatch").length;
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

async function runOfficialAccount(item, index, tokens, mode, previous, nowSeconds) {
  try {
    // Each account remains GET-first; only independent accounts overlap.
    const status = parseOfficialResponse(await officialRequest(item, "status"), "状态");
    const hit = officialHit(status, item);
    if (hit) {
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
    if (response.currentIp !== status.currentIp) throw new Error("加白后当前出口已变化，未确认");
    if (!officialHit(response, item)) throw new Error("加白后未确认当前出口或固定槽位");
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

  const official = {
    accounts,
    last_attempt_at: mode === "status" ? Number(previous && previous.last_attempt_at || 0) : nowSeconds,
    last_checked_at: nowSeconds,
    last_error: failures ? "部分官方防火墙账号检查或上报失败" : "",
  };
  return { ok: failures === 0, added, attempted: true, official };
}

async function detectIPv4() {
  const probes = [
    ["https://api.ipify.org?format=json", (body) => JSON.parse(body).ip],
    ["https://api.ip.sb/ip", (body) => String(body).trim()],
  ];
  let lastError = "IPv4 probe failed";

  for (const probe of probes) {
    try {
      const result = await request("get", {
        url: probe[0],
        headers: { "User-Agent": PO0_USER_AGENT },
        node: "DIRECT",
        timeout: 5_000,
      });
      const ip = probe[1](result.data);
      if (validIPv4(ip)) return String(ip).trim();
      lastError = "public IPv4 probe returned invalid data";
    } catch (error) {
      lastError = String(error && error.message || error);
    }
  }
  throw new Error(lastError);
}

function epochSeconds(value, fallback) {
  const numeric = Number(value);
  if (Number.isFinite(numeric) && numeric > 0) {
    return numeric > 10_000_000_000 ? Math.floor(numeric / 1000) : Math.floor(numeric);
  }
  const parsed = Date.parse(String(value || ""));
  return Number.isFinite(parsed) ? Math.floor(parsed / 1000) : fallback;
}

function boundedRefreshTTL(args) {
  const value = Number(args.refresh_ttl_seconds || args.ttl_seconds || PO0_DEFAULT_REFRESH_TTL_SECONDS);
  if (!Number.isFinite(value)) return PO0_DEFAULT_REFRESH_TTL_SECONDS;
  return Math.max(300, Math.min(6 * 60 * 60, Math.floor(value)));
}

function canUseCachedTTL(mode, state, network, nowSeconds) {
  if (mode !== "auto" || !state || state.context !== network.context) return false;
  const nextRefresh = Number(state.next_refresh_at || 0);
  const expiresAt = Number(state.expires_at || 0);
  return nextRefresh > nowSeconds && expiresAt > nowSeconds + PO0_EXPIRY_SAFETY_SECONDS;
}

function officialDue(mode, state, nowSeconds) {
  if (mode === "force") return true;
  if (mode !== "auto") return false;
  const last = Number(state && state.last_attempt_at || 0);
  return !last || nowSeconds < last || nowSeconds - last >= PO0_OFFICIAL_INTERVAL_SECONDS;
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
  const key = PO0_RUN_LOCK_KEY;
  const old = parseRunLock(readJSON(key, {}));
  const activeByExpiry = Number.isFinite(old.expiresAt) && old.expiresAt > now;
  const activeByLegacyAt = Number.isFinite(old.at) && old.at > 0 && (now < old.at || now - old.at < PO0_RUN_LOCK_TTL_MS);
  if (activeByExpiry || activeByLegacyAt) return null;
  const owner = String(now) + "-" + Math.random().toString(36).slice(2, 10);
  const lock = {
    version: 1,
    owner,
    at: now,
    expires_at: now + PO0_RUN_LOCK_TTL_MS,
    context: String(context || ""),
    mode: String(mode || "auto"),
  };
  // Without a persisted lock, another invocation cannot observe this owner;
  // fail closed instead of allowing concurrent official/worker reports.
  if (!writeJSON(key, lock)) return null;
  const confirmed = parseRunLock(readJSON(key, {}));
  return confirmed.owner === owner ? lock : null;
}

function releaseRunLock(lock) {
  if (!lock || !lock.owner) return;
  const current = parseRunLock(readJSON(PO0_RUN_LOCK_KEY, {}));
  if (current.owner === lock.owner) writeJSON(PO0_RUN_LOCK_KEY, {});
}

function statusMessage(state) {
  const official = officialSummary(state && state.official);
  const savedError = state && state.last_error
    ? String(state.last_error).replace(/pgnfw_[A-Za-z0-9._~-]+/g, "[REDACTED]").replace(/Bearer\s+[^\s,;]+/gi, "Bearer [REDACTED]")
    : "";
  if (!state || !state.accepted_at) {
    const worker = savedError ? "最近错误：" + savedError : "尚未成功上报";
    return official + "；Worker " + worker;
  }
  const expiresAt = Number(state.expires_at || 0);
  const remaining = Math.max(0, expiresAt - Math.floor(Date.now() / 1000));
  const suffix = savedError ? "；最近错误：" + savedError : "";
  return official + "；Worker " + (state.accepted_cidr || state.ip) + " · " + state.network +
    " · 剩余 " + Math.floor(remaining / 60) + " 分钟" + suffix;
}

function redactedError(error, args, items) {
  let message = String(error && error.message || error);
  const tokens = [];
  if (args) {
    tokens.push(args.token, args.secret, args.worker_token, args.PO0_FIREWALL_TOKENS, args.po0_firewall_tokens, args.firewall_tokens);
  }
  if (Array.isArray(items)) {
    for (const item of items) tokens.push(item && item.token);
  }
  tokens.push(readStore(PO0_WORKER_TOKEN_KEY), readStore(PO0_STORE_KEY + ".worker_token"), readStore(PO0_FIREWALL_TOKENS_KEY));
  for (const token of tokens) {
    if (token !== undefined && token !== null && String(token)) message = message.split(String(token)).join("[REDACTED]");
  }
  return message
    .replace(/pgnfw_[A-Za-z0-9._~-]+/g, "[REDACTED]")
    .replace(/Bearer\s+[^\s,;]+/gi, "Bearer [REDACTED]");
}

function finishResult(mode, ok, message, state, meta) {
  const details = meta || {};
  log(message);
  if (mode === "status") notify("PO0 状态", ok ? "可用" : "异常", statusMessage(state));
  if (mode === "force") notify("PO0 手动上报", ok ? "成功" : "拒绝或失败", message);
  if (mode === "auto" && (!ok || Number(details.added || 0) > 0)) {
    notify("PO0 自动上报", ok ? "新增官方白名单" : "部分失败", message);
  }
  finish();
}

async function runWorker(credentials, state, args, network, mode, nowSeconds) {
  if (!credentials) return { ok: true, enabled: false, skipped: true };
  if (canUseCachedTTL(mode, state, network, nowSeconds)) {
    return { ok: true, enabled: true, skipped: true };
  }

  const ip = await detectIPv4();
  const requestId = PO0_SOURCE_ID + "-" + nowSeconds + "-" + Math.random().toString(36).slice(2, 10);
  const payload = {
    source_id: PO0_SOURCE_ID,
    ip,
    network: network.network,
    observed_at: nowSeconds,
    request_id: requestId,
  };
  const result = await request("post", {
    url: credentials.workerUrl,
    headers: {
      "Authorization": "Bearer " + credentials.token,
      "Content-Type": "application/json",
      "User-Agent": PO0_USER_AGENT,
    },
    body: JSON.stringify(payload),
    timeout: 12_000,
  });

  const status = responseStatus(result);
  let response;
  try {
    response = JSON.parse(result.data);
  } catch (_) {
    throw new Error("LAN Worker 返回非 JSON（HTTP " + (status || "?") + "）");
  }
  if (status < 200 || status >= 300 || !response.ok || !response.accepted_cidr) {
    throw new Error("LAN Worker 拒绝请求（HTTP " + (status || "?") + "）");
  }

  const acceptedAt = epochSeconds(response.accepted_at, nowSeconds);
  const expiresAt = epochSeconds(response.expires_at, nowSeconds + 12 * 60 * 60);
  const refreshTTL = boundedRefreshTTL(args);
  const nextRefreshAt = Math.max(
    nowSeconds,
    Math.min(acceptedAt + refreshTTL, expiresAt - PO0_EXPIRY_SAFETY_SECONDS),
  );
  return {
    ok: true,
    enabled: true,
    skipped: false,
    state: {
      ok: true,
      source_id: PO0_SOURCE_ID,
      ip,
      network: network.network,
      context: network.context,
      accepted_cidr: response.accepted_cidr,
      accepted_at: acceptedAt,
      expires_at: expiresAt,
      next_refresh_at: nextRefreshAt,
      targets: Array.isArray(response.targets) ? response.targets : [],
      last_error: "",
    },
  };
}

async function runUnlocked() {
  const args = getArgument();
  const mode = String(args.mode || "auto").toLowerCase();
  if (!["auto", "status", "force"].includes(mode)) throw new Error("不支持的模式：" + mode);

  let state = readJSON(PO0_STORE_KEY, {});
  if (!state || typeof state !== "object" || Array.isArray(state)) state = {};
  const now = Date.now();
  const nowSeconds = Math.floor(now / 1000);

  if (mode === "status") {
    const tokens = loadFirewallTokens(args);
    if (!tokens.length) {
      finishResult(mode, true, "status", state);
      return;
    }
    const officialResult = await runOfficial(tokens, mode, state.official || {}, nowSeconds);
    state.official = officialResult.official;
    if (!officialResult.ok) state.last_error = officialResult.official.last_error;
    writeJSON(PO0_STORE_KEY, state);
    finishResult(mode, officialResult.ok, officialSummary(state.official), state, officialResult);
    return;
  }

  const classified = classifyNetwork(readRuntimeConfig());
  if (!classified.allowed && mode !== "force") {
    finishResult(mode, false, classified.reason, state);
    return;
  }
  const network = mode === "force" ? forceNetwork(classified) : classified;
  const tokens = loadFirewallTokens(args);
  const credentials = loadCredentials(args);
  const needsOfficial = tokens.length > 0 && officialDue(mode, state.official || {}, nowSeconds);
  const workerCached = canUseCachedTTL(mode, state, network, nowSeconds);
  if (!needsOfficial && workerCached) {
    finishResult(mode, true, "有效 TTL 内无需重复上报", state);
    return;
  }
  let officialResult = { ok: true, added: 0, attempted: false };
  if (tokens.length && (needsOfficial || mode === "force")) {
    officialResult = await runOfficial(tokens, mode, state.official || {}, nowSeconds);
    state.official = officialResult.official;
    state.official.network = network.network;
  }

  let workerResult = { ok: true, enabled: false, skipped: true };
  try {
    workerResult = await runWorker(credentials, state, args, network, mode, nowSeconds);
    if (workerResult.state) {
      const official = state.official;
      state = workerResult.state;
      if (official) state.official = official;
    }
  } catch (error) {
    workerResult = {
      ok: false,
      enabled: Boolean(credentials),
      skipped: false,
      error: redactedError(error, args, tokens),
    };
  }

  const ok = officialResult.ok && workerResult.ok;
  const parts = [];
  if (officialResult.attempted) {
    parts.push("官方" + (officialResult.added ? "新增 " + officialResult.added : "检查完成"));
  }
  if (workerResult.enabled) {
    parts.push(workerResult.skipped ? "Worker 有效 TTL 内跳过" : workerResult.ok ? "Worker 完成" : "Worker 失败");
  }
  if (!parts.length) parts.push("没有启用的上报通道");
  const message = parts.join("；") + (ok ? "" : "；本轮部分失败");
  state.last_error = ok
    ? ""
    : officialResult.ok
      ? workerResult.error || "上报失败"
      : officialResult.official && officialResult.official.last_error || "官方通道失败";
  writeJSON(PO0_STORE_KEY, state);
  finishResult(mode, ok, message, state, { added: officialResult.added });
}

async function run() {
  const args = getArgument();
  const mode = String(args.mode || "auto").toLowerCase();
  if (!["auto", "status", "force"].includes(mode)) throw new Error("不支持的模式：" + mode);

  // A status request with no configured official channel has no report-side
  // work and keeps the historical read-only/no-write behavior.
  const needsLock = mode !== "status" || loadFirewallTokens(args).length > 0;
  if (!needsLock) return await runUnlocked();

  const lock = acquireRunLock(mode, mode === "status" ? "status" : "pending", Date.now());
  if (!lock) {
    const state = readJSON(PO0_STORE_KEY, {});
    finishResult(mode, true, "去抖窗口内跳过重复触发", state);
    return;
  }
  try {
    return await runUnlocked();
  } finally {
    releaseRunLock(lock);
  }
}

run().catch((error) => {
  const args = getArgument();
  const mode = String(args.mode || "auto").toLowerCase();
  const message = redactedError(error, args);
  const state = readJSON(PO0_STORE_KEY, {});

  // status is intentionally read-only. All other modes retain a redacted local
  // error for diagnostics; credentials are never included in log/state text.
  if (mode !== "status") {
    state.last_error = message;
    state.last_error_at = Math.floor(Date.now() / 1000);
    writeJSON(PO0_STORE_KEY, state);
  }
  finishResult(mode, false, message, state);
});
