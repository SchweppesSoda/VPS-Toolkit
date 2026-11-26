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
  if (!writeJSON(STORE_KEY, state) || !writeStore(STORE_KEY + '.worker-config', '') || !writeStore(key, '1')) throw new Error('无法完成本机配置迁移，原配置已备份');
}

const STORE_KEY = "proxyconfig.po0.stash-report.v1";
const RUN_LOCK_KEY = STORE_KEY + ".run-lock";
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
  const oldTokens = parseFirewallTokens(previous.tokens);
  const oldNames = String(settings.officialNames || '').replace(/\r/g, '').split(/[;；\n]/);
  const input = String(args.PO0_FIREWALL_NAMES || '').trim();
  settings.officialNames = clear || input === '-' ? '' : input || parseFirewallTokens(tokens).map(item => {
    if (item.name) return item.name;
    const index = oldTokens.findIndex(old => old.token === item.token);
    return index < 0 ? '' : oldNames[index] || '';
  }).join(';');
  if (!clear) {
    if (args.SKIP_WIFI_SSIDS !== undefined) settings.officialSkipSsids = String(args.SKIP_WIFI_SSIDS).split(';').map(name => name.trim()).filter(Boolean);
    for (const key of ['NOTIFY_SUCCESS', 'NOTIFY_FAILURE']) {
      if (args[key] !== undefined) settings[key] = /^(true|1|on|yes)$/i.test(String(args[key]));
    }
  } else {
    delete settings.officialSkipSsids;
    delete settings.NOTIFY_SUCCESS;
    delete settings.NOTIFY_FAILURE;
  }
  if (!clear) settings.officialIntervalSeconds = saveTimerSettings(settings, 'official', args, settings.officialIntervalSeconds);
  if (clear) settings.officialAutoEnabled = false;
  saveChannelSettings(settings);
}

function isLocalSettingsMode(mode) {
  return ['toggle-official', 'toggle-official-timer'].includes(mode);
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
    '跳过的 Wi-Fi：' + ((settings.officialSkipSsids || []).join('; ') || '未设置'),
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
  saveChannelSettings(settings);
  return '本机设置已更新。\n' + localSettingsSummary(args);
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
    tokens.forEach((item, index) => { item.networkName = names[index]?.trim() || item.name || '官方账号 ' + (index + 1); });
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
        if (item.name) return item.name;
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
    delete state.notice;
    delete state.notice_at;
    delete state.last_error;
    delete state.last_error_at;
    if (!tokens) state.notice = '尚未配置账号';
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
  const items = text.split(/[,;，；\r\n]+/).flatMap(row => row.includes('|') ? [row.trim()] : row.split(/\s+/)).filter(Boolean);
  const tokens = [];
  const seen = [];
  for (const rawItem of items) {
    const [item, name = '', ...extra] = rawItem.split('|').map(value => value.trim());
    if (extra.length) throw new Error('账号格式为 Token@槽位|名称，间隔由定期上报设置控制');
    const match = item.match(/^(pgnfw_[A-Za-z0-9._~-]{1,240})(?:@([0-9]))?$/);
    if (!match) {
      throw new Error("PO0 防火墙 token 配置无效：请使用 pgnfw_...，槽位可写为 @0 到 @9");
    }
    const token = match[1];
    const fixedSlot = match[2] === undefined ? null : Number(match[2]);
    // A token identifies one official account; slot hints are not separate accounts.
    const key = token;
    if (seen.indexOf(key) >= 0) throw new Error("PO0 防火墙 token 列表包含重复项");
    seen.push(key);
    tokens.push({ token, fixedSlot, name });
    if (tokens.length > MAX_FIREWALL_TOKENS) throw new Error("PO0 防火墙 token 数量超过上限");
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

async function reportNetwork(args, split) {
  // Stash 5's authenticated local control API returns {interface, ssid}.
  if (typeof $httpAPI === 'function') {
    try {
      const info = await $httpAPI('GET', '/diagnosis/network');
      const type = String(info?.interface || '').trim().toLowerCase().replace('-', '');
      const kind = ['wifi', 'cellular'].includes(type) ? type : 'unknown';
      const ssid = kind === 'wifi' && typeof info.ssid === 'string' ? info.ssid.trim() : '';
      return { kind, ssid: /^(?:<redacted>|redacted)$/i.test(ssid) ? '' : ssid };
    } catch (_) { return { kind: 'unknown', ssid: '' }; }
  }

  // Older clients can still select saved network targets through their SSID policies.
  if (!split) return { kind: 'unknown', ssid: '' };
  const groups = [args.PO0_PROBE_WIFI_GROUP || '📡 PO0 Wi-Fi 探测', args.PO0_PROBE_CELLULAR_GROUP || '📡 PO0 蜂窝探测'];
  const [wifi, cellular] = await Promise.all(groups.map(async group => {
    try {
      const result = await request('get', { url: 'https://www.gstatic.com/generate_204', headers: selectedHeaders(group), timeout: 5, 'auto-redirect': false });
      return responseStatus(result) === 204;
    } catch (_) { return false; }
  }));
  return { kind: wifi === cellular ? 'unknown' : wifi ? 'wifi' : 'cellular', ssid: '' };
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
  if (typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= 9) return value;
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
  if (!Number.isInteger(body.limit) || body.limit < 1 || body.limit > 10) {
    throw new Error("官方防火墙名额无效");
  }
  if (!Array.isArray(body.whitelist) || body.whitelist.length > body.limit || body.whitelist.length > 10) {
    throw new Error("官方防火墙白名单状态无效");
  }
  const slots = [];
  const whitelist = body.whitelist.map((entry) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry) || !validIPv4Cidr24(entry.ip)) {
      throw new Error("官方防火墙白名单 IP 无效");
    }
    const slot = normalizeSlot(entry.slot);
    if (slot !== null) {
      if (slot >= body.limit) throw new Error("官方白名单槽位超出账号额度");
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
      "X-Stash-Selected-Proxy": "DIRECT",
    },
    "auto-redirect": false,
    timeout: 20,
  });
}

function coveredRow(response, item) {
  const subnet = response.currentIp.split('.').slice(0, 3).map(Number).join('.');
  const rows = response.whitelist.filter(row => row.ip.split('.').slice(0, 3).map(Number).join('.') === subnet);
  return rows.find(row => item.fixedSlot === null || row.slot === item.fixedSlot) || rows[0];
}

function officialAccountState(index, item, response, nowSeconds, status, added, error, covered) {
  return {
    name: item.networkName || officialAccountName(index - 1),
    account: index,
    fixed_slot: item.fixedSlot,
    covered_slot: covered?.slot ?? null,
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
  return redactDisplayText(message);
}

function redactDisplayText(message) {
  return message
    .replace(/pgnfw_[A-Za-z0-9._~-]+/g, "[REDACTED]")
    .replace(/Bearer\s+[^\s,;]+/gi, "Bearer [REDACTED]");
}

function officialSummary(official) {
  if (!official || !Array.isArray(official.accounts) || !official.accounts.length) return "尚无官方结果";
  const ok = official.accounts.filter((account) => account.status === "ok").length;
  const missing = official.accounts.filter((account) => account.status === "missing" || account.status === "slot-mismatch").length;
  const added = official.accounts.filter((account) => account.added).length;
  let text = "官方防火墙 " + ok + "/" + official.accounts.length + " · 已用状态已保存";
  const first = official.accounts.find((account) => account.status !== "error");
  if (first) {
    text += " · 当前 " + (first.current || "-") + " · " + first.used + "/" + first.limit;
    if (first.status === 'ok' && first.covered_slot !== undefined) {
      const slot = first.covered_slot === null ? '自动槽位' : '#' + (first.covered_slot + 1);
      text += ' · ' + (first.fixed_slot != null && first.fixed_slot !== first.covered_slot ? '共用 ' : '命中 ') + slot;
    }
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
    function checked(result, phase) {
      const response = parseOfficialResponse(result, phase);
      if (item.fixedSlot !== null && item.fixedSlot >= response.limit) throw new Error("指定槽位超出账号额度，请调整固定槽位");
      return response;
    }
    function outcome(response, row, added = false) {
      const written = added && (item.fixedSlot === null || item.fixedSlot === row.slot);
      return { account: officialAccountState(index + 1, item, response, nowSeconds, row ? 'ok' : 'missing', written, '', row), added: written };
    }
    const status = checked(await officialRequest(item, 'status'), '状态');
    const hit = coveredRow(status, item);
    if (hit || mode === 'status') return outcome(status, hit);

    const write = await officialRequest(item, 'add');
    if (responseStatus(write) === 403) {
      // Another device may have covered this subnet between our GET and POST.
      let confirmed;
      try { confirmed = checked(await officialRequest(item, 'status'), '复查'); } catch (_) {}
      const shared = confirmed && coveredRow(confirmed, item);
      if (shared) return outcome(confirmed, shared);
      throw new Error('官方防火墙加白被拒绝（HTTP 403），复查未确认放行');
    }
    const updated = checked(write, '加白');
    const row = coveredRow(updated, item);
    if (!row) throw new Error('加白后未确认当前出口网段');
    return outcome(updated, row, true);
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


// Also embedded in the collapsed Tile so Stash can render it synchronously, offline.
function panelOverview(state, settings) {
  const data = state.official || {};
  const accounts = Array.isArray(data.accounts) ? data.accounts.map(a => a && typeof a === 'object' && !Array.isArray(a) ? a : {}) : [];
  const total = accounts.length;
  const count = status => accounts.filter(a => a.status === status).length;
  const hits = count('ok'), failed = count('error'), missing = count('missing'), mismatch = count('slot-mismatch');
  const pending = total - hits - failed - missing - mismatch;
  const unconfigured = state.notice === '尚未配置账号';
  let headline = '等待首次检查', tone = 'idle';
  if (total && hits === total) { headline = data.last_error ? '检查有异常' : '全部放行'; tone = data.last_error ? 'warn' : 'good'; }
  else if (hits) { headline = '部分放行'; tone = 'warn'; }
  else if ((failed && failed === total) || (!total && data.last_error)) { headline = '检查失败'; tone = 'bad'; }
  else if (missing && missing === total) { headline = '均未放行'; tone = 'warn'; }
  else if (total) { headline = '尚未确认放行'; tone = 'warn'; }
  else if (unconfigured) headline = '尚未配置账号';

  const issues = [[failed, '检查失败'], [missing, '未放行'], [mismatch, '槽位不匹配'], [pending, '待确认']]
    .filter(([n]) => n).map(([n, label]) => n + ' 个' + label);
  if (data.last_error && !failed && total) issues.push('检查有异常');
  const tally = hits + '/' + total + ' 个账号已放行';
  let result = headline;
  if (hits) result = tally;
  else if (total && failed === total) result = total + ' 个账号检查失败';
  else if (total && missing === total) result = total + ' 个账号未放行';
  else if (total) result = total + ' 个账号尚未确认放行';
  const network = data.network === 'wifi' ? 'Wi-Fi' : data.network === 'cellular' ? '蜂窝' : '';
  function localTime(seconds) {
    const date = new Date(Number(seconds) * 1000);
    if (!(date.getTime() > 0)) return '';
    const today = new Date(Date.now());
    const day = date.getDate(), month = date.getMonth() + 1;
    const year = date.getFullYear() === today.getFullYear() ? '' : date.getFullYear() + '/';
    return (date.toDateString() === today.toDateString() ? '' : year + month + '/' + day + ' ') + date.toTimeString().slice(0, 5);
  }
  const context = [network, localTime(data.last_checked_at)].filter(Boolean).join(' ');
  const hasResult = Boolean(total || data.last_error);
  const runError = state.last_error && state.last_error !== data.last_error && state.last_error_at > 0
    && !(Number(data.last_checked_at) > Number(state.last_error_at));
  let notice = state.notice === 'Wi-Fi 已跳过' ? state.notice : state.notice === '网络类型未知' ? '网络未知，已跳过' : '';
  const noticeTime = localTime(notice ? state.notice_at : runError ? state.last_error_at : 0);
  if (runError && !notice) notice = '本次检查失败';
  if (settings.officialAutoEnabled === false && !unconfigured) notice = [notice, '自动上报已停用'].filter(Boolean).join(' · ');
  const style = {
    good: ['checkmark.shield.fill', '#187548'], warn: ['exclamationmark.shield.fill', '#a25b13'],
    bad: ['xmark.shield.fill', '#aa3a38'], idle: ['shield', '#6b7280'],
  };
  let [icon, backgroundColor] = style[tone];
  if (notice) {
    icon = notice.startsWith('本次检查失败') ? style.bad[0] : notice.startsWith('自动') ? 'pause.circle.fill' : 'clock.fill';
    backgroundColor = notice.startsWith('本次检查失败') ? style.bad[1] : style.idle[1];
  }
  const detail = !notice && total && failed !== total && missing !== total ? issues[0] : '';
  const summary = notice ? hasResult ? '上次 ' + result : '尚无上次结果' : result;
  const breakdown = hits ? [tally, ...issues].join(' · ') : issues.join(' · ');
  return { accounts, headline, tone, breakdown, context, notice, noticeTime, hasResult,
    tile: { title: 'PO0 防火墙 · 本机', content: [notice, summary, detail, hasResult && context].filter(Boolean).join(' · '),
      icon, backgroundColor, url: 'http://po0-report.invalid/recent' } };
}

function localOverview(state) {
  const settings = readJSON(STORE_KEY + '.channel-settings', {});
  const view = panelOverview(state, settings);
  view.names = String(settings.officialNames || '').split(/[;；\n]/);
  return view;
}

function escapeHtml(value) {
  return String(value == null ? '' : value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}

function panelText(value) {
  return escapeHtml(redactDisplayText(String(value)));
}

function slotNumber(slot) {
  return Number.isInteger(slot) && slot >= 0 && slot < 10 ? slot + 1 : null;
}

function slotMeter(account, covered) {
  const { used, limit, whitelist } = account;
  if (!Number.isInteger(limit) || limit < 1 || limit > 10 || !Number.isInteger(used) || used < 0 || used > limit) return '';
  // Only put numbers on cells when the official response locates every occupied slot.
  const placed = Array.isArray(whitelist) && whitelist.length === used &&
    whitelist.every(row => row && slotNumber(row.slot) && row.slot < limit && validIPv4Cidr24(row.ip)) &&
    new Set(whitelist.map(row => row.slot)).size === used;
  const cells = [];
  for (let slot = 0; slot < limit; slot++) {
    const row = placed && whitelist.find(row => row.slot === slot);
    const hit = account.status === 'ok' && (placed ? row && covered && row.slot === covered.slot : used > 0 && slot === 0);
    const occupied = placed ? Boolean(row) : slot < used;
    const label = hit ? '本机命中' : occupied ? '已占用' : '空闲';
    cells.push('<span class="cell ' + (hit ? 'hit' : occupied ? 'used' : 'free') + '" title="' +
      (placed ? '#' + (slot + 1) + ' ' : '') + label + '">' + (placed ? slot + 1 : '') + '</span>');
  }
  return '<div class="capacity"><div class="quota"><span>槽位占用</span><b>' + used + '/' + limit + '</b></div>' +
    '<div class="meter' + (placed ? '' : ' unnumbered') + '" aria-label="占用 ' + used + '/' + limit + '">' + cells.join('') + '</div></div>';
}

function accountError(message) {
  const http = /\bHTTP (\d{3})\b/.exec(message);
  if (http) return '官方接口返回 HTTP ' + http[1];
  if (String(message).includes('指定槽位超出账号额度')) return '指定槽位超出账号额度';
  if (String(message).includes('未启用')) return '官方防火墙未启用';
  return '本次未能确认官方白名单';
}

function accountCard(account, index, names) {
  const name = typeof account.name === 'string' && account.name.trim() || names[index]?.trim() || '官方账号 ' + (index + 1);
  const ok = account.status === 'ok', error = account.status === 'error';
  const checked = ok || account.status === 'missing' || account.status === 'slot-mismatch';
  const labels = { __proto__: null, missing: '未放行', 'slot-mismatch': '槽位不匹配' };
  const status = ok ? account.added === true ? '新增放行' : '已放行' : error ? '检查失败' : labels[account.status] || '待确认';
  const tone = ok ? 'good' : error ? 'bad' : checked ? 'warn' : 'idle';
  const start = '<article class="account"><header><h3>' + panelText(name) + '</h3><span class="badge ' + tone + '">' + status + '</span></header>';
  if (!checked) return start + '<p class="reason">' + (error ? accountError(account.last_error) : '尚无可确认的检查结果') + '</p></article>';
  const exit = [account.current, account.current_ip, account.current_exit].find(value => typeof value === 'string' && validIPv4Cidr24(value));
  const fixed = slotNumber(account.fixed_slot);
  let covered;
  if (ok) {
    if (account.covered_slot === null || slotNumber(account.covered_slot)) covered = { slot: account.covered_slot };
    else if (exit && Array.isArray(account.whitelist)) {
      const whitelist = account.whitelist.filter(row => row && validIPv4Cidr24(row.ip) && (row.slot === null || slotNumber(row.slot)));
      covered = coveredRow({ currentIp: exit, whitelist }, { fixedSlot: fixed ? account.fixed_slot : null });
    }
  }
  let slot = fixed ? '指定 #' + fixed : '';
  if (covered) {
    const shared = fixed && account.fixed_slot !== covered.slot;
    slot = (shared ? '共用' : '命中') + (covered.slot === null ? '自动槽位' : ' #' + slotNumber(covered.slot)) +
      (shared ? '<small>指定 #' + fixed + '</small>' : '');
  }
  return start + (slot ? '<p class="slot">' + slot + '</p>' : '') + slotMeter(account, covered) +
    (exit ? '<p class="exit"><span>官方出口</span><code>' + escapeHtml(exit) + '</code></p>' : '') + '</article>';
}

function cachedPanelHtml(state, fresh) {
  const view = localOverview(state);
  const official = state.official || {};
  const notice = fresh ? '' : view.notice;
  const source = official.check_kind === 'query' ? '只读查询' : official.check_kind === 'report' ? '官方上报' : '';
  const caption = notice ? '上次检查' : '本次检查';
  const rows = view.accounts;
  const when = [view.context, source].filter(Boolean).join(' · ');
  const banner = notice ? '<aside class="notice"><strong>' + notice + '</strong><span>' + (view.noticeTime ? view.noticeTime + ' · ' : '') +
    (view.hasResult ? '下方保留上次检查结果' : '尚无上次检查结果') + '</span></aside>' : '';
  if (!view.hasResult && notice) return banner;
  const overview = '<section class="summary ' + view.tone + '"><div class="summary-meta"><span>' +
    (view.hasResult ? caption : '本机状态') + '</span><span>' + when + '</span></div><h2>' + view.headline + '</h2>' +
    (view.breakdown ? '<p>' + view.breakdown + '</p>' : '') + '</section>';
  if (!rows.length) return banner + overview;
  const cards = rows.map((a, i) => accountCard(a, i, view.names)).join('');
  const legend = cards.includes('class="meter') ? '<div class="legend"><span class="hit">本机命中</span>' +
    '<span class="used">其他占用</span><span class="free">空闲</span></div>' : '';
  return banner + overview + '<section class="accounts"><div class="section-head"><h2>账号详情</h2>' +
    legend + '</div>' + cards + '</section>';
}

function htmlResult(ok, message, state, mode, attempted) {
  const recent = mode === 'recent', settings = mode === 'settings';
  const heading = recent ? '本机上报结果' : settings ? '本机设置' : mode === 'status' ? '官方白名单查询' : ok ? '操作完成' : '操作未完成';
  const link = (path, label, danger) => '<a class="action' + (danger ? ' danger' : '') + '" href="http://po0-report.invalid/' + path + '"' +
    (danger ? ' onclick="return confirm(\'确认清除本机保存的官方配置？\')"' : '') + '>' + label + '</a>';
  const navigation = '<nav class="actions">' + (recent ? link('settings', '本机设置') : link('recent', '查看本机结果')) +
    link('status', '查询官方白名单') + '<a class="action" href="stash://">返回 Stash</a></nav>';
  const controls = '<section class="card"><h2>官方防火墙</h2><div class="actions">' + link('save-official','保存配置') +
    link('toggle-official-timer','启用 / 停用定期上报') + link('toggle-official','停用 / 恢复自动') + link('official-now','立即上报') +
    link('official-force','强制上报') + link('clear-official','清除本机配置',true) + '</div>' +
    '<p class="hint">在 /save-official 参数中填写账号、名称和间隔。SKIP_WIFI_SSIDS 可用英文分号分隔多个 Wi-Fi 名称。强制上报可绕过跳过名单。</p></section>';
  const response = !recent && !attempted ? '<section class="card"><h2>' + (settings ? '上报设置' : heading) +
    '</h2><div class="detail">' + panelText(message) + '</div></section>' : '';
  return '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<title>PO0 防火墙 · ' + heading + '</title><style>' + PANEL_CSS + '</style></head><body><main>' +
    '<header class="page-head"><p>Stash · 本机</p><h1>PO0 防火墙</h1></header>' +
    (recent || settings || attempted ? cachedPanelHtml(state, attempted) : '') + response + (recent ? '' : controls) +
    navigation + '</main></body></html>';
}

const PANEL_CSS = `
:root{color-scheme:light dark;--bg:#f3f5f5;--paper:#fff;--ink:#172a2e;--sub:#4d6369;--line:#d4dfe0;--hit:#176a5a;--used:#68828a;--free:#eef2f2;--link:#226473}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif}
main{max-width:580px;margin:auto;padding:20px 16px max(32px,env(safe-area-inset-bottom));overflow-wrap:anywhere}h1,h2,h3,p{margin:0}
.page-head{margin-bottom:15px}.page-head p,.summary-meta,.legend,.quota,.exit,.hint,.reason,.notice span{color:var(--sub);font-size:13px}
h1{font-size:27px;line-height:1.35;letter-spacing:-.03em}.page-head p{font-weight:600}
.good{--tone:#146854;--tint:#e8f4ef}.warn{--tone:#874b0d;--tint:#fbefdd}.bad{--tone:#a13436;--tint:#faebeb}.idle{--tone:var(--sub);--tint:var(--free)}
.summary,.notice,.account,.card{border:1px solid var(--line);border-radius:15px;background:var(--paper)}
.summary{border:0;border-left:4px solid var(--tone);background:var(--tint);padding:13px 15px 15px;margin-bottom:17px}
.summary-meta,.section-head,.account header,.quota,.exit,.notice{display:flex;align-items:baseline;justify-content:space-between;gap:4px 12px;flex-wrap:wrap}
.summary-meta{color:var(--tone);font-weight:600;font-variant-numeric:tabular-nums}.summary h2{font-size:26px;line-height:1.35;margin:4px 0;color:var(--tone)}
.summary p{font-size:14px}.notice{padding:10px 14px;margin-bottom:10px}.notice strong{font-size:15px}
.section-head{margin:0 2px 8px}.section-head h2,.card h2{font-size:17px}.legend{display:flex;flex-wrap:wrap;gap:8px;font-size:11px}
.legend span:before{content:"";display:inline-block;width:8px;height:8px;margin-right:3px;border-radius:2px}
.legend .hit:before,.cell.hit{background:var(--hit)}.legend .used:before,.cell.used{background:var(--used)}.legend .free:before,.cell.free{background:var(--free);border:1px solid var(--line)}
.account,.card{padding:13px 15px;margin-bottom:8px}.account header{align-items:flex-start;flex-wrap:nowrap}.account h3{min-width:0;font-size:16px}.badge{flex:none;color:var(--tone);background:var(--tint);font-size:12px;font-weight:650;border-radius:6px;padding:2px 7px}
.slot,.reason{margin-top:4px}.slot{font-size:13px;color:var(--ink)}.slot small{margin-left:8px;color:var(--sub);font-size:12px}
.capacity{margin-top:8px}.quota,.exit{gap:2px 8px}.quota b,.exit code{color:var(--ink);font-variant-numeric:tabular-nums}
.meter{display:flex;gap:3px;margin-top:3px}.cell{flex:1;text-align:center;border-radius:3px;font:600 11px/16px -apple-system,sans-serif;color:white}.cell.free{color:var(--sub);line-height:14px}
.unnumbered .cell{height:6px}.exit{margin-top:7px}.exit code{font:13px ui-monospace,Consolas,monospace}
.card h2{margin-bottom:8px}.detail{white-space:pre-wrap}.actions{display:flex;flex-wrap:wrap;gap:6px}nav{margin-top:16px}
.action{display:inline-block;border:1px solid var(--line);background:var(--paper);border-radius:8px;padding:9px 10px;color:var(--link);text-decoration:none;font-size:14px}.danger{color:#a13436}.hint{margin-top:10px}
@media(prefers-color-scheme:dark){:root{--bg:#11191c;--paper:#192427;--ink:#eef3f3;--sub:#b1c0c4;--line:#3a4a4e;--hit:#278673;--used:#526c75;--free:#263338;--link:#89d5df}
.good{--tone:#8cdbc0;--tint:#183b33}.warn{--tone:#f3c681;--tint:#382d1d}.bad{--tone:#ffb1ae;--tint:#422b2e}.danger{color:#ffb1ae}}
`;
function finish(mode, ok, message, state, meta) {
  const details = meta || {};
  if (['auto', 'report', 'force', 'status'].includes(mode)) {
    const settings = readJSON(STORE_KEY + '.channel-settings', {});
    const updated = Number(details.added || 0) > 0;
    if ((!ok && settings.NOTIFY_FAILURE !== false) || (ok && (updated || (details.attempted && mode !== 'auto' && settings.NOTIFY_SUCCESS)))) {
      $notification.post('PO0 防火墙', ok ? (updated ? '新增官方白名单' : '检查完成') : '检查失败', message);
    }
  }
  if (mode === "status" && $script.type !== "request") return localOverview(state).tile;
  if ($script.type === "request" || mode === "force") {
    return { response: { status: ok ? 200 : 502, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" }, body: htmlResult(ok, message, state, mode, details.attempted) } };
  }
}

async function runUnlocked() {
  const args = parseArgument();
  const mode = $script.type === "tile" ? "status" : String(args.mode || "auto").toLowerCase();
  if (retiredMode(args, mode)) { return finish('settings', true, '自建防火墙功能已退役；旧版可从归档恢复', {}, {}); }
  if (mode === 'recent' || mode === 'settings') {
    return finish(mode, true, mode === 'settings' ? localSettingsSummary(args) : '', readJSON(STORE_KEY, {}));
  }
  migrateRetiredState();
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

  if (args.channel && args.channel !== 'official') return finish(mode, false, '未知的上报目标', state, {});
  if (!parseFirewallTokens(firewallRawValue(args)).length) return finish(mode, true, '尚未配置官方上报目标', state, {});
  const split = officialNetworkEnabled(args);
  const scheduled = mode === 'auto' && !isNetworkTrigger(args);
  if (scheduled && !timerEnabled('official', args)) return finish(mode, true, '定期检查已停用', state, {});
  // Only legacy clients need external 204 probes. Keep idle legacy ticks offline.
  if (scheduled && typeof $httpAPI !== 'function' && !officialDue(mode, state.official, nowSeconds, args)) {
    return finish(mode, true, '尚未到定期检查时间', state, {});
  }
  const skip = channelSettings().officialSkipSsids || [];
  const checkSsid = skip.length > 0 && (mode === 'auto' || mode === 'report');
  const network = await reportNetwork(args, split);
  if (checkSsid && network.ssid && skip.includes(network.ssid)) {
    state.notice = 'Wi-Fi 已跳过';
    state.notice_at = nowSeconds;
    writeJSON(STORE_KEY, state);
    console.log('[PO0 防火墙] Wi-Fi 已跳过');
    return finish(mode, true, 'Wi-Fi 已跳过，保留上次结果', state, {});
  }
  if (split && network.kind === 'unknown') {
    state.notice = '网络类型未知';
    state.notice_at = nowSeconds;
    writeJSON(STORE_KEY, state);
    return finish(mode, false, '无法识别当前网络，已跳过官方请求', state, {});
  }
  const previous = split && state.official?.network !== network.kind ? {} : state.official || {};
  // An idle timer tick has no new evidence about the last checked network.
  if (scheduled && !officialDue(mode, previous, nowSeconds, args)) return finish(mode, true, '尚未到定期检查时间', state, {});
  const tokens = selectedFirewallTokens(args, network.kind);
  const officialResult = await runOfficial(tokens, mode, previous, nowSeconds);
  state.official = officialResult.official;
  state.official.check_kind = mode === 'status' ? 'query' : 'report';
  state.official.network = network.kind === 'unknown' ? 'default' : network.kind;
  delete state.notice;
  delete state.notice_at;
  delete state.last_error_at;
  const ok = officialResult.ok;
  const message = officialSummary(state.official);
  state.last_error = ok ? '' : state.official.last_error;
  writeJSON(STORE_KEY, state);
  return finish(mode, ok, message, state, officialResult);
}

async function run() {
  const args = parseArgument();
  const mode = String(args.mode || 'auto').toLowerCase();
  if (mode === 'recent' || mode === 'settings' || retiredMode(args, mode)) return runUnlocked();
  const lock = acquireRunLock(mode, 'official', Date.now());
  if (!lock) return finish(mode, true, '已有上报任务运行，已跳过重复触发', readJSON(STORE_KEY, {}), {});
  try { return await runUnlocked(); } finally { releaseRunLock(lock); }
}

function handleError(error) {
  const args = parseArgument();
  const mode = $script.type === "tile" ? "status" : String(args.mode || "auto").toLowerCase();
  const state = readJSON(STORE_KEY, {});
  const message = redactedError(error, args, null);
  if (['auto', 'report', 'force', 'status'].includes(mode)) {
    delete state.notice;
    delete state.notice_at;
    state.last_error = message;
    state.last_error_at = Math.floor(Date.now() / 1000);
    writeJSON(STORE_KEY, state);
  }
  console.log("[PO0 防火墙] " + message);
  return finish(mode, false, message, state);
}

if ($script.type === "tile") {
  $done(localOverview(readJSON(STORE_KEY, {})).tile);
} else {
  // Release the shared event/cron lock before Stash ends this script.
  run().catch(handleError).then(result => result === undefined ? $done() : $done(result));
}
