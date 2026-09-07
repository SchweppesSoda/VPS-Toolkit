function retiredMode(args, mode) {
  return args.channel === 'worker' || /worker|self-report|ssh-report/.test(mode);
}

function migrateRetiredState() {
  const key = STORE_KEY + '.official-only-v1';
  if (readStore(key)) return;
  // Keep the original raw values on this device. Never send them in reports.
  const backupKey = STORE_KEY + '.pre-retirement-v1';
  if (!readStore(backupKey) && !writeJSON(backupKey, {
    state: readStore(STORE_KEY),
    channels: readStore(STORE_KEY + '.channel-settings'),
    worker: readStore(STORE_KEY + '.worker-config'),
    official: readStore(STORE_KEY + '.official-config'),
  })) throw new Error('无法备份旧本机配置，升级已暂停');
  const settings = channelSettings();
  const clean = { version: 1 };
  for (const key of Object.keys(settings)) if (key.startsWith('official')) clean[key] = settings[key];
  saveChannelSettings(clean);
  const previous = readJSON(STORE_KEY, {});
  const state = previous.official ? { official: previous.official } : {};
  if (previous.detected_ip) state.detected_ip = previous.detected_ip;
  if (!writeJSON(STORE_KEY, state) || !writeStore(STORE_KEY + '.worker-config', '') || !writeStore(key, '1')) throw new Error('无法完成本机配置迁移，原配置已备份');
}

const STORE_KEY = "proxyconfig.po0.stash-report.v1";
const RUN_LOCK_KEY = STORE_KEY + ".run-lock";
const NETWORK_GROUP = "📡 PO0 网络识别（自动）";
const FORCE_URL = "http://po0-report.invalid/report-now";
const FIREWALL_TOKENS_KEY = "PO0_FIREWALL_TOKENS";
const OFFICIAL_API_URL = "https://124.221.69.228/api/firewall";
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

// These controls are device-local. Missing values retain the legacy behavior.
function channelSettings() {
  const raw = readStore(STORE_KEY + '.channel-settings');
  if (!raw) return {};
  let saved;
  try { saved = JSON.parse(raw); } catch (_) { throw new Error('本机通道设置损坏，请重新保存'); }
  if (!saved || saved.version !== 1) throw new Error('本机通道设置格式错误');
  return saved;
}

function saveChannelSettings(value) {
  if (!writeJSON(STORE_KEY + '.channel-settings', Object.assign({}, value, { version: 1 }))) throw new Error('无法保存本机通道设置');
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
  const previous = readJSON(STORE_KEY + '.official-config', {});
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
  const saved = readJSON(STORE_KEY + '.official-config', null);
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
    readStore(FIREWALL_TOKENS_KEY),
  ]);
}

function officialNetworkEnabled(args) {
  const saved = readJSON(STORE_KEY + '.official-config', null);
  return /^(true|1|on|yes)$/i.test(String(saved ? saved.networkTargetsEnabled : args.OFFICIAL_NETWORK_TARGETS_ENABLED));
}

function selectedFirewallTokens(args, network) {
  const raw = firewallRawValue(args);
  if (!officialNetworkEnabled(args)) return parseFirewallTokens(raw);
  if (!['wifi', 'cellular'].includes(network)) return [];
  const saved = readJSON(STORE_KEY + '.official-config', {});
  const tokens = parseFirewallTokens(network === 'wifi' ? saved.wifiTokens : raw);
  if (network === 'wifi') {
    const names = String(saved.wifiNames || '').replace(/\r/g, '').split(/[;；\n]/);
    tokens.forEach((item, index) => { item.networkName = names[index]?.trim() || '官方账号 ' + (index + 1); });
  }
  return tokens;
}

function networkSettingsSummary(args) {
  const saved = readJSON(STORE_KEY + '.official-config', {});
  return '官方按网络选择目标：' + (officialNetworkEnabled(args) ? '开启；原目标用于蜂窝，Wi-Fi ' + parseFirewallTokens(saved.wifiTokens).length + ' 个目标' : '关闭；使用原目标');
}

function saveLocalFirewall(args, clear) {
  const input = clear ? "" : firewallInput(args) || String(readJSON(STORE_KEY + '.official-config', {}).tokens || '');
  const tokens = input === "-" ? "" : input;
  parseFirewallTokens(tokens);
  const previous = readJSON(STORE_KEY + '.official-config', {});
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
  if (!writeJSON(STORE_KEY + ".official-config", config)) throw new Error("无法保存本机官方配置");
  if (clear || input === '-' || previous.tokens !== tokens || previous.wifiTokens !== config.wifiTokens || previous.networkTargetsEnabled !== config.networkTargetsEnabled) {
    const state = readJSON(STORE_KEY, {});
    delete state.official;
    if (!writeJSON(STORE_KEY, state)) throw new Error('配置已清除，但最近状态未能清除');
  }
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
    if (tokens.length > MAX_FIREWALL_TOKENS) throw new Error("PO0 官方防火墙 token 数量超过上限");
  }
  return tokens;
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

async function detectNetwork(split = false) {
  if (split) {
    // Complementary SSID policies: exactly one probe must succeed. An outage,
    // missing groups, or a switch during the probes must not be guessed as cellular.
    const probes = await Promise.all(['📡 PO0 Wi-Fi 探测', '📡 PO0 蜂窝探测'].map(async group => {
      try {
        const result = await request('get', { url: 'https://www.gstatic.com/generate_204', headers: selectedHeaders(group), timeout: 5, 'auto-redirect': false });
        return responseStatus(result) === 204;
      } catch (_) { return false; }
    }));
    return probes[0] === probes[1] ? 'unknown' : probes[0] ? 'wifi' : 'cellular';
  }
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
  text += " · " + official.accounts.map(account => account.name || ("官方账号 " + account.account)).join(" / ");
  if (official.network) text += " · " + official.network;
  if (missing) text += " · 未命中 " + missing;
  if (added) text += " · 新增 " + added;
  if (official.last_error) text += " · 最近失败";
  if (channelSettings().officialAutoEnabled === false) text += " · 自动已停用";
  return text;
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


function tile(state) {
  const official = state && state.official;
  const accounts = official && Array.isArray(official.accounts) ? official.accounts : [];
  const errors = accounts.some(account => account.status === 'error');
  return { title: 'PO0 官方防火墙', content: officialSummary(official),
    icon: errors ? 'exclamationmark.triangle.fill' : 'checkmark.shield.fill',
    backgroundColor: errors ? '#b45309' : accounts.length ? '#178f55' : '#6b7280', url: FORCE_URL };
}

function escapeHtml(value) {
  return String(value == null ? '' : value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}

function htmlResult(ok, message, state, mode) {
  const heading = mode === 'settings' ? '本机设置' : mode === 'status' ? '上报状态' : ok ? '操作完成' : '操作未完成';
  const link = (path, label, danger) => '<a class="action' + (danger ? ' danger' : '') + '" href="http://po0-report.invalid/' + path + '"' + (danger ? ' onclick="return confirm(\'确认清除此通道的本机保存配置？\')"' : '') + '>' + label + '</a>';
  return '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>PO0 · ' + heading + '</title>' +
    '<style>body{margin:0;background:#f4f6f9;color:#172333;font:16px/1.65 -apple-system,sans-serif}main{max-width:680px;margin:auto;padding:28px 18px 48px}h1{font-size:28px;margin:4px 0}h2{font-size:18px;margin:0 0 12px}.eyebrow{font-size:12px;letter-spacing:2px;color:#59718c}.card{background:white;border:1px solid #e0e6ee;border-radius:16px;padding:20px;margin:16px 0}.detail{white-space:pre-wrap;overflow-wrap:anywhere}.actions{display:flex;gap:8px;flex-wrap:wrap}.action{display:block;background:#edf3fa;color:#245581;text-decoration:none;padding:10px 14px;border-radius:10px;font-size:14px}.danger{color:#a13535;background:#fceded}.muted{color:#637286;font-size:13px}</style>' +
    '<main><div class="eyebrow">PO0 · 出口上报</div><h1>' + heading + '</h1><p class="muted">官方上报独立计时；每 60 秒轮询检测出口 IP 变化。</p>' +
    '<section class="card"><h2>' + (ok ? '✓ ' : '！ ') + heading + '</h2><div class="detail">' + escapeHtml(message === 'status' ? officialSummary(state && state.official) : message) + '</div></section>' +
    '<section class="card"><h2>官方防火墙</h2><div class="actions">' + link('save-official','保存配置') + link('toggle-official-timer','启用 / 停用定期上报') + link('toggle-official','停用 / 恢复自动') + link('official-now','立即上报') + link('official-force','强制上报') + link('clear-official','清除本机配置',true) + '</div><p class="muted">Token、名称、定期开关和上报间隔在模块的 /save-official 参数中填写；上报间隔默认 600 秒；关闭定期上报保留原间隔；出口变化由每分钟轮询检测。</p></section>' +
    '<div class="actions">' + link('settings','查看本机配置') + link('recent','查看最近结果') + link('status','查询官方白名单') + link('report','立即上报') + link('report-now','强制上报') + '<a class="action" href="stash://">返回 Stash</a></div><p class="muted">Stash 公开脚本接口不提供当前 SSID，因此此客户端没有 SSID 跳过名单。</p></main></html>';
}

function finish(mode, ok, message, state, meta) {
  const details = meta || {};
  if ($script.type === "tile") return $done(tile(state));
  if (mode === "status") {
    if ($script.type === "request") {
      return $done({ response: { status: ok ? 200 : 502, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" }, body: htmlResult(ok, message, state, mode) } });
    }
    return $done(tile(state));
  }
  if (mode === "auto" && (!ok || Number(details.added || 0) > 0)) {
    $notification.post("PO0 自动上报", ok ? "新增官方白名单" : "部分失败", message);
  }
  if ($script.type === "request" || mode === "force") {
    if (mode === "force") $notification.post("PO0 上报", ok ? "成功" : "失败", message);
    return $done({ response: { status: ok ? 200 : 502, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" }, body: htmlResult(ok, message, state, mode) } });
  }
  return $done();
}

async function runUnlocked() {
  const args = parseArgument();
  const mode = $script.type === "tile" ? "status" : String(args.mode || "auto").toLowerCase();
  if (retiredMode(args, mode)) { return finish('settings', true, '自建防火墙功能已退役；旧版可从归档恢复', {}, {}); }
  migrateRetiredState();
  if (mode === 'recent') return finish(mode, true, officialSummary(readJSON(STORE_KEY, {}).official), readJSON(STORE_KEY, {}), {});
  if (isLocalSettingsMode(mode)) {
    const message = runLocalSettingsAction(args, mode);
    return finish("settings", true, message, readJSON(STORE_KEY, {}), {});
  }
  if (mode === "save-official" || mode === "clear-official") {
    saveLocalFirewall(args, mode === "clear-official");
    return finish("force", true, mode === "clear-official" ? "已清除本机官方配置；同步参数不会自动恢复它" : "已保存本机官方 Token 和槽位；后续同步参数不会覆盖", readJSON(STORE_KEY, {}), {});
  }
  if (["auto", "status", "force", "report", "recent", "save-official", "clear-official"].indexOf(mode) < 0) throw new Error("不支持的模式：" + mode);
  let state = readJSON(STORE_KEY, {});
  if (!state || typeof state !== "object" || Array.isArray(state)) state = {};
  const now = Date.now();
  const nowSeconds = Math.floor(now / 1000);

  if (mode === "auto" && !channelAllowed(args, mode, "official")) {
    return finish(mode, true, "官方自动上报已停用，配置保留", state, {});
  }

  if (mode === "status") {
    firewallRawValue(args);
    const kind = officialNetworkEnabled(args) ? await detectNetwork(true) : undefined;
    const tokens = selectedFirewallTokens(args, kind);
    if (officialNetworkEnabled(args) && kind === 'unknown') return finish(mode, false, '无法识别当前网络，已跳过官方查询', state, {});
    if (!tokens.length) return finish(mode, true, "status", state, {});
    const officialResult = await runOfficial(tokens, mode, kind && state.official?.network !== kind ? {} : state.official || {}, nowSeconds);
    state.official = officialResult.official;
    if (kind) state.official.network = kind;
    if (!officialResult.ok) state.last_error = officialResult.official.last_error;
    writeJSON(STORE_KEY, state);
    return finish(mode, officialResult.ok, officialSummary(state.official), state, officialResult);
  }

  // Validate official credentials before any network probe so malformed or
  // duplicate-account input fails closed without touching the network.
  if (channelAllowed(args, mode, 'official')) parseFirewallTokens(firewallRawValue(args));
  if (!parseFirewallTokens(firewallRawValue(args)).length) { return finish(mode, true, '尚未配置官方上报目标', state, {}); }
  const detectedNetwork = officialNetworkEnabled(args) ? await detectNetwork(true) : 'default';
  const tokens = channelAllowed(args, mode, 'official') ? selectedFirewallTokens(args, detectedNetwork) : [];
  const unknownOfficialNetwork = channelAllowed(args, mode, 'official') && officialNetworkEnabled(args) && detectedNetwork === 'unknown';
  const officialNetworkChanged = officialNetworkEnabled(args) && state.official?.network !== detectedNetwork;
  if (detectedNetwork === "unknown" && mode !== "force") {
    return finish(mode, false, "无法可靠识别网络，已按 fail-closed 跳过", state, {});
  }
  const network = { network: detectedNetwork, context: detectedNetwork };
  // Stash has no documented network event or current SSID API. Poll the direct
  // public IPv4 instead; never present this as an instantaneous network callback.
  if (mode === 'auto') {
    args.detected_ip = await detectIPv4();
    if (!(state.detected_ip || state.ip) || (state.detected_ip || state.ip) !== args.detected_ip) args.trigger = 'network';
    state.detected_ip = args.detected_ip;
  }
  const needsOfficial = tokens.length > 0 && officialDue(mode, state.official || {}, nowSeconds, officialNetworkChanged ? Object.assign({}, args, { trigger: 'network' }) : args);

  let officialResult = { ok: !unknownOfficialNetwork, added: 0, attempted: false, official: unknownOfficialNetwork ? { last_error: '无法识别当前网络，已跳过官方上报' } : undefined };
  if (tokens.length && (needsOfficial || mode === "force")) {
    officialResult = await runOfficial(tokens, mode, state.official || {}, nowSeconds);
    state.official = officialResult.official;
    state.official.network = network.network;
  }

  const ok = officialResult.ok;
  const message = unknownOfficialNetwork ? '无法识别当前网络，已跳过官方上报' : officialResult.attempted ? officialSummary(state.official) : '尚未到上报间隔，无需重复上报';
  state.last_error = ok ? '' : officialResult.official && officialResult.official.last_error || '官方上报失败';
  writeJSON(STORE_KEY, state);
  return finish(mode, ok, message, state, { added: officialResult.added });
}

async function run() {
  const args = parseArgument();
  const mode = String(args.mode || 'auto').toLowerCase();
  if ($script.type === "tile") return $done(tile(readJSON(STORE_KEY, {})));
  if (mode === 'recent' || mode === 'settings' || retiredMode(args, mode)) return runUnlocked();
  const lock = acquireRunLock(mode, 'official', Date.now());
  if (!lock) { return finish(mode, true, '已有上报任务运行，已跳过重复触发', readJSON(STORE_KEY, {}), {}); return; }
  try { return await runUnlocked(); } finally { releaseRunLock(lock); }
}

run().catch((error) => {
  const args = parseArgument();
  const mode = $script.type === "tile" ? "status" : String(args.mode || "auto").toLowerCase();
  if (mode === 'recent') return finish(mode, true, officialSummary(readJSON(STORE_KEY, {}).official), readJSON(STORE_KEY, {}), {});
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
