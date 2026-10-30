// PO0 防火墙上报 · 20261030-widget-redesign-v2
function retiredAction(ctx) {
  return /自建|ssh-report|设备 ID|本机设备|Device ID|设备标识/i.test(scriptLabel(ctx)) || Boolean(ctx?.request);
}

async function migrateRetiredState(ctx) {
  const marker = CONFIG_STORAGE_KEY + ':official-only-v1';
  if (await storageGet(ctx, marker)) return;
  const key = CONFIG_STORAGE_KEY + ':pre-retirement-v1';
  if (!await storageGet(ctx, key)) {
    const backup = { config: await storageGet(ctx, CONFIG_STORAGE_KEY), state: await storageGet(ctx, STORAGE_KEY), official: await storageGet(ctx, OFFICIAL_STORAGE_KEY), error: await storageGet(ctx, ERROR_STORAGE_KEY) };
    if (!await storageSet(ctx, key, JSON.stringify(backup))) throw new Error('无法备份旧本机配置');
  }
  const saved = await storedReportConfig(ctx);
  if (saved.exists) await saveReportConfig(ctx, saved.values);
  if (!await storageSet(ctx, STORAGE_KEY, JSON.stringify(sanitizedStoredState(await storageGet(ctx, STORAGE_KEY)) || {}))) throw new Error('无法迁移本机状态');
  await storageDelete(ctx, ERROR_STORAGE_KEY);
  if (!await storageSet(ctx, marker, '1')) throw new Error('无法完成本机配置迁移');
}

// Keep device settings and locks compatible with the old script URLs.
const STORAGE_KEY = 'po0-ssh-ip-report:last';
const ERROR_STORAGE_KEY = 'po0-ssh-ip-report:last-error';
const OFFICIAL_STORAGE_KEY = 'po0-ssh-ip-report:official:v1';
const CONFIG_STORAGE_KEY = 'po0-ssh-ip-report:config:v1';
const CONFIG_STORAGE_VERSION = 1;
const OFFICIAL_FIREWALL_API_BASE = 'https://124.221.69.228/api/firewall';
const DEFAULT_OFFICIAL_INTERVAL_SECONDS = 600;
const OFFICIAL_FIREWALL_MAX_TOKENS = 16;
const REPORT_LOCK_KEY = 'po0-ssh-ip-report:run-lock:v1';
const REPORT_LOCK_TTL_MS = 120000;
const REPORT_TITLE = 'PO0 防火墙';
const REPORT_FAILED_TITLE = 'PO0 防火墙 · 检查失败';
// Official targets and the automatic switch stay on this device.
const OFFICIAL_CONFIG_KEYS = ['PO0_FIREWALL_TOKENS', 'PO0_FIREWALL_NAMES', 'PO0_FIREWALL_WIFI_TOKENS', 'PO0_FIREWALL_WIFI_NAMES', 'OFFICIAL_AUTO_ENABLED'];
const PERSISTED_ENV_KEYS = [...OFFICIAL_CONFIG_KEYS];
const LIVE_ENV_KEYS = ['OFFICIAL_INTERVAL_SECONDS', 'OFFICIAL_TIMER_ENABLED', 'OFFICIAL_NETWORK_TARGETS_ENABLED', 'SKIP_WIFI_SSIDS', 'IP_CHECK_URL', 'IP_CHECK_URLS', 'POLICY', 'NOTIFY_SUCCESS', 'NOTIFY_FAILURE'];

function redactSensitiveText(value, secrets = []) {
  let text = String(value ?? '');
  const candidates = Array.from(new Set(
    (Array.isArray(secrets) ? secrets : [secrets])
      .map((secret) => String(secret ?? '').trim())
      .filter(Boolean),
  )).sort((left, right) => right.length - left.length);

  for (const secret of candidates) {
    text = text.split(secret).join('[REDACTED]');
    let encoded = '';
    try { encoded = encodeURIComponent(secret); } catch (_) {}
    if (encoded && encoded !== secret) text = text.split(encoded).join('[REDACTED]');
  }

  text = text.replace(/\bBearer\s+[^\s,;)}\]>"']+/gi, 'Bearer [REDACTED]');
  text = text.replace(/\bpgnfw_[A-Za-z0-9._~@+-]{1,240}/g, '[REDACTED]');
  return text;
}

function redactError(error, env = {}) {
  const values = Object.values(env).filter(value => typeof value === 'string' && value.length > 3);
  return redactSensitiveText(String(error && error.message || error || ''), values);
}

async function responseText(resp) {
  if (typeof resp.text === 'function') return await resp.text();
  if (typeof resp.body === 'string') return resp.body;
  if (typeof resp.data === 'string') return resp.data;
  return JSON.stringify(resp.body || resp.data || '');
}

function normalizeIpProfile(value) {
  if (!value || typeof value !== 'object') return { location: '', isp: '' };
  return {
    location: String(value.location || '').trim(),
    isp: String(value.isp || value.org || '').trim(),
  };
}

function boolEnv(value, fallback) {
  const raw = String(value || '').trim().toLowerCase();
  if (!raw) return fallback;
  return ['1', 'true', 'yes', 'on'].includes(raw);
}

function officialNowMs() {
  try {
    const testValue = Number(globalThis.__PO0_EGERN_TEST_NOW);
    if (Number.isFinite(testValue)) return testValue;
  } catch (_) {}
  return Date.now();
}

function officialNowIso() {
  return new Date(officialNowMs()).toISOString();
}

function parseOfficialTokenItem(value) {
  const row = String(value ?? '').trim();
  if (!row || /[\r\n]/.test(row)) {
    throw new Error('Token 配置包含空项或换行。');
  }

  const [item, name, ...options] = row.split('|').map(part => part.trim());
  const settings = {};
  // The third column is a client reporting interval. Legacy ttl= aliases remain readable.
  // Old interval/timer rows remain readable for saved local configuration.
  if (options.length === 1 && /^(?:ttl=)?\d+$/i.test(options[0])) {
    const seconds = Number(options[0].replace(/^ttl=/i, ''));
    if (!Number.isInteger(seconds) || (seconds !== 0 && (seconds < 60 || seconds > 86400))) {
      throw new Error('旧版间隔参数无效，请删除账号中的间隔参数，改用“上报间隔”设置。');
    }
    if (seconds === 0) settings.timer = false;
    else settings.interval = seconds;
    options.length = 0;
  }
  for (const option of options) {
    if (!option) continue;
    if (/^ttl\s*=/i.test(option) || /^\d+$/.test(option)) {
      throw new Error('账号格式：Token@槽位|名称；间隔请在“上报间隔”中设置。');
    }
    const match = /^(interval|timer)=(.+)$/.exec(option);
    if (!match) throw new Error('账号格式：Token@槽位|名称；间隔请在“上报间隔”中设置。');
    const [, key, raw] = match;
    if (Object.prototype.hasOwnProperty.call(settings, key)) throw new Error('账号可选参数不能重复。');
    if (key === 'interval') {
      if (!/^\d+$/.test(raw) || Number(raw) < 60 || Number(raw) > 86400) throw new Error('旧版间隔参数无效，请删除账号中的间隔参数，改用“上报间隔”设置。');
      settings.interval = Number(raw);
    } else {
      if (!/^(true|false)$/.test(raw)) throw new Error('旧版定时参数无效，请删除账号中的定时参数，改用“启用定期上报”设置。');
      settings.timer = raw === 'true';
    }
  }
  let token = item;
  let slot = null;
  const at = item.indexOf('@');
  if (at >= 0) {
    if (at !== item.lastIndexOf('@')) {
      throw new Error('Token 配置无效：槽位只能写 @0～@9。');
    }
    token = item.slice(0, at);
    const slotText = item.slice(at + 1);
    if (!/^[0-9]$/.test(slotText)) {
      throw new Error('Token 配置无效：槽位只能写 @0～@9。');
    }
    slot = Number(slotText);
  }

  if (!/^pgnfw_[A-Za-z0-9._~-]{1,240}$/.test(token)) {
    throw new Error('Token 配置无效：请使用 pgnfw_...。');
  }
  return { token, slot, name, ...settings };
}

function officialTokenWithoutName(item) {
  const interval = item.timer === false ? 0 : item.interval;
  return item.token + (item.slot === null ? '' : '@' + item.slot) + (interval === undefined ? '' : '||' + interval);
}

function parseOfficialTokens(raw) {
  const value = String(raw ?? '').trim();
  if (!value) return [];

  const seen = new Set();
  // Extended rows preserve spaces in names; bare legacy lists still accept whitespace.
  const tokens = value.split(/[,;，；\r\n]+/).flatMap(row => row.includes('|') ? [row.trim()] : row.split(/\s+/))
    .filter(Boolean).map((item) => parseOfficialTokenItem(item));
  for (const item of tokens) {
    // A token identifies one official account; slot hints are not separate accounts.
    const key = item.token;
    if (seen.has(key)) {
      throw new Error('Token 列表包含重复项。');
    }
    seen.add(key);
  }
  if (tokens.length > OFFICIAL_FIREWALL_MAX_TOKENS) {
    throw new Error(`Token 数量超过上限（最多 ${OFFICIAL_FIREWALL_MAX_TOKENS} 个）。`);
  }
  return tokens;
}

// Select an entire user-supplied target list. Never assign or remove slots.
function officialNetworkEnv(env, network) {
  if (!boolEnv(env.OFFICIAL_NETWORK_TARGETS_ENABLED, false)) return env;
  const kind = network?.kind || 'unknown';
  return { ...env, _officialNetwork: kind,
    ...(kind === 'wifi' ? {
      PO0_FIREWALL_TOKENS: env.PO0_FIREWALL_WIFI_TOKENS || '',
      PO0_FIREWALL_NAMES: env.PO0_FIREWALL_WIFI_NAMES || '',
    } : {}),
  };
}

function officialNetworkSettingsRows(env) {
  const enabled = boolEnv(env.OFFICIAL_NETWORK_TARGETS_ENABLED, false);
  return ['按网络选择账号：' + (enabled ? '已启用；上报账号用于蜂窝' : '已停用；所有网络使用上报账号'),
    ...(enabled ? officialSavedNameRows(officialNetworkEnv(env, { kind: 'wifi' })).map(row => 'Wi-Fi · ' + row) : []),
  ];
}

function officialTokensConfigured(env) {
  return String(env?.PO0_FIREWALL_TOKENS ?? '').trim() !== '';
}

function officialCidr24(value) {
  const match = String(value ?? '').trim().match(/^(\d{1,3})(?:\.(\d{1,3})){3}\/24$/);
  if (!match) return '';
  const address = String(value).trim().slice(0, -3);
  const parts = address.split('.').map((part) => Number(part));
  if (parts.length !== 4 || parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) return '';
  return `${parts.join('.')}/24`;
}

function officialNormalizePayload(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new Error('防火墙返回数据无效。');
  }
  if (data.enabled !== true) {
    throw new Error('防火墙当前未启用。');
  }
  const currentIp = officialCidr24(data.currentIp);
  if (!currentIp) {
    throw new Error('防火墙未返回有效的出口 IPv4。');
  }
  const limit = data.limit;
  if (!Number.isInteger(limit) || limit < 1 || limit > 10) {
    throw new Error('防火墙返回的槽位数量无效。');
  }
  if (!Array.isArray(data.whitelist) || data.whitelist.length > limit || data.whitelist.length > 10) {
    throw new Error('防火墙返回的白名单无效。');
  }

  const seenSlots = new Set();
  const whitelist = data.whitelist.map((entry) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      throw new Error('防火墙返回的白名单无效。');
    }
    const ip = officialCidr24(entry.ip);
    if (!ip) throw new Error('防火墙返回的白名单 IP 无效。');

    let slot = null;
    if (entry.slot !== undefined && entry.slot !== null && entry.slot !== '') {
      if (!Number.isInteger(entry.slot) || entry.slot < 0 || entry.slot >= limit) {
        throw new Error('防火墙返回的槽位无效。');
      }
      if (seenSlots.has(entry.slot)) {
        throw new Error('防火墙返回了重复槽位。');
      }
      seenSlots.add(entry.slot);
      slot = entry.slot;
    }
    return { ip, slot };
  });

  return {
    enabled: true,
    currentIp,
    limit,
    used: whitelist.length,
    whitelist,
  };
}

function officialHttpError(status, operation) {
  const phase = operation === 'post' ? '更新' : '查询';
  const suffix = Number.isInteger(status) ? '（HTTP ' + status + '）' : '';
  const hint = status === 403
    ? operation === 'post'
      ? '：服务端拒绝写入，请核对白名单槽位。'
      : '：服务端拒绝查询，请核对 Token 与防火墙开关。'
    : '。';
  const error = new Error('防火墙' + phase + '失败' + suffix + hint);
  error.httpStatus = status;
  return error;
}

async function officialPayloadFromResponse(response, operation) {
  const status = Number(response?.status);
  if (!Number.isInteger(status) || status < 200 || status >= 300) {
    throw officialHttpError(status, operation);
  }

  let data;
  try {
    if (typeof response?.json === 'function') {
      data = await response.json();
    } else {
      const text = await responseText(response);
      data = JSON.parse(text);
    }
    if (typeof data === 'string') data = JSON.parse(data);
  } catch (_) {
    throw new Error('防火墙返回数据无效。');
  }
  return officialNormalizePayload(data);
}

async function officialDirectRequest(ctx, item, operation) {
  const method = operation === 'post' ? 'post' : 'get';
  const encodedToken = encodeURIComponent(item.token);
  let url = `${OFFICIAL_FIREWALL_API_BASE}/${encodedToken}`;
  if (method === 'post') {
    url += '/add';
    if (item.slot !== null && item.slot !== undefined) url += `?slot=${item.slot}`;
  }

  const request = ctx?.http?.[method];
  if (typeof request !== 'function') {
    throw new Error('Egern 无法发送网络请求。');
  }

  let response;
  try {
    response = await request.call(ctx.http, url, {
      policy: 'DIRECT',
      timeout: 10000,
      redirect: 'error',
      credentials: 'omit',
      insecureTls: false,
      headers: { Accept: 'application/json' },
    });
  } catch (error) {
    // Some Egern versions throw HTTP failures instead of returning a Response.
    // Extract only the status; never retain the URL or raw response body.
    const status = String(error?.message || '').match(/\bstatus:\s*([1-5]\d{2})\b/i);
    if (status) throw officialHttpError(Number(status[1]), method);
    throw new Error('防火墙网络请求失败。');
  }
  return await officialPayloadFromResponse(response, method);
}

function officialSafeError(error) {
  if (error?.message === '无法识别当前网络，已跳过上报。') return error.message;
  const text = String(error?.message || '').replace(/^官方防火墙/, '防火墙').replace(/^PO0 官方防火墙 token /, 'Token ').replace(/^防火墙加白/, '防火墙更新');
  if ([
    '账号格式：Token@槽位|名称；间隔请在“上报间隔”中设置。',
    '旧版间隔参数无效，请删除账号中的间隔参数，改用“上报间隔”设置。',
    '账号可选参数不能重复。',
    '上报间隔必须为 60～86400 秒',
    '旧版定时参数无效，请删除账号中的定时参数，改用“启用定期上报”设置。',
  ].includes(text)) return text;
  if (text === '指定槽位超出账号额度，请调整固定槽位。') return text;
  if (text === '防火墙网络请求失败。' || text === 'Egern 无法发送网络请求。') return text;
  const http = text.match(/^防火墙请求失败（HTTP (\d{3})）。$/);
  if (http) return `防火墙请求失败（HTTP ${http[1]}）。`;
  const phasedHttp = text.match(/^防火墙(查询|更新)失败（HTTP (\d{3})）/);
  if (phasedHttp) {
    const safe = officialHttpError(Number(phasedHttp[2]), phasedHttp[1] === '更新' ? 'post' : 'get').message;
    if (text === safe) return safe;
  }
  if (/^防火墙(?:当前未启用|未返回有效的出口 IPv4|返回数据无效|返回的槽位数量无效|返回的白名单无效|返回的白名单 IP 无效|返回的槽位无效|返回了重复槽位|更新后未确认当前出口)。$/.test(text)) return text;
  if (/^Token (?:配置包含空项或换行|配置无效：槽位只能写 @0～@9|配置无效：请使用 pgnfw_\.\.\.|列表包含重复项|数量超过上限（最多 16 个）)。$/.test(text)) return text;
  return '防火墙请求失败。';
}

function scriptLabel(ctx) {
  const aliases = {
    'PO0 防火墙 · 查看配置': '查看本机上报设置',
    'PO0 防火墙状态': 'PO0 防火墙上报状态',
    'PO0 防火墙 · 保存配置': '保存本机 PO0 官方防火墙配置',
    'PO0 防火墙 · 启用自动上报': '启用官方防火墙自动上报',
    'PO0 防火墙 · 停用自动上报': '停用官方防火墙自动上报',
    'PO0 防火墙 · 查询白名单': 'PO0 官方防火墙状态（只读）',
    'PO0 防火墙 · 清除配置': '清除本机 PO0 官方防火墙 Token',
    'PO0 防火墙 · 最近结果': '查看最近结果',
    '查看本机配置': '查看本机上报设置',
    '查看本机官方防火墙配置': '查看本机上报设置',
    '查看官方防火墙最近结果': '查看最近结果',
    '自建防火墙 · 保存配置': '保存本机 PO0 自建防火墙配置',
    '官方防火墙 · 保存配置': '保存本机 PO0 官方防火墙配置',
    '查询官方白名单': 'PO0 官方防火墙状态（只读）',
  };
  return [
    ctx?.name,
    ctx?.script?.name,
    ctx?.script?.type,
    ctx?.trigger,
    ctx?.type,
    ctx?.executionType,
  ].filter(Boolean).map(value => aliases[value] || value).join(' ');
}

function isManualRun(ctx) {
  return /generic|manual|now|force|立即|手动|强制/i.test(scriptLabel(ctx));
}

function isAutomaticReportRun(ctx) {
  if (
    isManualRun(ctx)
    || isWidgetRun(ctx)
    || isStatusRun(ctx)
    || isDeviceSetupRun(ctx)
    || isDeviceClearRun(ctx)
    || isWorkerConfigSaveRun(ctx)
    || isOfficialConfigSaveRun(ctx)
    || isReportConfigSaveRun(ctx)
    || isReportConfigClearRun(ctx)
  ) return false;
  const exactTriggers = [
    ctx?.trigger,
    ctx?.type,
    ctx?.executionType,
    ctx?.script?.type,
  ].map((value) => String(value || '').trim().toLowerCase());
  if (exactTriggers.some((value) => value === 'schedule' || value === 'network')) return true;
  return /(^|\s)(schedule|network)(\s|$)|定时|网络/i.test(scriptLabel(ctx));
}

function isWidgetRun(ctx) {
  return Boolean(ctx?.widgetFamily);
}

function isStatusRun(ctx) {
  return /状态|status/i.test(scriptLabel(ctx));
}

function isOfficialStatusRun(ctx) {
  const label = scriptLabel(ctx);
  return !/上报状态/.test(label) && /官方防火墙.*状态|official firewall status/i.test(label);
}

function shouldReturnWidget(ctx) {
  // Egern documents ctx.script.name; generic actions need renderable results too.
  return isWidgetRun(ctx) || isStatusRun(ctx)
    || (Boolean(ctx?.script?.name) && !ctx?.request && !isAutomaticReportRun(ctx));
}

function isDeviceSetupRun(ctx) {
  return /保存本机设备|设置本机设备|save device|set device/i.test(scriptLabel(ctx));
}

function isDeviceClearRun(ctx) {
  return /清除本机设备|clear device/i.test(scriptLabel(ctx));
}

function isWorkerConfigSaveRun(ctx) {
  return /保存本机(?: PO0 自建防火墙配置|自建 PO0 \/ 通用设置)/.test(scriptLabel(ctx));
}

function isOfficialConfigSaveRun(ctx) {
  return /保存本机\s*PO0\s*官方防火墙配置/.test(scriptLabel(ctx));
}

function isReportConfigSaveRun(ctx) {
  return /保存本机\s*(?:PO0\s*)?上报配置|save (?:local )?(?:po0 )?report config/i.test(scriptLabel(ctx));
}

function isReportConfigClearRun(ctx) {
  return /清除本机\s*(?:全部\s*)?(?:PO0\s*)?上报配置|clear (?:local )?(?:po0 )?report config/i.test(scriptLabel(ctx));
}

function isOfficialConfigClearRun(ctx) {
  return /清除本机\s*PO0\s*官方防火墙(?:\s*token)?|clear (?:local )?po0 official firewall(?: tokens?)?/i.test(scriptLabel(ctx));
}

function formatTime(value) {
  if (!value) return '未检查';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '时间未知';
  const time = date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit', hour12: false });
  const now = new Date(officialNowMs());
  if (date.toDateString() === now.toDateString()) return time;
  const day = [String(date.getMonth() + 1).padStart(2, '0'), String(date.getDate()).padStart(2, '0')].join('/');
  return (date.getFullYear() === now.getFullYear() ? day : date.getFullYear() + '/' + day) + ' ' + time;
}

function formatDurationSeconds(seconds) {
  const value = Number(seconds);
  if (!Number.isFinite(value) || value <= 0) return '未知';
  let remaining = Math.floor(value);
  const parts = [];
  for (const [unit, length] of [['天', 86400], ['小时', 3600], ['分钟', 60], ['秒', 1]]) {
    const count = Math.floor(remaining / length);
    if (count) parts.push(count + ' ' + unit);
    remaining %= length;
  }
  return parts.join(' ') || '0 秒';
}

// Egern resolves {light, dark} colors with the system appearance. Green is reserved for
// the current /24 network; other states stay neutral so the covered slot stands out.
const WIDGET_COLORS = {
  background: { light: '#FFFFFF', dark: '#1C1C1E' },
  card: { light: '#F2F2F7', dark: '#2C2C2E' },
  text: { light: '#1C1C1E', dark: '#F5F5F7' },
  secondary: { light: '#6E6E73', dark: '#98989F' },
  tertiary: { light: '#AEAEB2', dark: '#636366' },
  slot: { light: '#E5E5EA', dark: '#3A3A3C' },
  slotOnCard: { light: '#DCDCE1', dark: '#48484A' },
  slotLine: { light: '#C7C7CC', dark: '#48484A' },
  green: { light: '#248A3D', dark: '#30D158' },
  greenFill: { light: '#34C759', dark: '#30D158' },
  onGreen: { light: '#FFFFFF', dark: '#062B12' },
  orange: { light: '#C93400', dark: '#FF9F0A' },
  red: { light: '#D70015', dark: '#FF453A' },
};

const WIDGET_TONES = {
  ok: { color: WIDGET_COLORS.green, tint: { light: 'rgba(52, 199, 89, 0.16)', dark: 'rgba(48, 209, 88, 0.2)' }, icon: 'checkmark.circle.fill', shield: 'checkmark.shield.fill' },
  warn: { color: WIDGET_COLORS.orange, tint: { light: 'rgba(255, 149, 0, 0.16)', dark: 'rgba(255, 159, 10, 0.2)' }, icon: 'exclamationmark.circle.fill', shield: 'exclamationmark.shield.fill' },
  error: { color: WIDGET_COLORS.red, tint: { light: 'rgba(255, 59, 48, 0.1)', dark: 'rgba(255, 69, 58, 0.14)' }, icon: 'xmark.circle.fill', shield: 'xmark.shield.fill' },
  idle: { color: WIDGET_COLORS.secondary, tint: { light: 'rgba(120, 120, 128, 0.12)', dark: 'rgba(120, 120, 128, 0.24)' }, icon: 'circle.dashed', shield: 'shield' },
};

function textNode(text, size = 'caption1', weight = 'regular', color = WIDGET_COLORS.text) {
  return {
    type: 'text',
    text: String(text),
    font: { size, weight },
    textColor: color,
    maxLines: 1,
    minScale: 0.55,
  };
}

function iconNode(symbol, color, size = 12) {
  return {
    type: 'image',
    src: `sf-symbol:${symbol}`,
    width: size,
    height: size,
    color,
  };
}

function spacerNode(length) {
  return Number.isFinite(length) ? { type: 'spacer', length } : { type: 'spacer' };
}

function widgetFamily(ctx) {
  const family = String(ctx?.widgetFamily || '').toLowerCase();
  if (family.includes('small') || family.includes('accessory')) return 'small';
  if (family.includes('large')) return 'large';
  return 'medium';
}

function widgetMetrics(ctx) {
  const family = widgetFamily(ctx);
  return {
    padding: family === 'large' ? 16 : family === 'medium' ? 14 : 13,
    widgetGap: family === 'large' ? 8 : 6,
    titleSize: family === 'small' ? 14 : 15,
    bodySize: family === 'small' ? 12 : 13,
  };
}

function widgetText(text, size = 12, color = WIDGET_COLORS.text, weight = 'regular') {
  return { ...textNode(redactSensitiveText(String(text)), size, weight, color), minScale: 0.9 };
}

function widgetRow(children, gap = 5) {
  return { type: 'stack', direction: 'row', alignItems: 'center', gap, children };
}

function widgetLine(children, gap = 5) {
  // Trailing elastic space keeps a line full-width and leading-aligned in any parent.
  return widgetRow([...children, spacerNode()], gap);
}

function widgetPanel(title, content, ok, ctx) {
  const lines = (Array.isArray(content) ? content : String(content || '').split('\n'))
    .map(line => String(line || '').trim()).filter(Boolean);
  const metrics = widgetMetrics(ctx);
  const maxLines = !ctx?.widgetFamily ? lines.length : widgetFamily(ctx) === 'small' ? 4 : widgetFamily(ctx) === 'large' ? 12 : 7;
  const tone = WIDGET_TONES[ok ? 'ok' : 'error'];
  return {
    type: 'widget', padding: metrics.padding, gap: metrics.widgetGap,
    backgroundColor: WIDGET_COLORS.background,
    children: [
      widgetLine([iconNode(ok ? 'checkmark.shield.fill' : 'exclamationmark.triangle.fill', tone.color, 15), widgetText(title, metrics.titleSize, WIDGET_COLORS.text, 'semibold')], 6),
      ...lines.slice(0, maxLines).map(line => widgetLine([{ ...widgetText(line, metrics.bodySize, WIDGET_COLORS.secondary), maxLines: 2 }])),
    ],
  };
}

function officialStatusText(entry) {
  if (entry?.status === 'shared') return '当前网段已放行 · 共用' + officialCoveredSlotText(entry);
  if (entry?.status === 'hit') return '当前网段已放行';
  if (entry?.status === 'updated') return '当前网段已放行';
  if (entry?.status === 'missing') return '当前网段未放行（只读）';
  if (entry?.status === 'error') return entry.error || '检查失败';
  return '未检查';
}

function officialDisplaySlot(slot) {
  return Number.isInteger(slot) && slot >= 0 && slot <= 9 ? slot + 1 : null;
}

function officialCoveredSlotText(entry) {
  const slot = officialDisplaySlot(entry?.coveredSlot);
  return slot ? '槽位 #' + slot : '自动槽位';
}

function officialSameNetwork(left, right) {
  const leftIp = officialCidr24(left);
  const rightIp = officialCidr24(right);
  return Boolean(leftIp && rightIp && leftIp.split('.').slice(0, 3).join('.') === rightIp.split('.').slice(0, 3).join('.'));
}

function officialMatchingRow(payload, item) {
  // The API authorizes /24 networks, not devices or individual host addresses.
  const matches = payload.whitelist.filter(row => officialSameNetwork(row.ip, payload.currentIp));
  return matches.find(row => item.slot === null || row.slot === item.slot) || matches[0];
}

function applyOfficialPayload(entry, payload, item, successStatus) {
  if (item.slot !== null && item.slot >= payload.limit) throw new Error('指定槽位超出账号额度，请调整固定槽位。');
  entry.currentIp = payload.currentIp;
  entry.whitelist = payload.whitelist;
  entry.used = payload.used;
  entry.limit = payload.limit;
  const covered = officialMatchingRow(payload, item);
  entry.currentInWhitelist = Boolean(covered);
  entry.coveredSlot = covered?.slot ?? null;
  if (covered) entry.status = item.slot !== null && covered.slot !== item.slot ? 'shared' : successStatus;
  return Boolean(covered);
}

function widgetOfficialEntries(state, env, runtimeEnv = {}) {
  const displayEnv = officialDisplayEnv(env, runtimeEnv);
  if (!officialTokensConfigured(env)) return [];
  const previous = Array.isArray(state?.official?.entries) ? state.official.entries : [];
  try {
    return parseOfficialTokens(env.PO0_FIREWALL_TOKENS).map((item, index) => ({
      ...(previous.find(entry => entry.accountKey === shortHash(item.token) && entry.fixedSlot === item.slot) || (state?.official?.status === 'config-error' ? previous[0] : {}) || {}),
      ordinal: index + 1,
      name: officialAccountName(displayEnv, index),
      fixedSlot: item.slot,
      intervalSeconds: officialIntervalSeconds(env, item),
      timerEnabled: officialTimerEnabled(env, item),
    }));
  } catch (_) { return previous.map((entry, index) => ({ ...entry, name: officialAccountName(displayEnv, index) })); }
}

function widgetAutoState(configured, enabled, ssidMatched) {
  if (!configured) return { text: '未配置', icon: 'circle.dashed', tone: 'idle', color: WIDGET_COLORS.secondary };
  if (!enabled) return { text: '自动上报已停用', icon: 'pause.circle.fill', tone: 'warn', color: WIDGET_COLORS.orange };
  if (ssidMatched) return { text: 'Wi-Fi 已跳过', icon: 'wifi.slash', tone: 'idle', color: WIDGET_COLORS.secondary };
  return { text: '自动上报已启用', icon: 'clock.arrow.circlepath', tone: 'idle', color: WIDGET_COLORS.secondary };
}

function widgetRefreshSchedule(env, officialAuto, entries) {
  const intervals = officialAuto.text === '自动上报已启用' ? entries.filter(entry => entry.timerEnabled && entry.intervalSeconds).map(entry => entry.intervalSeconds) : [];
  return intervals.length ? { refreshAfter: new Date(Date.now() + Math.min(...intervals) * 1000).toISOString() } : {};
}

function widgetColumn(children, gap = 3, extra = {}) {
  return { type: 'stack', direction: 'column', alignItems: 'start', gap, ...extra, children };
}

function widgetEntryResult(entry) {
  const tone = entry.status === 'shared' || entry.status === 'updated' || entry.status === 'hit' ? 'ok'
    : entry.status === 'missing' ? 'warn' : entry.status === 'error' ? 'error' : 'idle';
  const text = entry.status === 'shared' ? '已放行 · 共用' : tone === 'ok' ? '已放行'
    : tone === 'warn' ? '未放行' : tone === 'error' ? '检查失败' : '待检查';
  return { text, tone, color: WIDGET_TONES[tone].color };
}

function widgetSlotLabel(entry) {
  const fixed = officialDisplaySlot(entry.fixedSlot);
  const covered = officialDisplaySlot(entry.coveredSlot);
  if (covered) return (entry.status === 'shared' ? '共用 #' : '槽位 #') + covered;
  // Automatically assigned records have no number; the record list labels them 自动.
  if (entry.currentInWhitelist) return '';
  return fixed ? '指定槽位 #' + fixed : '';
}

function widgetSlotMeta(entry) {
  return [widgetSlotLabel(entry), widgetQuotaText(entry)].filter(Boolean).join(' · ');
}

function widgetCompactMeta(entry) {
  const covered = officialDisplaySlot(entry.coveredSlot);
  const fixed = officialDisplaySlot(entry.fixedSlot);
  if (covered) return '#' + covered + ' · ' + widgetQuotaText(entry, true);
  if (fixed && !entry.currentInWhitelist) return '指定 #' + fixed + ' · ' + widgetQuotaText(entry, true);
  return widgetQuotaText(entry);
}

function widgetQuotaText(entry, short = false) {
  if (!(entry.limit > 0 && Number.isInteger(entry.used))) return short ? '未知' : '占用未知';
  return (short ? '' : '占用 ') + entry.used + '/' + entry.limit;
}

function widgetAttemptText(entry) {
  return Number.isFinite(Date.parse(entry.lastAttemptAt || '')) ? '检查 ' + formatTime(entry.lastAttemptAt) : '尚未检查';
}

function widgetDisplayIp(value) {
  return String(value || '').replace(/\/24$/, '');
}

function officialOrderedWhitelist(entry) {
  const rows = Array.isArray(entry?.whitelist) ? entry.whitelist : [];
  return [...rows].sort((left, right) => (officialDisplaySlot(left.slot) || 11) - (officialDisplaySlot(right.slot) || 11));
}

// The API numbers fixed slots but leaves automatically assigned records unnumbered. Records are
// always listed; free cells carry numbers only when every record has a known position.
function widgetSlotModel(entry) {
  const rows = Array.isArray(entry.whitelist) ? officialOrderedWhitelist(entry) : [];
  const records = rows.map(row => ({
    label: officialDisplaySlot(row.slot) ? String(officialDisplaySlot(row.slot)) : '自动',
    row, state: officialSameNetwork(row.ip, entry.currentIp) ? 'current' : 'used',
  }));
  if (!(Number.isInteger(entry.limit) && entry.limit >= 1 && entry.limit <= 10)) return { kind: 'unknown', records, cells: [] };
  const placed = entry.used === rows.length
    && rows.every(row => officialDisplaySlot(row.slot) && row.slot < entry.limit)
    && new Set(rows.map(row => row.slot)).size === rows.length;
  if (placed) {
    return { kind: 'placed', records, cells: Array.from({ length: entry.limit }, (_, slot) =>
      records.find(record => record.row.slot === slot) || { label: String(slot + 1), row: null, state: 'empty' }) };
  }
  const free = Math.max(0, entry.limit - Math.max(rows.length, Number.isInteger(entry.used) ? entry.used : 0));
  return { kind: 'mixed', records, cells: [...records, ...Array.from({ length: free }, () => ({ label: '', row: null, state: 'empty' }))] };
}

function widgetSlotStyle(cell, onCard = false) {
  if (cell.state === 'current') return { backgroundColor: WIDGET_COLORS.greenFill };
  if (cell.state === 'used') return { backgroundColor: onCard ? WIDGET_COLORS.slotOnCard : WIDGET_COLORS.slot };
  return { borderWidth: 1, borderColor: WIDGET_COLORS.slotLine };
}

// Unnumbered capacity bar: solid green = current network, filled = occupied, outline = free.
function widgetSlotMeter(cells, height, onCard = false) {
  const bars = cells.map(cell => ({ type: 'stack', flex: 1, height, borderRadius: 2, ...widgetSlotStyle(cell, onCard), children: [] }));
  // Fillers keep the ten-slot scale aligned between accounts; they are not extra slots.
  while (bars.length < 10) bars.push({ type: 'stack', flex: 1, height, children: [] });
  return widgetRow(bars, 2);
}

// Whitelist record: slot number (or 自动), network and state in one chip.
function widgetSlotChip(cell, size, compact = false) {
  const current = cell.state === 'current';
  const used = cell.state === 'used';
  const color = current ? WIDGET_COLORS.onGreen : used ? WIDGET_COLORS.text : WIDGET_COLORS.tertiary;
  return {
    type: 'stack', direction: 'column', flex: 1, padding: compact ? [2, 8, 2, 3] : [4, 9, 4, 4], borderRadius: compact ? 7 : 9,
    ...widgetSlotStyle(cell, compact),
    children: [spacerNode(), widgetRow([
      widgetColumn(cell.label ? [{ ...widgetText(cell.label, size - 2, current ? WIDGET_COLORS.onGreen : used ? WIDGET_COLORS.secondary : WIDGET_COLORS.tertiary, 'semibold'), minScale: 0.8 }] : [], 0, { width: 24, alignItems: 'center' }),
      { ...widgetText(cell.row ? widgetDisplayIp(cell.row.ip) : '空闲', size, color, current ? 'semibold' : used ? 'medium' : 'regular'), minScale: 0.75 },
      spacerNode(),
      ...(current ? [iconNode('checkmark', WIDGET_COLORS.onGreen, size - 3)] : []),
    ], 4), spacerNode()],
  };
}

function widgetBlankCell() {
  return { type: 'stack', direction: 'column', flex: 1, children: [spacerNode()] };
}

// One account: every slot as a chip, #1-#5 down the first column and #6-#10 down the second.
function widgetSlotList(cells, size) {
  const perColumn = 5;
  const columns = Math.ceil(cells.length / perColumn);
  const lines = [];
  for (let line = 0; line < Math.min(perColumn, cells.length); line++) {
    const chips = Array.from({ length: columns }, (_, column) => cells[column * perColumn + line]);
    lines.push({ ...widgetRow(chips.map(cell => cell ? widgetSlotChip(cell, size) : widgetBlankCell()), 6), flex: 1 });
  }
  return widgetColumn(lines, 6, { flex: 1 });
}

// Keep record order; when space runs out, the current network replaces the last visible record.
function widgetVisibleRecords(records, capacity) {
  if (records.length <= capacity) return { shown: records, more: 0 };
  let shown = records.slice(0, Math.max(1, capacity - 1));
  const current = records.find(record => record.state === 'current');
  if (current && !shown.includes(current)) shown = [...shown.slice(0, -1), current];
  return { shown, more: records.length - shown.length };
}

function widgetRecordGrid(model, rows, size) {
  const { shown, more } = widgetVisibleRecords(model.records, rows * 2);
  const items = shown.map(record => widgetSlotChip(record, size, true));
  if (more) items.push({ type: 'stack', direction: 'column', flex: 1, padding: [2, 8, 2, 8], children: [spacerNode(), widgetLine([widgetText('另 ' + more + ' 条', size - 1, WIDGET_COLORS.secondary)]), spacerNode()] });
  const lines = [];
  for (let index = 0; index < items.length; index += 2) {
    lines.push({ ...widgetRow([items[index], items[index + 1] || widgetBlankCell()], 6), flex: 1 });
  }
  return widgetColumn(lines, 4, { flex: 1 });
}

function widgetRecordLines(model, maximum) {
  const { shown, more } = widgetVisibleRecords(model.records, maximum);
  return widgetColumn([
    ...shown.map(record => {
      const current = record.state === 'current';
      const color = current ? WIDGET_COLORS.green : WIDGET_COLORS.text;
      return widgetLine([
        widgetColumn([widgetText(record.label, 10, current ? WIDGET_COLORS.green : WIDGET_COLORS.secondary, 'semibold')], 0, { width: 22, alignItems: 'center' }),
        { ...widgetText(widgetDisplayIp(record.row.ip), 12, color, current ? 'semibold' : 'regular'), minScale: 0.8 },
        ...(current ? [iconNode('checkmark', WIDGET_COLORS.green, 9)] : []),
      ], 3);
    }),
    ...(more ? [widgetLine([widgetColumn([], 0, { width: 22 }), widgetText('另 ' + more + ' 条', 11, WIDGET_COLORS.secondary)], 3)] : []),
  ], 2);
}

// Large views with two or three accounts share a fixed number of record rows.
function widgetRecordRows(entries, total) {
  const need = entries.map(entry => entry.status === 'error' ? 1 : Math.max(1, Math.ceil(widgetSlotModel(entry).records.length / 2)));
  const rows = need.map(() => 1);
  let left = total - rows.length;
  while (left > 0 && rows.some((row, index) => row < need[index])) {
    for (let index = 0; index < rows.length && left > 0; index++) if (rows[index] < need[index]) { rows[index]++; left--; }
  }
  return rows;
}

function widgetNoRecords(entry, size) {
  return widgetLine([widgetText(entry.limit > 0 ? '暂无白名单记录' : '尚未取得白名单', size, WIDGET_COLORS.secondary)]);
}

function widgetErrorText(entry, size, maxLines) {
  return widgetLine([{ ...widgetText(entry.error || '请求失败，请刷新重试', size, WIDGET_COLORS.secondary), maxLines }]);
}

function widgetPill(text, tone, size = 12) {
  return { type: 'stack', direction: 'row', padding: [3, 8, 3, 8], borderRadius: 10, backgroundColor: WIDGET_TONES[tone].tint,
    children: [widgetText(text, size, WIDGET_TONES[tone].color, 'semibold')] };
}

function widgetLargeSingle(entry) {
  const model = widgetSlotModel(entry);
  const title = widgetRow([
    { ...widgetText(entry.name || '账号', 17, WIDGET_COLORS.text, 'semibold'), flex: 1, minScale: 0.85 },
    widgetText(widgetSlotMeta(entry), 13, WIDGET_COLORS.secondary, 'medium'),
  ], 8);
  let body;
  if (entry.status === 'error') {
    body = widgetColumn([spacerNode(), widgetLine([iconNode('xmark.circle.fill', WIDGET_COLORS.red, 16), widgetText('检查失败', 15, WIDGET_COLORS.red, 'semibold')], 6),
      widgetLine([{ ...widgetText(entry.error || '请求失败，请刷新重试', 13, WIDGET_COLORS.secondary), maxLines: 4 }]), spacerNode()],
    6, { flex: 1, padding: 14, borderRadius: 12, backgroundColor: WIDGET_TONES.error.tint });
  } else if (model.kind === 'unknown') {
    body = widgetColumn([model.records.length ? widgetSlotList(model.records, 13) : widgetLine([widgetText('槽位数量未知', 13, WIDGET_COLORS.secondary)]), spacerNode()], 0, { flex: 1 });
  } else {
    body = widgetSlotList(model.cells, model.cells.length > 5 ? 13 : 14);
  }
  return widgetColumn([title, body], 8, { flex: 1 });
}

function widgetLargeCard(entry, view, rows) {
  const result = widgetEntryResult(entry);
  const model = widgetSlotModel(entry);
  const meta = [widgetSlotMeta(entry)];
  if (view.differentIps && entry.currentIp) meta.push(widgetDisplayIp(entry.currentIp));
  const attempt = widgetAttemptText(entry);
  if (attempt !== '检查 ' + view.timestamp) meta.push(attempt);
  const failed = entry.status === 'error';
  const listed = !failed && model.records.length > 0;
  return widgetColumn([
    widgetRow([
      iconNode(WIDGET_TONES[result.tone].icon, result.color, 14),
      { ...widgetText(entry.name || '账号', 15, WIDGET_COLORS.text, 'semibold'), flex: 1, minScale: 0.85 },
      widgetText((result.tone === 'ok' ? '' : result.text + ' · ') + meta.join(' · '), 12, result.tone === 'ok' ? WIDGET_COLORS.secondary : result.color),
    ], 6),
    failed ? widgetErrorText(entry, 12, rows > 1 ? 2 : 1) : listed ? widgetRecordGrid(model, rows, 12) : widgetNoRecords(entry, 12),
    ...(listed ? [] : [spacerNode()]),
  ], 6, { flex: rows, padding: [8, 10, 9, 10], backgroundColor: WIDGET_COLORS.card, borderRadius: 12 });
}

function widgetMediumCard(entry, count) {
  const result = widgetEntryResult(entry);
  const model = widgetSlotModel(entry);
  const failed = entry.status === 'error';
  const line = widgetRow([
    iconNode(WIDGET_TONES[result.tone].icon, result.color, 12),
    { ...widgetText(entry.name || '账号', 13, WIDGET_COLORS.text, 'semibold'), flex: 1, minScale: 0.85 },
    widgetText(failed ? '检查失败' : widgetCompactMeta(entry), 11, failed ? WIDGET_COLORS.red : WIDGET_COLORS.secondary, 'medium'),
  ], 5);
  if (count === 1) {
    const detail = failed ? widgetErrorText(entry, 11, 3) : model.records.length ? widgetRecordLines(model, 3) : widgetNoRecords(entry, 11);
    return widgetColumn([widgetColumn([line, detail], 5), spacerNode()], 0, { flex: 1, padding: [8, 9, 9, 9], backgroundColor: WIDGET_COLORS.card, borderRadius: 12 });
  }
  const meter = count === 2 && model.cells.length ? [widgetSlotMeter(model.cells, 6, true)] : [];
  return widgetColumn([spacerNode(), widgetColumn([line, ...meter], 5), spacerNode()], 0, { flex: 1, padding: [5, 9, 5, 9], backgroundColor: WIDGET_COLORS.card, borderRadius: 10 });
}

function widgetSmallAccount(entry, count) {
  const result = widgetEntryResult(entry);
  const model = widgetSlotModel(entry);
  const line = widgetRow([
    ...(count > 1 ? [iconNode(WIDGET_TONES[result.tone].icon, result.color, 11)] : []),
    { ...widgetText(entry.name || '账号', 13, WIDGET_COLORS.text, 'semibold'), flex: 1, minScale: 0.85 },
    widgetText(entry.status === 'error' ? '检查失败' : widgetCompactMeta(entry), 11, entry.status === 'error' ? WIDGET_COLORS.red : WIDGET_COLORS.secondary, 'medium'),
  ], 4);
  const meter = count === 1 && model.cells.length ? [widgetSlotMeter(model.cells, 7)] : [];
  return widgetColumn([line, ...meter], 5);
}

function widgetEmptyAccounts(family) {
  return widgetColumn([
    spacerNode(),
    widgetLine([widgetText('尚未配置账号', family === 'small' ? 14 : 16, WIDGET_COLORS.text, 'semibold')]),
    widgetLine([{ ...widgetText('填写上报账号后，运行“PO0 防火墙 · 保存配置”', family === 'small' ? 11 : 13, WIDGET_COLORS.secondary), maxLines: 3 }]),
  ], 4, { flex: 1 });
}

function officialReadOnlyWidget(state, ctx, env) {
  const metrics = widgetMetrics(ctx);
  const entries = widgetOfficialEntries(state, env, ctx?.env);
  const children = [
    widgetLine([iconNode('list.bullet.rectangle', WIDGET_COLORS.secondary, 14), widgetText('PO0 防火墙 · 白名单', 15, WIDGET_COLORS.text, 'semibold')], 6),
    widgetLine([widgetText('仅查询，不修改白名单。', 12, WIDGET_COLORS.secondary)]),
  ];
  for (const entry of entries) {
    const result = widgetEntryResult(entry);
    children.push(widgetColumn([
      widgetLine([{ ...widgetText(entry.name + ' · ' + officialStatusText(entry), 13, result.tone === 'ok' ? WIDGET_COLORS.text : result.color, 'semibold'), maxLines: 2 }]),
      widgetLine([{ ...widgetText(`出口 ${widgetDisplayIp(entry.currentIp) || '未知'} · ${officialDisplaySlot(entry.fixedSlot) ? '指定槽位 #' + officialDisplaySlot(entry.fixedSlot) : '自动分配'} · ${widgetQuotaText(entry)}`, 12, WIDGET_COLORS.secondary), minScale: 0.85 }]),
      ...officialOrderedWhitelist(entry).map(row => widgetLine([widgetText(
        `${officialDisplaySlot(row.slot) ? '#' + officialDisplaySlot(row.slot) : '自动'} · ${row.ip}`,
        13, officialSameNetwork(row.ip, entry.currentIp) ? WIDGET_COLORS.green : WIDGET_COLORS.text, officialSameNetwork(row.ip, entry.currentIp) ? 'semibold' : 'regular',
      )])),
    ], 3));
  }
  if (!entries.length) children.push(widgetLine([{ ...widgetText(state?.error || '尚无检查结果。', 12, WIDGET_COLORS.secondary), maxLines: 2 }]));
  // Leading alignment: long lists overflow at the bottom instead of hiding the title.
  return { type: 'widget', padding: metrics.padding, gap: 7, backgroundColor: WIDGET_COLORS.background, children: [...children, spacerNode()] };
}

function widgetFromState(state, ctx, deviceId = '', env = ctx?.env || {}) {
  if (isOfficialStatusRun(ctx)) return officialReadOnlyWidget(state, ctx, env);
  const family = widgetFamily(ctx);
  const network = ctx?.device ? networkInfo(ctx) : normalizeNetworkInfo(state?.network);
  const ssid = currentWifiSsidFromNetwork(ctx, network);
  const entries = widgetOfficialEntries(state, env, ctx?.env);
  const auto = widgetAutoState(officialTokensConfigured(env), boolEnv(env.OFFICIAL_AUTO_ENABLED, true), Boolean(ssid && normalizeSsidSkipList(env.SKIP_WIFI_SSIDS).includes(ssid)));
  const lastTime = state?.official?.checkedAt || state?.checkedAt || state?.at;
  const ips = [...new Set(entries.map(entry => entry.currentIp?.replace(/\/\d+$/, '')).filter(Boolean))];
  const ip = ips.length > 1 ? '多个出口 IP' : ips[0] || state?.official?.currentIp?.replace(/\/\d+$/, '') || state?.ip || '出口 IP 未知';
  const successCount = entries.filter(entry => /^(hit|updated|shared)$/.test(entry.status)).length;
  const failures = entries.filter(entry => entry.status === 'error').length;
  const limit = family === 'small' ? 2 : 3;
  const shown = entries.slice(0, limit);
  const hidden = entries.length - shown.length;
  const hiddenFailures = entries.slice(limit).filter(entry => entry.status === 'error').length;
  // Hidden accounts still count: one failing or uncovered account changes the summary tone.
  const summary = !entries.length ? '未配置' : failures ? failures + (family === 'small' ? ' 个异常' : ' 个账号异常')
    : entries.length === 1 ? widgetEntryResult(entries[0]).text : successCount + '/' + entries.length + ' 已放行';
  const summaryTone = failures ? 'error' : entries.length && successCount === entries.length ? 'ok'
    : successCount || entries.some(entry => entry.status === 'missing') ? 'warn' : 'idle';
  const networkText = ssid || network.value || '网络未知';
  const notice = state?.uiNotice || (state?.skipType === 'wifi-ssid' ? 'Wi-Fi 已跳过 · 显示上次结果'
    : state?.skipped ? '未到检查时间 · 显示上次结果' : '');
  const schedule = auto.text !== '自动上报已启用' ? auto.text : officialTimerEnabled(env) ? '每 ' + formatDurationSeconds(officialIntervalSeconds(env)) : '网络变化时检查';
  const timestamp = lastTime && Number.isFinite(Date.parse(lastTime)) ? formatTime(lastTime) : '未检查';
  const footer = !entries.length ? { text: '未配置', color: WIDGET_COLORS.secondary } : hidden
    ? { text: '另 ' + hidden + ' 个账号未显示' + (hiddenFailures ? ' · 含 ' + hiddenFailures + ' 个异常' : '') + (notice ? ' · 上次结果' : ''), color: hiddenFailures ? WIDGET_COLORS.red : WIDGET_COLORS.secondary }
    : notice ? { text: family === 'small' ? (state?.skipType === 'wifi-ssid' ? 'Wi-Fi 已跳过' : '显示上次结果') : notice, color: state?.uiNotice === '操作未完成' ? WIDGET_COLORS.red : WIDGET_COLORS.secondary }
      : { text: schedule, color: auto.color };
  const footerRow = widgetRow([
    { ...widgetText(family === 'small' && hidden ? '另 ' + hidden + ' 个账号' : footer.text, family === 'large' ? 12 : 11, footer.color), flex: 1, maxLines: family === 'medium' ? 2 : 1 },
    widgetText(timestamp, family === 'large' ? 12 : 11, WIDGET_COLORS.secondary, 'medium'),
  ], 6);
  const tone = WIDGET_TONES[summaryTone];
  const networkLine = (size, gap = 4) => widgetLine([iconNode(network.icon || 'network', WIDGET_COLORS.secondary, size), { ...widgetText(networkText, size, WIDGET_COLORS.secondary), minScale: 0.85 }], gap);
  const ipText = size => ({ ...widgetText(ip, size, WIDGET_COLORS.text, 'semibold'), minScale: 0.6 });
  const differentIps = new Set(shown.map(entry => entry.currentIp).filter(Boolean)).size > 1;
  let children;
  if (family === 'small') {
    children = [
      widgetRow([iconNode(tone.shield, tone.color, 13), widgetText('PO0', 13, WIDGET_COLORS.text, 'semibold'), spacerNode(), { ...widgetText(summary, 11, tone.color, 'semibold'), minScale: 0.8 }], 4),
      ...(shown.length ? [widgetColumn([widgetLine([ipText(19)]), networkLine(11, 3)], 1)] : []),
      shown.length ? widgetColumn([spacerNode(), widgetColumn(shown.map(entry => widgetSmallAccount(entry, shown.length)), 4)], 0, { flex: 1 }) : widgetEmptyAccounts(family),
      footerRow,
    ];
  } else if (family === 'medium') {
    children = [
      widgetRow([iconNode(tone.shield, tone.color, 15), widgetText('PO0 防火墙', 14, WIDGET_COLORS.text, 'semibold'), spacerNode(), widgetPill(summary, summaryTone, 11)], 6),
      { ...widgetRow([
        widgetColumn([...(shown.length ? [widgetLine([ipText(21)]), networkLine(12)] : [networkLine(12)]), spacerNode(), footerRow], 3, { flex: 1 }),
        shown.length ? widgetColumn(shown.map(entry => widgetMediumCard(entry, shown.length)), shown.length === 3 ? 4 : 5, { flex: 1 }) : widgetEmptyAccounts(family),
      ], 12), flex: 1, alignItems: 'start' },
    ];
  } else {
    const single = shown.length === 1;
    const recordRows = widgetRecordRows(shown, shown.length === 2 ? 5 : 3);
    children = [
      widgetColumn([
        widgetRow([iconNode(tone.shield, tone.color, 16), widgetText('PO0 防火墙', 15, WIDGET_COLORS.text, 'semibold'), spacerNode(), widgetPill(summary, summaryTone)], 6),
        !shown.length ? networkLine(13)
          : single ? widgetColumn([widgetLine([ipText(28)]), networkLine(13)], 1)
          : widgetRow([ipText(24), spacerNode(), iconNode(network.icon || 'network', WIDGET_COLORS.secondary, 12), { ...widgetText(networkText, 12, WIDGET_COLORS.secondary), minScale: 0.85 }], 4),
      ], 4),
      !shown.length ? widgetEmptyAccounts(family)
        : single ? widgetLargeSingle(shown[0])
          : widgetColumn(shown.map((entry, index) => widgetLargeCard(entry, { differentIps, timestamp }, recordRows[index])), 8, { flex: 1 }),
      footerRow,
    ];
  }
  return {
    type: 'widget', padding: widgetMetrics(ctx).padding, gap: family === 'large' ? 10 : family === 'medium' ? 8 : 5,
    backgroundColor: WIDGET_COLORS.background,
    ...widgetRefreshSchedule(env, auto, entries), children,
  };
}

function carrierLabel(carrier) {
  const text = String(carrier || '').trim();
  if (!text) return '';
  if (/cmcc|china mobile|中国移动/i.test(text)) return '中国移动';
  if (/cucc|china unicom|中国联通/i.test(text)) return '中国联通';
  if (/ctcc|china telecom|中国电信/i.test(text)) return '中国电信';
  return text;
}

function radioLabel(radio) {
  const key = String(radio || '').toUpperCase().replace(/\s+/g, '');
  const labels = {
    NRNSA: '5G',
    NR: '5G',
    LTE: '4G',
    WCDMA: '3G',
    HSDPA: '3G',
    HSUPA: '3G',
    EDGE: '2G',
    GPRS: '2G',
  };
  return labels[key] || radio || '';
}

function normalizeSsidSkipList(value) {
  return String(value || '')
    .split(';')
    .map((item) => item.trim())
    .filter(Boolean);
}

function currentWifiSsidFromNetwork(ctx, network) {
  const raw = String(ctx?.device?.wifi?.ssid || network?.ssid || '').trim();
  if (!raw || network?.kind !== 'wifi') return '';
  return raw;
}

function ssidSkipDecision(ctx, env, network) {
  // A widget refresh is not an explicit request to override the SSID guard.
  const explicitForce = !isWidgetRun(ctx) && !isAutomaticReportRun(ctx)
    && /强制上报|(^|\s)force(\s|$)/i.test(scriptLabel(ctx));
  if (explicitForce) return { skip: false };
  const skipList = normalizeSsidSkipList(env?.SKIP_WIFI_SSIDS);
  if (skipList.length === 0) return { skip: false };
  const ssid = currentWifiSsidFromNetwork(ctx, network);
  if (!ssid) return { skip: false };
  if (!skipList.includes(ssid)) return { skip: false, ssid };
  return { skip: true, ssid };
}

function networkInfo(ctx) {
  const device = ctx?.device || {};
  const runtimeNetwork = (typeof $network !== 'undefined') ? $network : (ctx?.network || {});
  const localIp = runtimeNetwork?.v4?.primaryAddress || device?.ipv4?.address || '';
  const gateway = runtimeNetwork?.v4?.primaryRouter || device?.ipv4?.gateway || '';
  const wifiName = String(device?.wifi?.ssid || '').trim();
  const carrier = carrierLabel(device?.cellular?.carrier || '');
  const radio = radioLabel(device?.cellular?.radio || '');

  if (wifiName) {
    return {
      kind: 'wifi',
      label: 'Wi-Fi',
      value: wifiName,
      ssid: wifiName,
      icon: 'wifi',
      localIp,
      gateway,
    };
  }

  if (radio || carrier) {
    return {
      kind: 'cellular',
      label: '蜂窝',
      value: [carrier, radio].filter(Boolean).join(' ') || '未知',
      icon: 'antenna.radiowaves.left.and.right',
      localIp,
      gateway,
    };
  }

  return {
    kind: 'unknown',
    label: '网络',
    value: '未知',
    icon: 'network',
    localIp,
    gateway,
  };
}

function normalizeNetworkInfo(value) {
  if (value && typeof value === 'object') {
    return {
      kind: value.kind || 'unknown',
      label: value.label || '网络',
      value: value.value || '未知',
      ssid: value.ssid || (value.kind === 'wifi' ? value.value || '' : ''),
      icon: value.icon || 'network',
      localIp: value.localIp || '',
      gateway: value.gateway || '',
    };
  }
  return {
    kind: 'unknown',
    label: '网络',
    value: String(value || '未知'),
    ssid: '',
    icon: 'network',
    localIp: '',
    gateway: '',
  };
}

async function storageSet(ctx, key, value) {
  const storage = ctx?.storage;
  if (!storage) return false;
  if (typeof storage.set === 'function') {
    return (await storage.set(key, value)) !== false;
  }
  if (typeof storage.setItem === 'function') {
    return (await storage.setItem(key, value)) !== false;
  }
  if (typeof storage.write === 'function') {
    return (await storage.write(key, value)) !== false;
  }
  return false;
}

async function storageGet(ctx, key) {
  const storage = ctx?.storage;
  if (!storage) return null;
  if (typeof storage.get === 'function') return await storage.get(key);
  if (typeof storage.getItem === 'function') return await storage.getItem(key);
  if (typeof storage.read === 'function') return await storage.read(key);
  return null;
}

async function storageDelete(ctx, key) {
  const storage = ctx?.storage;
  if (!storage) return false;
  if (typeof storage.delete === 'function') {
    await storage.delete(key);
    return true;
  }
  if (typeof storage.remove === 'function') {
    await storage.remove(key);
    return true;
  }
  if (typeof storage.removeItem === 'function') {
    await storage.removeItem(key);
    return true;
  }
  return await storageSet(ctx, key, '');
}

function parseReportLock(raw) {
  let value = raw;
  if (typeof value === 'string') {
    try { value = JSON.parse(value); } catch (_) { return null; }
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const owner = String(value.owner || '');
  const expiresAt = Number(value.expiresAt);
  if (!owner || !Number.isFinite(expiresAt)) return null;
  return { owner, expiresAt };
}

async function acquireReportLock(ctx, mode, nowMs) {
  const existing = parseReportLock(await storageGet(ctx, REPORT_LOCK_KEY));
  if (existing && existing.expiresAt > nowMs) return null;
  const owner = `${nowMs}-${Math.random().toString(36).slice(2, 10)}`;
  const record = {
    version: 1,
    owner,
    mode: String(mode || 'report'),
    startedAt: nowMs,
    expiresAt: nowMs + REPORT_LOCK_TTL_MS,
  };
  if (!await storageSet(ctx, REPORT_LOCK_KEY, JSON.stringify(record))) return null;
  const confirmed = parseReportLock(await storageGet(ctx, REPORT_LOCK_KEY));
  return confirmed && confirmed.owner === owner ? record : null;
}

async function releaseReportLock(ctx, lock) {
  if (!lock || !lock.owner) return;
  const current = parseReportLock(await storageGet(ctx, REPORT_LOCK_KEY));
  if (current && current.owner === lock.owner) await storageDelete(ctx, REPORT_LOCK_KEY);
}


function persistableEnvValues(env) {
  const values = {};
  for (const key of PERSISTED_ENV_KEYS) {
    const value = env?.[key];
    if (value === undefined || value === null) continue;
    const text = String(value).trim();
    if (text) values[key] = text;
  }
  return values;
}

function effectiveReportEnv(localValues, runtimeEnv = {}) {
  const env = persistableEnvValues(localValues);
  // Missing/empty live values use current defaults, never an old storage snapshot.
  for (const key of LIVE_ENV_KEYS) {
    if (runtimeEnv[key] !== undefined && runtimeEnv[key] !== null) env[key] = String(runtimeEnv[key]).trim();
  }
  return env;
}


async function storedReportConfig(ctx) {
  const raw = await storageGet(ctx, CONFIG_STORAGE_KEY);
  if (raw === undefined || raw === null || String(raw).trim() === '') {
    return { exists: false, values: {}, savedAt: '' };
  }

  let parsed = raw;
  if (typeof parsed !== 'object') {
    try {
      parsed = JSON.parse(String(raw));
    } catch (_) {
      throw new Error('本机配置已损坏；请运行“PO0 防火墙 · 清除配置”后重新保存。');
    }
  }

  if (
    !parsed
    || typeof parsed !== 'object'
    || parsed.version !== CONFIG_STORAGE_VERSION
    || !parsed.values
    || typeof parsed.values !== 'object'
  ) {
    throw new Error('本机配置版本无效；请运行“PO0 防火墙 · 清除配置”后重新保存。');
  }

  const values = persistableEnvValues(parsed.values);
  return {
    exists: true,
    values,
    savedAt: String(parsed.savedAt || ''),
  };
}

async function saveReportConfig(ctx, env) {
  const values = persistableEnvValues(env);
  if (String(values.PO0_FIREWALL_TOKENS || '').includes('|')) {
    const items = parseOfficialTokens(values.PO0_FIREWALL_TOKENS);
    // Persist names separately so legacy name-only edits can rename/clear them
    // without changing credentials, fixed slots or per-account timer options.
    const names = items.map((item, index) => officialAccountLabel(env, item, index));
    values.PO0_FIREWALL_TOKENS = items.map(officialTokenWithoutName).join('\n');
    if (names.some(Boolean)) values.PO0_FIREWALL_NAMES = names.join(';');
    else delete values.PO0_FIREWALL_NAMES;
  }
  if (String(values.PO0_FIREWALL_WIFI_TOKENS || '').includes('|')) {
    const items = parseOfficialTokens(values.PO0_FIREWALL_WIFI_TOKENS);
    const names = items.map((item, index) => officialAccountLabel({ PO0_FIREWALL_NAMES: values.PO0_FIREWALL_WIFI_NAMES }, item, index));
    values.PO0_FIREWALL_WIFI_TOKENS = items.map(officialTokenWithoutName).join('\n');
    if (names.some(Boolean)) values.PO0_FIREWALL_WIFI_NAMES = names.join(';');
    else delete values.PO0_FIREWALL_WIFI_NAMES;
  }
  const savedAt = new Date().toISOString();
  const saved = await storageSet(ctx, CONFIG_STORAGE_KEY, JSON.stringify({
    version: CONFIG_STORAGE_VERSION,
    savedAt,
    values,
  }));
  if (!saved) {
    throw new Error('Egern 本机存储不可用，无法保存配置。');
  }
  return { values, savedAt };
}


function parseStoredState(raw) {
  if (!raw) return null;
  if (typeof raw === 'object') return raw;
  try {
    return JSON.parse(String(raw));
  } catch (_) {
    return null;
  }
}

function shortHash(value) {
  const text = String(value || '');
  let hash = 2166136261;
  for (let i = 0; i < text.length; i += 1) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16);
}

function sanitizedStoredState(raw) {
  const old = parseStoredState(raw);
  if (!old) return null;
  const state = {};
  for (const key of ['ok', 'at', 'checkedAt', 'ip', 'ipProfile', 'network', 'skipped', 'skipType', 'uiNotice']) if (old[key] !== undefined) state[key] = old[key];
  if (old.official) state.official = sanitizeOfficialState(old.official);
  return state;
}

function sanitizeOfficialEntry(entry = {}) {
  const clean = {
    name: String(entry.name || ''),
    accountKey: /^[0-9a-f]{1,8}$/.test(String(entry.accountKey || '')) ? String(entry.accountKey) : '',
    ordinal: Number.isInteger(entry.ordinal) ? entry.ordinal : 0,
    slot: Number.isInteger(entry.slot) ? entry.slot : null,
    fixedSlot: Number.isInteger(entry.fixedSlot) ? entry.fixedSlot : null,
    coveredSlot: officialDisplaySlot(entry.coveredSlot) ? entry.coveredSlot : null,
    status: String(entry.status || 'error'),
    lastAttemptAt: entry.lastAttemptAt === undefined ? undefined : String(entry.lastAttemptAt || ''),
    currentIp: officialCidr24(entry.currentIp) || '',
    used: Number.isInteger(entry.used) ? entry.used : 0,
    limit: Number.isInteger(entry.limit) ? entry.limit : 0,
    currentInWhitelist: Boolean(entry.currentInWhitelist),
  };
  if (Array.isArray(entry.whitelist)) {
    clean.whitelist = entry.whitelist
      .map((item) => ({
        ip: officialCidr24(item?.ip) || '',
        slot: Number.isInteger(item?.slot) ? item.slot : null,
      }))
      .filter((item) => item.ip);
  } else {
    clean.whitelist = [];
  }
  if (entry.error) clean.error = officialSafeError({ message: String(entry.error) });
  return clean;
}

function sanitizeOfficialState(raw) {
  const state = parseStoredState(raw);
  if (!state || typeof state !== 'object' || Array.isArray(state)) return null;
  const entries = Array.isArray(state.entries) ? state.entries.map(sanitizeOfficialEntry) : [];
  const clean = {
    version: 1,
    networkContext: String(state.networkContext || ''),
    ok: Boolean(state.ok),
    status: String(state.status || 'unknown'),
    skipped: Boolean(state.skipped),
    checkedAt: String(state.checkedAt || ''),
    lastAttemptAt: String(state.lastAttemptAt || ''),
    lastSuccessAt: String(state.lastSuccessAt || ''),
    currentIp: officialCidr24(state.currentIp) || entries.find((entry) => entry.currentIp)?.currentIp || '',
    used: Number.isInteger(state.used) ? state.used : entries[0]?.used || 0,
    limit: Number.isInteger(state.limit) ? state.limit : entries[0]?.limit || 0,
    successCount: Number.isInteger(state.successCount) ? state.successCount : entries.filter((entry) => entry.status !== 'error').length,
    failureCount: Number.isInteger(state.failureCount) ? state.failureCount : entries.filter((entry) => entry.status === 'error').length,
    entries,
  };
  const first = entries.find((entry) => entry.currentIp) || entries[0];
  clean.whitelist = Array.isArray(state.whitelist)
    ? state.whitelist.map((item) => ({
      ip: officialCidr24(item?.ip) || '',
      slot: Number.isInteger(item?.slot) ? item.slot : null,
    })).filter((item) => item.ip)
    : first?.whitelist || [];
  return clean;
}

async function storedOfficialState(ctx) {
  return sanitizeOfficialState(await storageGet(ctx, OFFICIAL_STORAGE_KEY));
}

function isNetworkChangeRun(ctx) {
  return /network|网络变化/i.test(scriptLabel(ctx));
}
function officialIntervalSeconds(env, item = {}) {
  const value = Number(String(env?.OFFICIAL_INTERVAL_SECONDS ?? '').trim() || DEFAULT_OFFICIAL_INTERVAL_SECONDS);
  if (!Number.isInteger(value) || value < 60 || value > 86400) throw new Error('上报间隔必须为 60～86400 秒');
  return value;
}
function officialTimerEnabled(env, item = {}) {
  return boolEnv(env.OFFICIAL_TIMER_ENABLED, true);
}
function officialIsDue(ctx, state, env = {}, item = {}) {
  if (!isAutomaticReportRun(ctx) || isNetworkChangeRun(ctx)) return true;
  if (!officialTimerEnabled(env, item)) return false;
  const last = Date.parse(String(state?.lastAttemptAt || ''));
  if (!Number.isFinite(last)) return true;
  const age = officialNowMs() - last;
  return age < 0 || age >= officialIntervalSeconds(env, item) * 1000;
}

function officialStateFromEntries(entries, mode, now, previous, skipped = false) {
  const cleanEntries = entries.map(sanitizeOfficialEntry);
  const failures = cleanEntries.filter((entry) => entry.status === 'error').length;
  const successes = cleanEntries.filter(entry => /^(hit|updated|shared|missing)$/.test(entry.status)).length;
  const first = cleanEntries.find((entry) => entry.currentIp) || cleanEntries[0] || {};
  const state = {
    version: 1,
    ok: failures === 0,
    status: skipped ? 'due-skipped' : failures > 0 ? (successes > 0 ? 'partial' : 'failed') : mode === 'status' ? 'status' : 'success',
    skipped,
    checkedAt: now,
    lastAttemptAt: mode === 'report' ? now : String(previous?.lastAttemptAt || ''),
    lastSuccessAt: mode === 'report' && failures === 0 ? now : String(previous?.lastSuccessAt || ''),
    currentIp: first.currentIp || String(previous?.currentIp || ''),
    whitelist: first.whitelist || previous?.whitelist || [],
    used: Number.isInteger(first.used) ? first.used : Number.isInteger(previous?.used) ? previous.used : 0,
    limit: Number.isInteger(first.limit) ? first.limit : Number.isInteger(previous?.limit) ? previous.limit : 0,
    successCount: successes,
    failureCount: failures,
    entries: cleanEntries,
  };
  return state;
}

function officialConfigErrorState(error, mode, previous) {
  const message = officialSafeError(error);
  const now = officialNowIso();
  const entry = sanitizeOfficialEntry({ ordinal: 0, status: 'error', error: message });
  const state = officialStateFromEntries([entry], mode, now, previous);
  state.status = 'config-error';
  state.lastAttemptAt = String(previous?.lastAttemptAt || '');
  state.lastSuccessAt = String(previous?.lastSuccessAt || '');
  return { active: true, ok: false, state, skipped: false, needsNotification: false };
}

async function runOfficialFirewall(ctx, env, mode = 'report') {
  let previous = await storedOfficialState(ctx);
  const networkContext = env._officialNetwork || '';
  if (networkContext === 'unknown') {
    return officialConfigErrorState(new Error('无法识别当前网络，已跳过上报。'), mode, previous);
  }
  if (networkContext && previous?.networkContext !== networkContext) previous = null;
  let items;
  try {
    items = parseOfficialTokens(env?.PO0_FIREWALL_TOKENS);
  } catch (error) {
    return officialConfigErrorState(error, mode, previous);
  }
  if (items.length === 0) return { active: false, ok: true, state: previous, skipped: false, needsNotification: false };

  const previousEntries = items.map(item => {
    const entry = previous?.entries.find(entry => entry.accountKey === shortHash(item.token) && entry.fixedSlot === item.slot);
    return entry ? { ...entry, lastAttemptAt: entry.lastAttemptAt ?? previous.lastAttemptAt } : null;
  });
  const due = items.map((item, index) => mode !== 'report' || officialIsDue(ctx, previousEntries[index], env, item));
  if (!due.some(Boolean)) {
    const dueState = previous
      ? { ...previous, skipped: true, status: 'due-skipped', checkedAt: officialNowIso() }
      : officialStateFromEntries([], mode, officialNowIso(), previous, true);
    return {
      active: true,
      ok: true,
      state: dueState,
      skipped: true,
      needsNotification: false,
    };
  }

  const now = officialNowIso();
  const entries = [];
  let needsNotification = false;
  if (mode === 'report') {
    await storageSet(ctx, OFFICIAL_STORAGE_KEY, JSON.stringify({
      version: 1,
      ok: false,
      status: 'running',
      networkContext,
      skipped: false,
      checkedAt: now,
      lastAttemptAt: now,
      lastSuccessAt: String(previous?.lastSuccessAt || ''),
      currentIp: String(previous?.currentIp || ''),
      whitelist: Array.isArray(previous?.whitelist) ? previous.whitelist : [],
      used: previous?.used || 0,
      limit: previous?.limit || 0,
      successCount: 0,
      failureCount: 0,
      entries: items.map((item, index) => sanitizeOfficialEntry({
        ...previousEntries[index], accountKey: shortHash(item.token), fixedSlot: item.slot,
        lastAttemptAt: due[index] ? now : previousEntries[index]?.lastAttemptAt || '',
      })),
    }));
  }

  const runOfficialAccount = async (item, index) => {
    if (!due[index]) return {
      entry: sanitizeOfficialEntry({ ...previousEntries[index],
        accountKey: shortHash(item.token), name: officialAccountName(env, index),
        ordinal: index + 1, slot: item.slot, fixedSlot: item.slot,
        status: previousEntries[index]?.status || 'pending',
        lastAttemptAt: previousEntries[index]?.lastAttemptAt || '',
      }), needsNotification: false,
    };
    const entry = {
      accountKey: shortHash(item.token),
      name: officialAccountName(env, index),
      ordinal: index + 1,
      slot: item.slot,
      fixedSlot: item.slot,
      status: 'error',
      lastAttemptAt: mode === 'report' ? now : String(previousEntries[index]?.lastAttemptAt || ''),
      currentIp: '',
      used: 0,
      limit: 0,
      currentInWhitelist: false,
      whitelist: [],
    };
    try {
      const status = await officialDirectRequest(ctx, item, 'get');
      const covered = applyOfficialPayload(entry, status, item, 'hit');
      if (!covered && mode === 'status') {
        entry.status = 'missing';
      } else if (!covered) {
        try {
          const updated = await officialDirectRequest(ctx, item, 'post');
          if (!applyOfficialPayload(entry, updated, item, 'updated')) throw new Error('防火墙更新后未确认当前出口。');
        } catch (error) {
          if (error.httpStatus !== 403) throw error;
          // Another device may have added this network after our first GET.
          // Confirm once; never delete a slot or repeat a rejected write.
          let confirmed = false;
          try {
            const latest = await officialDirectRequest(ctx, item, 'get');
            confirmed = applyOfficialPayload(entry, latest, item, 'hit');
          } catch (_) {}
          if (!confirmed) throw error;
        }
      }
    } catch (error) {
      entry.error = officialSafeError(error);
    }
    return {
      entry: sanitizeOfficialEntry(entry),
      needsNotification: entry.status === 'updated',
    };
  };

  // Accounts are independent, so run them concurrently. Each account keeps
  // its own strict GET -> optional POST sequence, and Promise.all preserves
  // configured order for state/UI output.
  const results = await Promise.all(items.map((item, index) => runOfficialAccount(item, index)));
  for (const [index, result] of results.entries()) {
    entries.push(result.entry);
    if (due[index] && result.entry.status === 'error') {
      try { logMessage(ctx, 'error', '账号 ' + result.entry.ordinal + ' 检查失败', result.entry.error); } catch (_) {}
    }
  }
  needsNotification = results.some((result) => result.needsNotification);

  const state = officialStateFromEntries(entries, mode, now, previous);
  state.networkContext = networkContext;
  await storageSet(ctx, OFFICIAL_STORAGE_KEY, JSON.stringify(state));
  return {
    active: true,
    ok: state.failureCount === 0,
    state,
    skipped: false,
    needsNotification,
  };
}

function notify(ctx, title, body) {
  if (!ctx || typeof ctx.notify !== 'function') return;
  ctx.notify({ title: redactSensitiveText(title), body: redactSensitiveText(body) });
}

function logMessage(ctx, level, message, detail = '') {
  const safeMessage = redactSensitiveText(message);
  const safeDetail = redactSensitiveText(detail);
  const line = '[' + REPORT_TITLE + '] ' + safeMessage + (safeDetail ? ': ' + safeDetail : '');
  try {
    if (level === 'error') console.error(line);
    else console.log(line);
  } catch (_) {}
  try {
    if (typeof ctx?.log === 'function') ctx.log(line);
  } catch (_) {}
}

async function handleScopedConfigSaveScript(ctx, runtimeEnv, storedValues) {
  const title = '配置';
  try {
    let candidate;
    {
      const input = String(runtimeEnv.PO0_FIREWALL_TOKENS || '').trim() || String(storedValues?.PO0_FIREWALL_TOKENS || '').trim();
      if (!input) throw new Error('请填写上报账号；清空请运行“PO0 防火墙 · 清除配置”。');
      parseOfficialTokens(input);
      candidate = { ...(storedValues || {}), PO0_FIREWALL_TOKENS: input };
      candidate.PO0_FIREWALL_NAMES = officialNamesForSave(storedValues || {}, runtimeEnv, input);
      if (runtimeEnv.OFFICIAL_AUTO_ENABLED !== undefined) candidate.OFFICIAL_AUTO_ENABLED = String(runtimeEnv.OFFICIAL_AUTO_ENABLED);
      for (const key of ['PO0_FIREWALL_WIFI_TOKENS']) {
        if (runtimeEnv[key] !== undefined && String(runtimeEnv[key]).trim()) candidate[key] = String(runtimeEnv[key]);
      }
      if (candidate.PO0_FIREWALL_WIFI_TOKENS === '-') delete candidate.PO0_FIREWALL_WIFI_TOKENS;
      if (candidate.PO0_FIREWALL_WIFI_TOKENS) {
        parseOfficialTokens(candidate.PO0_FIREWALL_WIFI_TOKENS);
        candidate.PO0_FIREWALL_WIFI_NAMES = officialNamesForSave(
          officialNetworkEnv({ ...storedValues, OFFICIAL_NETWORK_TARGETS_ENABLED: 'true' }, { kind: 'wifi' }),
          { PO0_FIREWALL_TOKENS: runtimeEnv.PO0_FIREWALL_WIFI_TOKENS }, candidate.PO0_FIREWALL_WIFI_TOKENS);
      }
      if (boolEnv(runtimeEnv.OFFICIAL_NETWORK_TARGETS_ENABLED, false) && !candidate.PO0_FIREWALL_WIFI_TOKENS) {
        throw new Error('请先填写并保存 Wi-Fi 账号，再开启按网络选择。');
      }
      officialIntervalSeconds(effectiveReportEnv(candidate, runtimeEnv));
    }
    await saveReportConfig(ctx, candidate);
    notify(ctx, REPORT_TITLE, '配置已保存');
    return widgetPanel(REPORT_TITLE, [title + '已保存。', ...officialSavedNameRows(effectiveReportEnv(candidate, runtimeEnv)), ...officialNetworkSettingsRows(effectiveReportEnv(candidate, runtimeEnv)), '账号和槽位已保存到本机，本次未上报。'], true, ctx);
  } catch (error) {
    return widgetPanel(REPORT_TITLE, [title + '未保存。', redactError(error, { ...(storedValues || {}), ...runtimeEnv })], false, ctx);
  }
}

async function handleOfficialConfigClearScript(ctx) {
  await saveReportConfig(ctx, { OFFICIAL_AUTO_ENABLED: 'false' });
  await storageDelete(ctx, OFFICIAL_STORAGE_KEY);
  await storageDelete(ctx, STORAGE_KEY);
  await storageDelete(ctx, ERROR_STORAGE_KEY);
  return widgetPanel(REPORT_TITLE, ['本机账号、配置和最近结果已清除，自动上报已停用。', '恢复使用请保存账号，再启用自动上报。'], true, ctx);
}

function officialFailureSummary(result) {
  const entries = Array.isArray(result?.state?.entries) ? result.state.entries : [];
  return entries
    .filter((entry) => entry.status === 'error')
    .map((entry) => {
      const displaySlot = officialDisplaySlot(entry.slot);
      const slot = displaySlot === null ? '' : `（槽位 #${displaySlot}）`;
      return `${entry.name || '账号 ' + (entry.ordinal || '?')}${slot}：${entry.error || '防火墙请求失败。'}`;
    })
    .join('；');
}

function officialUpdateSummary(result) {
  const entries = Array.isArray(result?.state?.entries) ? result.state.entries : [];
  return entries.filter(entry => entry.status === 'updated').map(entry => {
    const slot = officialDisplaySlot(entry.coveredSlot);
    return (entry.name || '账号 ' + (entry.ordinal || '?')) + ' · 已放行 · ' + (slot ? '槽位 #' + slot : '自动槽位') + ' · ' + (entry.currentIp || '出口 IP 未知');
  }).join('；');
}

function parseOfficialNames(value) {
  const raw = String(value || '').trim();
  return raw === '-' ? [] : raw.replace(/\r\n?/g, '\n').split(/[,;，；\n]/).map(name => name.trim());
}

function officialAccountLabel(env, item, index) {
  const name = item.name || parseOfficialNames(env.PO0_FIREWALL_NAMES)[index] || '';
  return name === '-' ? '' : name;
}

function officialAccountName(env, index) {
  let item = {};
  try { item = parseOfficialTokens(env.PO0_FIREWALL_TOKENS)[index] || {}; } catch (_) {}
  return officialAccountLabel(env, item, index) || ('账号 ' + (index + 1));
}

function officialDisplayEnv(env, runtimeEnv) {
  if (env._officialNetwork) runtimeEnv = officialNetworkEnv({ ...runtimeEnv, OFFICIAL_NETWORK_TARGETS_ENABLED: 'true' }, { kind: env._officialNetwork });
  if (!String(runtimeEnv?.PO0_FIREWALL_NAMES || '').trim() && !String(runtimeEnv?.PO0_FIREWALL_TOKENS || '').includes('|')) return env;
  try {
    const accounts = parseOfficialTokens(env.PO0_FIREWALL_TOKENS);
    const moduleAccounts = String(runtimeEnv.PO0_FIREWALL_TOKENS || '').trim()
      ? parseOfficialTokens(runtimeEnv.PO0_FIREWALL_TOKENS) : accounts;
    const moduleNames = moduleAccounts.map((item, index) => officialAccountLabel(runtimeEnv, item, index));
    // Sync can update display names only, matched by token; reporting continues
    // using saved local credentials/slots; time settings come from live parameters.
    const names = accounts.map((account, index) => {
      const moduleIndex = moduleAccounts.findIndex(item => item.token === account.token);
      const clear = moduleAccounts[moduleIndex]?.name === '-' || String(runtimeEnv.PO0_FIREWALL_NAMES || '').trim() === '-';
      return moduleIndex >= 0 && clear ? '' : moduleNames[moduleIndex] || officialAccountLabel(env, account, index);
    });
    return { ...env, PO0_FIREWALL_TOKENS: accounts.map(officialTokenWithoutName).join('\n'), PO0_FIREWALL_NAMES: names.join(';') };
  } catch (_) { return env; }
}

function officialSavedNameRows(env) {
  let items;
  try { items = parseOfficialTokens(env.PO0_FIREWALL_TOKENS); } catch (_) { return []; }
  return items.map((item, index) => officialAccountName(env, index) + ' · ' + (officialDisplaySlot(item.slot) ? '指定槽位 #' + officialDisplaySlot(item.slot) : '自动槽位'));
}

function officialNamesForSave(stored, runtime, tokens) {
  let oldTokens = [];
  try { oldTokens = parseOfficialTokens(stored.PO0_FIREWALL_TOKENS); } catch (_) {}
  const explicitNames = String(runtime.PO0_FIREWALL_NAMES || '').trim();
  const names = parseOfficialTokens(tokens).map((item, index) => {
    if (item.name) return item.name === '-' ? '' : item.name;
    if (explicitNames) return parseOfficialNames(explicitNames)[index] || '';
    const oldIndex = oldTokens.findIndex(old => old.token === item.token);
    return oldIndex < 0 ? '' : officialAccountLabel(stored, oldTokens[oldIndex], oldIndex);
  });
  return names.some(Boolean) ? names.join(';') : '';
}

function localChannelAction(ctx) {
  const label = scriptLabel(ctx);
  if (/清除本机自建(?: PO0 |防火墙)配置/.test(label)) return 'clear-worker';
  if (/启用自建防火墙自动上报/.test(label)) return 'enable-worker';
  if (/停用自建防火墙自动上报/.test(label)) return 'disable-worker';
  if (/启用官方防火墙自动上报/.test(label)) return 'enable-official';
  if (/停用官方防火墙自动上报/.test(label)) return 'disable-official';
  if (/切换自建(?: PO0 |防火墙)自动上报/.test(label)) return 'toggle-worker';
  if (/切换官方防火墙自动上报/.test(label)) return 'toggle-official';
  if (/通用设置 · 保存配置/.test(label)) return 'save-common';
  if (/查看本机上报设置/.test(label)) return 'settings';
  if (/查看最近结果/.test(label)) return 'recent';
  return '';
}

async function handleLocalChannelAction(ctx, env, action) {
  if (action === 'recent') {
    const state = sanitizedStoredState(await storageGet(ctx, STORAGE_KEY)) || {};
    state.official = await storedOfficialState(ctx);
    state.uiNotice = '显示上次结果 · 本次未检查';
    return widgetFromState(state, ctx, '', officialNetworkEnv(env, networkInfo(ctx)));
  }
  const next = { ...env };
  if (/^(toggle|enable|disable)-official$/.test(action)) {
    next.OFFICIAL_AUTO_ENABLED = action.startsWith('enable-') || (action.startsWith('toggle-') && !boolEnv(next.OFFICIAL_AUTO_ENABLED, true)) ? 'true' : 'false';
    await saveReportConfig(ctx, next);
  }
  return widgetPanel(REPORT_TITLE + ' · 本机设置', [
    '账号与槽位保存在本机。',
    '其他设置修改后立即生效。',
    '自动上报：' + (boolEnv(next.OFFICIAL_AUTO_ENABLED, true) ? '已启用' : '已停用'),
    '定期上报：' + (officialTimerEnabled(next) ? '每 ' + formatDurationSeconds(officialIntervalSeconds(next)) : '已停用'),
    ...officialSavedNameRows(officialDisplayEnv(next, ctx?.env)), ...officialNetworkSettingsRows(next),
    '跳过的 Wi-Fi：' + (next.SKIP_WIFI_SSIDS || '未设置'),
    '“强制上报”可忽略 Wi-Fi 跳过设置；“查询白名单”不修改白名单。',
  ], true, ctx);
}


async function runEgernReportUnlocked(ctx) {
  if (retiredAction(ctx)) return widgetPanel(REPORT_TITLE, ['自建防火墙与设备 ID 功能已退役。', '旧版代码和配置恢复说明见归档版本。本次未发起上报。'], true, ctx);
  await migrateRetiredState(ctx);
  const runtime = ctx?.env || {};
  const stored = await storedReportConfig(ctx);
  if (isOfficialConfigSaveRun(ctx) || isReportConfigSaveRun(ctx)) return handleScopedConfigSaveScript(ctx, runtime, stored.values);
  if (isOfficialConfigClearRun(ctx) || isReportConfigClearRun(ctx)) return handleOfficialConfigClearScript(ctx);
  const configEnv = effectiveReportEnv(stored.exists ? stored.values : runtime, runtime);
  const action = localChannelAction(ctx);
  if (action) return handleLocalChannelAction(ctx, configEnv, action);
  const network = networkInfo(ctx);
  const env = officialNetworkEnv(configEnv, network);
  const automatic = isAutomaticReportRun(ctx);
  let state = sanitizedStoredState(await storageGet(ctx, STORAGE_KEY)) || {};
  state.official = await storedOfficialState(ctx);
  state.network = network;
  const result = () => shouldReturnWidget(ctx) ? widgetFromState(state, ctx, '', env) : state;
  if (!officialTokensConfigured(configEnv)) {
    state = { ...state, ok: true, skipped: true, uiNotice: '尚未配置账号' };
    return result();
  }
  try {
    parseOfficialTokens(configEnv.PO0_FIREWALL_TOKENS);
    if (configEnv.PO0_FIREWALL_WIFI_TOKENS) parseOfficialTokens(configEnv.PO0_FIREWALL_WIFI_TOKENS);
    if (!stored.exists) await saveReportConfig(ctx, configEnv);
    if (automatic && (!boolEnv(env.OFFICIAL_AUTO_ENABLED, true) || (!isNetworkChangeRun(ctx) && !officialTimerEnabled(env)))) {
      state = { ...state, ok: true, skipped: true, uiNotice: '自动上报已暂停 · 显示上次结果' };
      return result();
    }
    if (!isOfficialStatusRun(ctx) && ssidSkipDecision(ctx, env, network).skip) {
      state = { ...state, ok: true, skipped: true, skipType: 'wifi-ssid', uiNotice: 'Wi-Fi 已跳过 · 本次未上报 · 显示上次结果' };
      if (!await storageSet(ctx, STORAGE_KEY, JSON.stringify(state))) throw new Error('无法保存跳过状态');
      logMessage(ctx, 'info', 'Wi-Fi 已跳过：本次未检查，显示上次结果。');
      return result();
    }
    const reported = await runOfficialFirewall(ctx, env, isOfficialStatusRun(ctx) ? 'status' : 'report');
    state = { ok: reported.ok, network, official: reported.state, skipped: reported.skipped, checkedAt: officialNowIso(), ip: reported.state?.currentIp?.replace(/\/\d+$/, '') || '', error: reported.ok ? '' : '防火墙检查未完成' };
    if (!reported.skipped && reported.ok) state.at = reported.state?.lastSuccessAt || officialNowIso();
    if (!await storageSet(ctx, STORAGE_KEY, JSON.stringify(state))) throw new Error('无法保存上报状态');
    if (!reported.ok && boolEnv(env.NOTIFY_FAILURE, true)) notify(ctx, REPORT_FAILED_TITLE, officialFailureSummary(reported));
    else if (reported.needsNotification || (!automatic && boolEnv(env.NOTIFY_SUCCESS, false))) notify(ctx, REPORT_TITLE, officialUpdateSummary(reported) || '防火墙检查完成');
    return result();
  } catch (error) {
    state = { ...state, ok: false, error: redactError(error, env), uiNotice: '操作未完成' };
    if (!automatic && boolEnv(env.NOTIFY_FAILURE, true)) notify(ctx, REPORT_FAILED_TITLE, state.error);
    return result();
  }
}

function reportLockBypass(ctx) {
  return retiredAction(ctx) || ['recent', 'settings', 'save-common'].includes(localChannelAction(ctx));
}

async function unavailableReportResult(ctx, status) {
  const busy = status === 'busy';
  const message = busy ? '已有另一项上报或状态检查正在进行，本次未重复执行。' : '暂时无法读取本机上报状态，请稍后刷新。';
  let previous = null;
  let deviceId = '';
  let env = ctx?.env || {};
  try {
    previous = sanitizedStoredState(await storageGet(ctx, STORAGE_KEY));
    if (shouldReturnWidget(ctx)) {
      deviceId = '';
      const config = await storedReportConfig(ctx);
      env = effectiveReportEnv(config.exists ? config.values : {}, ctx?.env || {});
      env = officialNetworkEnv(env, networkInfo(ctx));
    }
  } catch (_) {
    // Storage errors must still produce a valid widget without exposing raw errors.
  }
  if (!shouldReturnWidget(ctx)) return { ...(previous || {}), ok: false, status, error: message };
  let panel;
  if (busy && previous) {
    panel = widgetFromState({ ...previous, uiNotice: '正在上报 · 显示上次结果' }, ctx, deviceId, env);
  } else {
    panel = widgetPanel(REPORT_TITLE, [
      busy ? '正在上报，请稍后刷新。' : message,
      busy ? '另一项上报完成前，本次不重复发送。' : '本次未发起网络请求。',
    ], busy, ctx);
  }
  panel.refreshAfter = new Date(Date.now() + 60 * 1000).toISOString();
  return panel;
}

async function runEgernReportWithLock(ctx) {
  if (reportLockBypass(ctx)) return runEgernReportUnlocked(ctx);
  const mode = isStatusRun(ctx) || isWidgetRun(ctx)
    ? 'status'
    : isManualRun(ctx)
      ? 'manual'
      : 'scheduled';
  let lock;
  try {
    lock = await acquireReportLock(ctx, mode, officialNowMs());
  } catch (_) {
    return unavailableReportResult(ctx, 'lock-error');
  }
  if (!lock) return unavailableReportResult(ctx, 'busy');
  try {
    return await runEgernReportUnlocked(ctx);
  } finally {
    try {
      await releaseReportLock(ctx, lock);
    } catch (error) {
      logMessage(ctx, 'error', '释放上报锁失败', redactError(error, ctx?.env || {}));
    }
  }
}

export default async function(ctx) {
  try {
    return await runEgernReportWithLock(ctx);
  } catch (error) {
    if (!shouldReturnWidget(ctx)) throw error;
    // Local save/clear operations can fail before the report error handler runs.
    // Do not expose storage errors, which may contain previously saved secrets.
    return widgetPanel(REPORT_TITLE, [
      '本次操作未完成。',
      '本机存储暂时不可用，请稍后重试。',
      '可运行“PO0 防火墙 · 查看配置”核对结果。',
    ], false, ctx);
  }
}
