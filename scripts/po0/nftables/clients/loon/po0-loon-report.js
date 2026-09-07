function retiredMode(args, mode) {
  return args.channel === 'worker' || /worker|self-report|ssh-report/.test(mode);
}

function migrateRetiredState() {
  const key = PO0_STORE_KEY + '.official-only-v1';
  if (readStore(key)) return;
  // Keep the original raw values on this device. Never send them in reports.
  const backupKey = PO0_STORE_KEY + '.pre-retirement-v1';
  if (!readStore(backupKey) && !writeJSON(backupKey, {
    state: readStore(PO0_STORE_KEY),
    channels: readStore(PO0_STORE_KEY + '.channel-settings'),
    worker: readStore(PO0_STORE_KEY + '.worker-config'),
    official: readStore(PO0_STORE_KEY + '.official-config'),
  })) throw new Error('无法备份旧本机配置，升级已暂停');
  const settings = channelSettings();
  const clean = { version: 1 };
  for (const key of Object.keys(settings)) if (key.startsWith('official')) clean[key] = settings[key];
  saveChannelSettings(clean);
  const previous = readJSON(PO0_STORE_KEY, {});
  const state = previous.official ? { official: previous.official } : {};
  if (previous.detected_ip) state.detected_ip = previous.detected_ip;
  if (!writeJSON(PO0_STORE_KEY, state) || !writeStore(PO0_STORE_KEY + '.worker-config', '') || !writeStore(key, '1')) throw new Error('无法完成本机配置迁移，原配置已备份');
}

"use strict";

const PO0_STORE_KEY = "proxyconfig.po0.loon-report.v1";
const PO0_RUN_LOCK_KEY = `${PO0_STORE_KEY}.run-lock`;
const PO0_WORKER_TOKEN_KEY = "po0_worker_token";
const PO0_FIREWALL_TOKENS_KEY = "PO0_FIREWALL_TOKENS";
const PO0_LEGACY_SKIP_WIFI_SSIDS = "ZTE-47kTee";
const PO0_OFFICIAL_USER_AGENT = "ProxyConfig-PO0-Firewall/Loon";
const PO0_OFFICIAL_API_URL = "https://124.221.69.228/api/firewall";
// One persistent guard covers every report/status mode and network context.
// Loon exposes persistent storage but no atomic lock primitive, so a bounded
// expiry is the safest recoverable approximation for a whole run.
const PO0_RUN_LOCK_TTL_MS = 120_000;

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
  const args = parseArgument(typeof $argument === "undefined" ? "" : $argument);
  if (args.mode) return args; // Legacy string / JSON actions retain their explicit mode.
  const name = typeof $script === "undefined" ? "" : String($script.name || "");
  const modes = {
    "通用 · 查看本机配置": "settings",
    "通用 · 查看最近结果": "recent",
    "官方防火墙 · 查询官方白名单": "status",
    "通用 · 强制上报": "force",
    "自建防火墙 · 保存配置": "save-worker",
    "官方防火墙 · 保存配置": "save-official",
    "自建 PO0 · 保存本机设置": "save-worker",
    "通用 · 自动上报": "auto",
    "通用 · 网络变化上报": "auto",
    "通用 · 查看上报状态": "status",
    "通用 · 立即上报": "report",
    "官方防火墙 · 保存本机设置": "save-official",
    "自建防火墙 · 保存本机设置": "save-worker",
    "通用 · 查看本机设置": "settings",
  };
  if (!modes[name]) throw new Error("无法识别上报操作，请更新 PO0 插件");
  return Object.assign({}, args, { mode: modes[name] });
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

function skipWifiSsids(args) {
  // Legacy actions without this argument retain their previous skip rule.
  const raw = Object.prototype.hasOwnProperty.call(args, "SKIP_WIFI_SSIDS")
    ? args.SKIP_WIFI_SSIDS : PO0_LEGACY_SKIP_WIFI_SSIDS;
  return String(raw || "").split(/[;；\r\n]+/).map((item) => item.trim()).filter((item) => item && item !== "-");
}

function classifyNetwork(runtimeConfig, args) {
  const ssid = String(runtimeConfig.ssid || "").trim();
  const unknown = !ssid || /^(?:<?unknown(?: ssid)?>?|null|undefined|n\/a)$/i.test(ssid);
  if (unknown) {
    return { allowed: false, reason: "无法可靠识别 SSID，已按 fail-closed 跳过" };
  }
  if (skipWifiSsids(args).includes(ssid)) {
    return { allowed: false, home: true, ssid, reason: `Wi-Fi ${ssid} 命中跳过名单，两个通道均已跳过` };
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
      ssid: network.ssid,
      context: "wifi:" + network.ssid,
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


// These controls are device-local. Missing values retain the legacy behavior.
function channelSettings() {
  const raw = readStore(PO0_STORE_KEY + '.channel-settings');
  if (!raw) return {};
  let saved;
  try { saved = JSON.parse(raw); } catch (_) { throw new Error('本机通道设置损坏，请重新保存'); }
  if (!saved || saved.version !== 1) throw new Error('本机通道设置格式错误');
  return saved;
}

function saveChannelSettings(value) {
  if (!writeJSON(PO0_STORE_KEY + '.channel-settings', Object.assign({}, value, { version: 1 }))) throw new Error('无法保存本机通道设置');
}

function channelAllowed(args, mode, channel) {
  return channel === 'official' && (!args.channel || args.channel === 'official') && (mode !== 'auto' || channelSettings().officialAutoEnabled !== false);
}

// Keep legacy interval=0 as timer-off; absent values retain the old defaults.
function timerEnabled(channel, args = {}) {
  if (channel !== 'official') return false;
  const settings = channelSettings();
  if (reportInterval(settings.officialIntervalSeconds ?? args.official_report_interval_seconds) === 0) return false;
  return !/^(false|0|off|no)$/i.test(String(settings.officialTimerEnabled ?? args.official_timer_enabled));
}
function saveTimerSettings(settings, channel, args, previousInterval) {
  const seconds = reportInterval(args.official_report_interval_seconds ?? previousInterval);
  if (seconds === 0) settings.officialTimerEnabled = false;
  else if (args.official_timer_enabled !== undefined) settings.officialTimerEnabled = !/^(false|0|off|no)$/i.test(String(args.official_timer_enabled));
  if (args.official_auto_enabled !== undefined) settings.officialAutoEnabled = !/^(false|0|off|no)$/i.test(String(args.official_auto_enabled));
  return seconds || reportInterval(previousInterval) || 600;
}
function intervalLabel(channel, args = {}) {
  return (reportInterval(channelSettings().officialIntervalSeconds ?? args.official_report_interval_seconds) || 600) + ' 秒' + (timerEnabled('official', args) ? '' : '（暂不使用）');
}

function officialAccountName(index) {
  return String(channelSettings().officialNames || '').replace(/\r/g, '').split(/[;；\n]/)[index]?.trim() || '官方账号 ' + (index + 1);
}

function saveOfficialNames(args, tokens, clear) {
  const settings = channelSettings();
  const previous = readJSON(PO0_STORE_KEY + '.official-config', {});
  const oldTokens = String(previous.tokens || '').split(/[,;，；\s]+/).filter(Boolean);
  const oldNames = String(settings.officialNames || '').replace(/\r/g, '').split(/[;；\n]/);
  const input = String(args.PO0_FIREWALL_NAMES || '').trim();
  settings.officialNames = clear || input === '-' ? '' : input || parseFirewallTokens(tokens).map(item => {
    const index = oldTokens.findIndex(old => old.split('@')[0] === item.token);
    return index < 0 ? '' : oldNames[index] || '';
  }).join(';');
  if (!clear) settings.officialIntervalSeconds = saveTimerSettings(settings, 'official', args, settings.officialIntervalSeconds);
  if (clear) settings.officialAutoEnabled = false;
  saveChannelSettings(settings);
}

function isLocalSettingsMode(mode) {
  return ['toggle-official', 'toggle-official-timer', 'settings'].includes(mode);
}

function localSettingsSummary(args) {
  const settings = channelSettings();
  const saved = readJSON(PO0_STORE_KEY + '.official-config', null);
  const count = parseFirewallTokens(saved ? saved.tokens : firewallInput(args)).length;
  return [
    '官方防火墙：' + (count ? count + ' 个目标' : '未配置'),
    '目标名称：' + (settings.officialNames || '按账号编号显示'),
    '自动上报：' + (settings.officialAutoEnabled === false ? '已停用' : '已启用'),
    '启用定期上报：' + (timerEnabled('official', args) ? '是' : '否') + '；上报间隔：' + intervalLabel('official', args),
    networkSettingsSummary(args),
    '停用保留配置，手动上报仍可用；清除后同步参数不会自动恢复。',
  ].join('\n');
}

function runLocalSettingsAction(args, mode) {
  const settings = channelSettings();
  if (mode === 'toggle-official') settings.officialAutoEnabled = settings.officialAutoEnabled === false;
  if (mode === 'toggle-official-timer') {
    settings.officialTimerEnabled = !timerEnabled('official', args);
    if (settings.officialTimerEnabled && settings.officialIntervalSeconds === 0) settings.officialIntervalSeconds = 600;
  }
  if (mode !== 'settings') saveChannelSettings(settings);
  return (mode === 'settings' ? '' : '本机设置已更新。\n') + localSettingsSummary(args);
}

function firewallInput(args) {
  return firstNonEmpty([
    args.PO0_FIREWALL_TOKENS, args.po0_firewall_tokens, args.firewall_tokens,
    readStore(PO0_FIREWALL_TOKENS_KEY),
  ]);
}

function officialNetworkEnabled(args) {
  const saved = readJSON(PO0_STORE_KEY + '.official-config', null);
  return /^(true|1|on|yes)$/i.test(String(saved ? saved.networkTargetsEnabled : args.OFFICIAL_NETWORK_TARGETS_ENABLED));
}

function selectedFirewallTokens(args, network) {
  const raw = firewallRawValue(args);
  if (!officialNetworkEnabled(args)) return parseFirewallTokens(raw);
  if (!['wifi', 'cellular'].includes(network)) return [];
  const saved = readJSON(PO0_STORE_KEY + '.official-config', {});
  const tokens = parseFirewallTokens(network === 'wifi' ? saved.wifiTokens : raw);
  if (network === 'wifi') {
    const names = String(saved.wifiNames || '').replace(/\r/g, '').split(/[;；\n]/);
    tokens.forEach((item, index) => { item.networkName = names[index]?.trim() || '官方账号 ' + (index + 1); });
  }
  return tokens;
}

function networkSettingsSummary(args) {
  const saved = readJSON(PO0_STORE_KEY + '.official-config', {});
  return '官方按网络选择目标：' + (officialNetworkEnabled(args) ? '开启；原目标用于蜂窝，Wi-Fi ' + parseFirewallTokens(saved.wifiTokens).length + ' 个目标' : '关闭；使用原目标');
}

function saveLocalFirewall(args, clear) {
  const input = clear ? "" : firewallInput(args) || String(readJSON(PO0_STORE_KEY + '.official-config', {}).tokens || '');
  const tokens = input === "-" ? "" : input;
  parseFirewallTokens(tokens);
  const previous = readJSON(PO0_STORE_KEY + '.official-config', {});
  const config = { version: 1, tokens };
  if (!(clear || input === '-')) {
    const enabled = args.OFFICIAL_NETWORK_TARGETS_ENABLED ?? previous.networkTargetsEnabled;
    const wifiInput = String(args.PO0_FIREWALL_WIFI_TOKENS || '').trim();
    const wifiTokens = wifiInput === '-' ? '' : wifiInput || previous.wifiTokens || '';
    const wifiNames = String(args.PO0_FIREWALL_WIFI_NAMES || '').trim();
    if (enabled !== undefined || wifiTokens) {
      config.networkTargetsEnabled = /^(true|1|on|yes)$/i.test(String(enabled));
      config.wifiTokens = wifiTokens;
      const wifiItems = parseFirewallTokens(wifiTokens);
      const previousItems = parseFirewallTokens(previous.wifiTokens);
      const previousNames = String(previous.wifiNames || '').replace(/\r/g, '').split(/[;；\n]/);
      config.wifiNames = wifiNames === '-' ? '' : wifiNames || wifiItems.map(item => {
        const index = previousItems.findIndex(old => old.token === item.token);
        return index < 0 ? '' : previousNames[index] || '';
      }).join(';');
      if (config.networkTargetsEnabled && !wifiTokens) throw new Error('开启按网络选择目标前，请填写 Wi-Fi 官方上报目标');
    }
  }
  saveOfficialNames(args, tokens, clear || input === "-");
  if (!writeJSON(PO0_STORE_KEY + ".official-config", config)) throw new Error("无法保存本机官方配置");
  if (clear || input === '-' || previous.tokens !== tokens || previous.wifiTokens !== config.wifiTokens || previous.networkTargetsEnabled !== config.networkTargetsEnabled) {
    const state = readJSON(PO0_STORE_KEY, {});
    delete state.official;
    if (!writeJSON(PO0_STORE_KEY, state)) throw new Error('配置已清除，但最近状态未能清除');
  }
  return tokens;
}

function firewallRawValue(args) {
  // Module parameters may arrive from iCloud. A saved device choice wins;
  // only the explicit save/clear actions can replace it, including a clear.
  const saved = readStore(PO0_STORE_KEY + ".official-config");
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
  const items = text.split(/[,;，；\s]+/).filter(Boolean);

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
    name: item.networkName || officialAccountName(index - 1),
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
  text += " · " + official.accounts.map(account => account.name || ("官方账号 " + account.account)).join(" / ");
  if (official.network) text += " · " + official.network;
  if (missing) text += " · 未命中 " + missing;
  if (added) text += " · 新增 " + added;
  if (official.last_error) text += " · 最近失败";
  if (channelSettings().officialAutoEnabled === false) text += " · 自动已停用";
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

function officialDue(mode, state, nowSeconds, args = {}) {
  if (mode === "force" || mode === "report") return true;
  if (mode !== "auto") return false;
  if (isNetworkTrigger(args)) return true;
  if (!timerEnabled('official', args)) return false;
  const interval = reportInterval(channelSettings().officialIntervalSeconds ?? args.official_report_interval_seconds);
  if (interval === 0) return false;
  const last = Number(state && state.last_attempt_at || 0);
  return !last || nowSeconds < last || nowSeconds - last >= interval;
}
function reportInterval(value) {
  if (value === undefined || value === null || value === '') return 600;
  const n = Number(value);
  if (!Number.isInteger(n) || (n !== 0 && (n < 60 || n > 86400))) throw new Error('上报间隔须为 60..86400 秒；兼容旧值 0（关闭定期上报）');
  return n;
}
function isNetworkTrigger(args) {
  return args.trigger === 'network' || (typeof $script !== 'undefined' && /network-changed|网络变化/i.test(String($script.type || '') + ' ' + String($script.name || '')));
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
  return officialSummary(state && state.official);
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
  if (mode === "status" || mode === "recent") notify("PO0 状态", ok ? "可用" : "异常", statusMessage(state));
  if (mode === "force") notify("PO0 手动上报", ok ? "成功" : "拒绝或失败", message);
  if (mode === "auto" && (!ok || Number(details.added || 0) > 0)) {
    notify("PO0 自动上报", ok ? "新增官方白名单" : "部分失败", message);
  }
  finish();
}


async function runUnlocked() {
  const args = getArgument();
  const mode = String(args.mode || "auto").toLowerCase();
  if (retiredMode(args, mode)) { notify('PO0', '功能已退役', '自建防火墙功能已退役；旧版可从归档恢复'); finish(); return; }
  migrateRetiredState();
  if (mode === 'recent') { finishResult(mode, true, officialSummary(readJSON(PO0_STORE_KEY, {}).official), readJSON(PO0_STORE_KEY, {})); return; }
  if (isLocalSettingsMode(mode)) {
    const message = runLocalSettingsAction(args, mode);
    notify("PO0 本机设置", "通道管理", message); finish(); return;
  }
  if (mode === "save-official" || mode === "clear-official") {
    saveLocalFirewall(args, mode === "clear-official");
    notify("PO0 本机官方配置", "已保存", mode === "clear-official" ? "本机配置已清除；同步参数不会自动恢复它" : "Token 和槽位已保存；后续同步参数不会覆盖");
    finish();
    return;
  }
  if (!["auto", "status", "force", "report", "recent"].includes(mode)) throw new Error("不支持的模式：" + mode);

  let state = readJSON(PO0_STORE_KEY, {});
  if (!state || typeof state !== "object" || Array.isArray(state)) state = {};
  const now = Date.now();
  const nowSeconds = Math.floor(now / 1000);

  if (mode === "auto" && !channelAllowed(args, mode, "official")) {
    finishResult(mode, true, "官方自动上报已停用，配置保留", state); return;
  }

  if (mode === "status") {
    firewallRawValue(args);
    const kind = officialNetworkEnabled(args) ? forceNetwork(classifyNetwork(readRuntimeConfig(), args)).network : undefined;
    const tokens = selectedFirewallTokens(args, kind);
    if (officialNetworkEnabled(args) && kind === 'unknown') { finishResult(mode, false, '无法识别当前网络，已跳过官方查询', state); return; }
    if (!tokens.length) {
      finishResult(mode, true, "status", state);
      return;
    }
    const officialResult = await runOfficial(tokens, mode, kind && state.official?.network !== kind ? {} : state.official || {}, nowSeconds);
    state.official = officialResult.official;
    if (kind) state.official.network = kind;
    if (!officialResult.ok) state.last_error = officialResult.official.last_error;
    writeJSON(PO0_STORE_KEY, state);
    finishResult(mode, officialResult.ok, officialSummary(state.official), state, officialResult);
    return;
  }

  if (!parseFirewallTokens(firewallRawValue(args)).length) { finishResult(mode, true, '尚未配置官方上报目标', state); return; }
  const classified = classifyNetwork(readRuntimeConfig(), args);
  if (!classified.allowed && mode !== "force") {
    finishResult(mode, false, classified.reason, state);
    return;
  }
  const network = mode === "force" ? forceNetwork(classified) : classified;
  const tokens = channelAllowed(args, mode, "official") ? selectedFirewallTokens(args, network.network) : [];
  const unknownOfficialNetwork = channelAllowed(args, mode, 'official') && officialNetworkEnabled(args) && network.network === 'unknown';
  const officialNetworkChanged = officialNetworkEnabled(args) && state.official?.network !== network.network;
  const needsOfficial = tokens.length > 0 && officialDue(mode, state.official || {}, nowSeconds, officialNetworkChanged ? Object.assign({}, args, { trigger: 'network' }) : args);
  if (!needsOfficial && !unknownOfficialNetwork) {
    finishResult(mode, true, "尚未到上报间隔，无需重复上报", state);
    return;
  }
  let officialResult = { ok: !unknownOfficialNetwork, added: 0, attempted: false, official: unknownOfficialNetwork ? { last_error: '无法识别当前网络，已跳过官方上报' } : undefined };
  if (tokens.length && (needsOfficial || mode === "force")) {
    officialResult = await runOfficial(tokens, mode, state.official || {}, nowSeconds);
    state.official = officialResult.official;
    state.official.network = network.network;
  }

  const ok = officialResult.ok;
  const message = unknownOfficialNetwork ? '无法识别当前网络，已跳过官方上报' : officialResult.attempted ? officialSummary(state.official) : '尚未到上报间隔，无需重复上报';
  state.last_error = ok ? '' : officialResult.official && officialResult.official.last_error || '官方上报失败';
  writeJSON(PO0_STORE_KEY, state);
  finishResult(mode, ok, message, state, { added: officialResult.added });
}

async function run() {
  const args = getArgument();
  const mode = String(args.mode || 'auto').toLowerCase();

  if (mode === 'recent' || mode === 'settings' || retiredMode(args, mode)) return runUnlocked();
  const lock = acquireRunLock(mode, 'official', Date.now());
  if (!lock) { finishResult(mode, true, '已有上报任务运行，已跳过重复触发', readJSON(PO0_STORE_KEY, {}), {}); return; }
  try { return await runUnlocked(); } finally { releaseRunLock(lock); }
}

run().catch((error) => {
  const args = getArgument();
  const mode = String(args.mode || "auto").toLowerCase();
  if (mode === 'recent') { finishResult(mode, true, officialSummary(readJSON(PO0_STORE_KEY, {}).official), readJSON(PO0_STORE_KEY, {})); return; }
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
