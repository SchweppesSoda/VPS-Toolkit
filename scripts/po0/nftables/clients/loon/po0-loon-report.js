"use strict";

const PO0_STORE_KEY = "proxyconfig.po0.loon-report.v1";
const PO0_RUN_LOCK_KEY = `${PO0_STORE_KEY}.run-lock`;
const PO0_FORCE_LOCK_KEY = `${PO0_STORE_KEY}.force-lock`;
const PO0_WORKER_URL_KEY = "po0_worker_url";
const PO0_WORKER_TOKEN_KEY = "po0_worker_token";
const PO0_HOME_SSID = "ZTE-47kTee";
const PO0_SOURCE_ID = "loon-ios";
const PO0_USER_AGENT = "AutoLoon-Loon/1";
const PO0_DEBOUNCE_MS = 15_000;
const PO0_FORCE_DEBOUNCE_MS = 10_000;
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

  const endpoint = workerUrl.split(/[?#]/, 1)[0].replace(/\/+$/, "");
  if (!/^https:\/\/[^/?#]+/i.test(workerUrl) || !/\/stash-report\/v1$/i.test(endpoint)) {
    throw new Error("PO0 Worker URL 必须是 HTTPS /stash-report/v1 端点");
  }
  if (!token || /^CHANGE_ME/i.test(token)) throw new Error("PO0 Worker token 未配置");
  return { workerUrl, token };
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

function acquireRunLock(mode, context, now) {
  const key = mode === "force" ? PO0_FORCE_LOCK_KEY : PO0_RUN_LOCK_KEY;
  const debounce = mode === "force" ? PO0_FORCE_DEBOUNCE_MS : PO0_DEBOUNCE_MS;
  const lock = readJSON(key, {});
  if (lock.context === context && now - Number(lock.at || 0) < debounce) return false;
  writeJSON(key, { at: now, context });
  return true;
}

function statusMessage(state) {
  if (!state || !state.accepted_at) {
    return state && state.last_error ? `尚未成功上报；最近错误：${state.last_error}` : "尚未成功上报";
  }
  const expiresAt = Number(state.expires_at || 0);
  const remaining = Math.max(0, expiresAt - Math.floor(Date.now() / 1000));
  const suffix = state.last_error ? `；最近错误：${state.last_error}` : "";
  return `${state.accepted_cidr || state.ip} · ${state.network} · 剩余 ${Math.floor(remaining / 60)} 分钟${suffix}`;
}

function redactedError(error, args) {
  let message = String(error && error.message || error);
  const tokens = [
    args && args.token,
    args && args.secret,
    args && args.worker_token,
    readStore(PO0_WORKER_TOKEN_KEY),
    readStore(`${PO0_STORE_KEY}.worker_token`),
  ].filter((value) => value !== undefined && value !== null && String(value));

  for (const token of tokens) message = message.split(String(token)).join("[REDACTED]");
  return message.replace(/Bearer\s+[^\s,;]+/gi, "Bearer [REDACTED]");
}

function finishResult(mode, ok, message, state) {
  log(message);
  if (mode === "status") notify("PO0 状态", ok ? "可用" : "异常", statusMessage(state));
  if (mode === "force") notify("PO0 手动上报", ok ? "成功" : "拒绝或失败", message);
  finish();
}

async function run() {
  const args = getArgument();
  const mode = String(args.mode || "auto").toLowerCase();
  if (!["auto", "status", "force"].includes(mode)) throw new Error(`不支持的模式：${mode}`);

  let state = readJSON(PO0_STORE_KEY, {});
  if (mode === "status") {
    finishResult(mode, true, "status", state);
    return;
  }

  const network = classifyNetwork(readRuntimeConfig());
  if (!network.allowed) {
    finishResult(mode, false, network.reason, state);
    return;
  }

  const credentials = loadCredentials(args);
  const now = Date.now();
  const nowSeconds = Math.floor(now / 1000);
  if (canUseCachedTTL(mode, state, network, nowSeconds)) {
    finishResult(mode, true, "有效 TTL 内无需重复上报", state);
    return;
  }
  if (!acquireRunLock(mode, network.context, now)) {
    finishResult(mode, true, "去抖窗口内跳过重复触发", state);
    return;
  }

  const ip = await detectIPv4();
  const requestId = `${PO0_SOURCE_ID}-${nowSeconds}-${Math.random().toString(36).slice(2, 10)}`;
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
      "Authorization": `Bearer ${credentials.token}`,
      "Content-Type": "application/json",
      "User-Agent": PO0_USER_AGENT,
    },
    body: JSON.stringify(payload),
    timeout: 12_000,
  });

  const status = Number(result.response.status || result.response.statusCode || 0);
  let response;
  try {
    response = JSON.parse(result.data);
  } catch (_) {
    throw new Error(`LAN Worker 返回非 JSON（HTTP ${status || "?"}）`);
  }
  if (status < 200 || status >= 300 || !response.ok || !response.accepted_cidr) {
    throw new Error(response.error || `LAN Worker 拒绝请求（HTTP ${status || "?"}）`);
  }

  const acceptedAt = epochSeconds(response.accepted_at, nowSeconds);
  const expiresAt = epochSeconds(response.expires_at, nowSeconds + 12 * 60 * 60);
  const refreshTTL = boundedRefreshTTL(args);
  const nextRefreshAt = Math.max(
    nowSeconds,
    Math.min(acceptedAt + refreshTTL, expiresAt - PO0_EXPIRY_SAFETY_SECONDS),
  );
  state = {
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
  };
  writeJSON(PO0_STORE_KEY, state);
  finishResult(mode, true, `${state.accepted_cidr} · ${state.network}`, state);
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
