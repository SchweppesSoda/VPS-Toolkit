const STORAGE_KEY = 'po0-ssh-ip-report:last';
const ERROR_STORAGE_KEY = 'po0-ssh-ip-report:last-error';
const OFFICIAL_STORAGE_KEY = 'po0-ssh-ip-report:official:v1';
const IP_CHECK_INDEX_KEY = 'po0-ssh-ip-report:ip-check-index';
const DEVICE_ID_KEY = 'po0-ssh-ip-report:device-id';
const CONFIG_STORAGE_KEY = 'po0-ssh-ip-report:config:v1';
const CONFIG_STORAGE_VERSION = 1;
const DEVICE_ID_FALLBACK = 'egern';
const OFFICIAL_FIREWALL_API_BASE = 'https://124.221.69.228/api/firewall';
const DEFAULT_OFFICIAL_INTERVAL_SECONDS = 600;
const OFFICIAL_FIREWALL_MAX_TOKENS = 16;
const REPORT_LOCK_KEY = 'po0-ssh-ip-report:run-lock:v1';
const REPORT_LOCK_TTL_MS = 120000;
const DEFAULT_TTL_SECONDS = 43200;
const DEFAULT_AUTO_REPORT_INTERVAL_SECONDS = 600;
const MIN_AUTO_REPORT_INTERVAL_SECONDS = 60;
const MAX_AUTO_REPORT_INTERVAL_SECONDS = 86400;
const DEFAULT_CELLULAR_CIDR_PREFIX = 24;
const REPORT_TITLE = 'PO0 防火墙上报';
const REPORT_FAILED_TITLE = 'PO0 防火墙上报失败';
const PERSISTED_ENV_KEYS = [
  'PO0_HOST',
  'PO0_PORT',
  'PO0_USER',
  'PO0_PASSWORD',
  'PO0_PRIVATE_KEY',
  'PO0_PASSPHRASE',
  'PO0_SCRIPT',
  'SSH_REPORT_SOURCE',
  'SSH_REPORT_TOKEN',
  'PO0_FIREWALL_TOKENS',
  'PO0_FIREWALL_NAMES',
  'WORKER_AUTO_ENABLED',
  'OFFICIAL_AUTO_ENABLED',
  'OFFICIAL_INTERVAL_SECONDS',
  'WORKER_TIMER_ENABLED',
  'OFFICIAL_TIMER_ENABLED',
  'REPORT_IDENTITY',
  'TTL_SECONDS',
  'AUTO_REPORT_INTERVAL_SECONDS',
  'CELLULAR_CIDR_PREFIX',
  'SKIP_WIFI_SSIDS',
  'SSH_REPORT_TARGETS',
  'IP_CHECK_URL',
  'IP_CHECK_URLS',
  'POLICY',
  'NOTIFY_SUCCESS',
  'NOTIFY_FAILURE',
];
const OFFICIAL_CONFIG_KEYS = ['PO0_FIREWALL_TOKENS', 'PO0_FIREWALL_NAMES', 'OFFICIAL_AUTO_ENABLED', 'OFFICIAL_INTERVAL_SECONDS', 'OFFICIAL_TIMER_ENABLED'];
const WORKER_CONFIG_KEYS = ['PO0_HOST', 'PO0_PORT', 'PO0_USER', 'PO0_PASSWORD', 'PO0_PRIVATE_KEY', 'PO0_PASSPHRASE', 'PO0_SCRIPT', 'SSH_REPORT_SOURCE', 'SSH_REPORT_TOKEN', 'REPORT_IDENTITY', 'TTL_SECONDS', 'AUTO_REPORT_INTERVAL_SECONDS', 'CELLULAR_CIDR_PREFIX', 'SSH_REPORT_TARGETS', 'WORKER_AUTO_ENABLED', 'WORKER_TIMER_ENABLED'];
const MODULE_DEFAULT_ENV_VALUES = {
  PO0_PORT: '22',
  PO0_USER: 'root',
  PO0_SCRIPT: '/root/nftables-relay-manager.sh',
  SSH_REPORT_SOURCE: 'egern',
  REPORT_IDENTITY: 'egern',
  TTL_SECONDS: '43200',
  AUTO_REPORT_INTERVAL_SECONDS: '600',
  CELLULAR_CIDR_PREFIX: '24',
  IP_CHECK_URL: 'https://ip9.com.cn/get',
  POLICY: 'DIRECT',
  NOTIFY_SUCCESS: 'false',
  NOTIFY_FAILURE: 'true',
};

function required(env, key) {
  const value = String(env[key] || '').trim();
  if (!value) throw new Error(`${key} is required`);
  return value;
}

function shQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function wrapText(value, width) {
  const chunks = [];
  const text = String(value || '');
  for (let index = 0; index < text.length; index += width) {
    chunks.push(text.slice(index, index + width));
  }
  return chunks;
}

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

function redactError(error, env = {}, channels = {}, targets = []) {
  const secrets = [];
  const add = (value) => {
    const text = String(value ?? '').trim();
    if (text) secrets.push(text);
  };

  for (const key of [
    'PO0_FIREWALL_TOKENS',
    'SSH_REPORT_TOKEN',
    'SSH_REPORT_TARGETS',
    'PO0_PASSWORD',
    'PO0_PRIVATE_KEY',
    'PO0_PASSPHRASE',
  ]) {
    add(env?.[key]);
  }
  for (const item of channels?.officialTokens || []) add(item?.token);
  const targetList = Array.isArray(targets) ? targets : [targets];
  for (const target of targetList) {
    add(target?.token);
    add(target?.password);
    add(target?.privateKey);
    add(target?.passphrase);
  }

  return redactSensitiveText(error?.message || String(error || ''), secrets);
}

function normalizeSshPrivateKey(value) {
  let key = String(value || '').trim();
  if (!key) return '';

  key = key
    .replace(/\\r\\n/g, '\n')
    .replace(/\\n/g, '\n')
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .trim();

  const oneLine = key.replace(/\n+/g, ' ').trim();
  const match = oneLine.match(/(-----BEGIN ([A-Z0-9 ]*PRIVATE KEY)-----)\s*([\s\S]*?)\s*(-----END \2-----)/);
  if (!match) return key;

  const body = match[3].replace(/\s+/g, '');
  if (!body) return `${match[1]}\n${match[4]}\n`;
  return `${match[1]}\n${wrapText(body, 64).join('\n')}\n${match[4]}\n`;
}

function isPublicIPv4(ip) {
  const m = String(ip || '').trim().match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (!m) return false;
  const o = m.slice(1).map(Number);
  if (o.some((n) => n < 0 || n > 255)) return false;
  if (o[0] === 0 || o[0] === 10 || o[0] === 127) return false;
  if (o[0] === 100 && o[1] >= 64 && o[1] <= 127) return false;
  if (o[0] === 169 && o[1] === 254) return false;
  if (o[0] === 172 && o[1] >= 16 && o[1] <= 31) return false;
  if (o[0] === 192 && o[1] === 168) return false;
  if (o[0] === 198 && o[1] >= 18 && o[1] <= 19) return false;
  if (o[0] >= 224) return false;
  return true;
}

function extractIPv4FromText(text) {
  const seen = new Set();
  const ips = [];
  const matches = String(text || '').matchAll(/\b(\d{1,3}(?:\.\d{1,3}){3})\b/g);
  for (const match of matches) {
    const ip = match[1];
    if (isPublicIPv4(ip) && !seen.has(ip)) {
      seen.add(ip);
      ips.push(ip);
    }
  }
  return ips;
}

function defaultIpCheckUrls(env) {
  return [
    env.IP_CHECK_URL || 'https://ip9.com.cn/get',
    'https://mail.163.com/fgw/mailsrv-ipdetail/detail',
    'https://api.live.bilibili.com/client/v1/Ip/getInfoNew',
    'https://ipservice.ws.126.net/locate/api/getLocByIp',
    'https://r.inews.qq.com/api/ip2city?otype=json',
    'https://data.video.iqiyi.com/v.f4v',
    'https://ip.apps.cntv.cn/whereis?client=json',
    'https://myip.ipip.net/json',
  ].filter(Boolean);
}

async function responseText(resp) {
  if (typeof resp.text === 'function') return await resp.text();
  if (typeof resp.body === 'string') return resp.body;
  if (typeof resp.data === 'string') return resp.data;
  return JSON.stringify(resp.body || resp.data || '');
}

async function detectCurrentIPv4(ctx, url, policy) {
  const resp = await ctx.http.get(url, { timeout: 10000, policy });
  if (resp.status < 200 || resp.status >= 300) {
    throw new Error(`公网 IPv4 探测失败：HTTP ${resp.status}`);
  }

  let data = null;
  try {
    data = await resp.json();
  } catch (_) {
    data = null;
  }

  if (data && typeof data === 'object') {
    const fields = [data.ip, data.origin, data.query, data.address, data.IPv4, data.ipv4];
    for (const field of fields) {
      const ips = extractIPv4FromText(field);
      if (ips.length > 0) return { ip: ips[0], ipProfile: extractIpProfile(data) };
    }
    const ips = extractIPv4FromText(JSON.stringify(data));
    if (ips.length > 0) return { ip: ips[0], ipProfile: extractIpProfile(data) };
  }

  const text = await responseText(resp);
  const ips = extractIPv4FromText(text);
  if (ips.length === 0) {
    throw new Error(`未从 ${url} 提取到公网 IPv4`);
  }
  return { ip: ips[0], ipProfile: extractIpProfile(text) };
}

async function detectCurrentIPv4WithFallback(ctx, env, policy) {
  const urls = String(env.IP_CHECK_URLS || '')
    .split(',')
    .map((url) => url.trim())
    .filter(Boolean);
  if (urls.length === 0) {
    urls.push(...defaultIpCheckUrls(env));
  }
  const start = await storageIndex(ctx, IP_CHECK_INDEX_KEY, urls.length);
  const errors = [];
  for (let i = 0; i < urls.length; i += 1) {
    const index = (start + i) % urls.length;
    const url = urls[index];
    try {
      const result = await detectCurrentIPv4(ctx, url, policy);
      await storageSet(ctx, IP_CHECK_INDEX_KEY, String((index + 1) % urls.length));
      return result;
    } catch (error) {
      errors.push(`${url}: ${error?.message || error}`);
    }
  }
  await storageSet(ctx, IP_CHECK_INDEX_KEY, String((start + 1) % urls.length));
  throw new Error(`所有公网 IPv4 探测地址均失败：${errors.join('; ')}`);
}

function normalizeIpProfile(value) {
  if (!value || typeof value !== 'object') return { location: '', isp: '' };
  return {
    location: String(value.location || '').trim(),
    isp: String(value.isp || value.org || '').trim(),
  };
}

function compactParts(parts) {
  const seen = new Set();
  return (parts || [])
    .map((part) => String(part || '').trim())
    .filter((part) => part && !/^unknown$/i.test(part))
    .filter((part) => {
      const key = part.toLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
}

function firstValue(...values) {
  for (const value of values) {
    const text = String(value || '').trim();
    if (text && !/^unknown$/i.test(text)) return text;
  }
  return '';
}

function extractIpProfileFromObject(data) {
  if (!data || typeof data !== 'object') return { location: '', isp: '' };
  const candidates = [data, data.data, data.result].filter((item) => item && typeof item === 'object');
  for (const item of candidates) {
    if (Array.isArray(item.location)) {
      const locationParts = compactParts(item.location.slice(0, 4));
      const isp = firstValue(item.location[4], item.isp, item.org, item.company, item.operator);
      if (locationParts.length || isp) return { location: locationParts.join(' '), isp };
    }

    const locationParts = compactParts([
      item.country,
      item.prov,
      item.province,
      item.regionName,
      item.city,
      item.county,
      item.district,
    ]);
    const isp = firstValue(item.isp, item.org, item.company, item.operator);
    if (locationParts.length || isp) return { location: locationParts.join(' '), isp };
  }
  return { location: '', isp: '' };
}

function extractIpProfileFromText(text) {
  const value = String(text || '');
  const iqiyi = value.match(/"t"\s*:\s*"([^"|]+)\|([^"-]+)(?:-[0-9.]+)?"/);
  if (iqiyi) {
    return {
      location: iqiyi[2].replace(/_/g, ' ').trim(),
      isp: iqiyi[1].trim(),
    };
  }
  return { location: '', isp: '' };
}

function extractIpProfile(value) {
  if (value && typeof value === 'object') {
    const profile = normalizeIpProfile(extractIpProfileFromObject(value));
    if (profile.location || profile.isp) return profile;
    return normalizeIpProfile(extractIpProfileFromText(JSON.stringify(value)));
  }
  return normalizeIpProfile(extractIpProfileFromText(value));
}

function trimDisplayText(value, maxLength = 18) {
  const text = String(value || '').trim();
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength - 1)}...`;
}

async function fetchIpProfile(ctx, ip, policy) {
  if (!isPublicIPv4(ip)) return { location: '', isp: '' };
  try {
    const fields = 'status,message,country,regionName,city,isp,org,query';
    const url = `http://ip-api.com/json/${encodeURIComponent(ip)}?lang=zh-CN&fields=${fields}`;
    const resp = await ctx.http.get(url, { timeout: 5000, policy });
    if (resp.status < 200 || resp.status >= 300) return { location: '', isp: '' };
    let data = null;
    try {
      data = await resp.json();
    } catch (_) {
      const text = await responseText(resp);
      data = JSON.parse(text);
    }
    if (!data || data.status === 'fail') return { location: '', isp: '' };
    const location = [data.country, data.regionName, data.city]
      .map((part) => String(part || '').trim())
      .filter(Boolean)
      .join(' ');
    const isp = String(data.isp || data.org || '').trim();
    return {
      location,
      isp,
    };
  } catch (_) {
    return { location: '', isp: '' };
  }
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
  const item = String(value ?? '').trim();
  if (!item || /[\r\n]/.test(item)) {
    throw new Error('PO0 官方防火墙 token 配置包含空项或换行。');
  }

  let token = item;
  let slot = null;
  const at = item.indexOf('@');
  if (at >= 0) {
    if (at !== item.lastIndexOf('@')) {
      throw new Error('PO0 官方防火墙 token 配置无效：槽位只能写 @0 到 @4。');
    }
    token = item.slice(0, at);
    const slotText = item.slice(at + 1);
    if (!/^[0-4]$/.test(slotText)) {
      throw new Error('PO0 官方防火墙 token 配置无效：槽位只能写 @0 到 @4。');
    }
    slot = Number(slotText);
  }

  if (!/^pgnfw_[A-Za-z0-9._~-]{1,240}$/.test(token)) {
    throw new Error('PO0 官方防火墙 token 配置无效：请使用 pgnfw_...。');
  }
  return { token, slot };
}

function parseOfficialTokens(raw) {
  const value = String(raw ?? '').trim();
  if (!value) return [];

  const seen = new Set();
  const tokens = value.split(/[,;，；\s]+/).filter(Boolean).map((item) => parseOfficialTokenItem(item));
  for (const item of tokens) {
    // A token identifies one official account; slot hints are not separate accounts.
    const key = item.token;
    if (seen.has(key)) {
      throw new Error('PO0 官方防火墙 token 列表包含重复项。');
    }
    seen.add(key);
  }
  if (tokens.length > OFFICIAL_FIREWALL_MAX_TOKENS) {
    throw new Error(`PO0 官方防火墙 token 数量超过上限（最多 ${OFFICIAL_FIREWALL_MAX_TOKENS} 个）。`);
  }
  return tokens;
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
    throw new Error('官方防火墙返回数据无效。');
  }
  if (data.enabled !== true) {
    throw new Error('官方防火墙当前未启用。');
  }
  const currentIp = officialCidr24(data.currentIp);
  if (!currentIp) {
    throw new Error('官方防火墙未返回有效当前出口 IPv4。');
  }
  const limit = data.limit;
  if (!Number.isInteger(limit) || limit < 1 || limit > 5) {
    throw new Error('官方防火墙返回的名额无效。');
  }
  if (!Array.isArray(data.whitelist) || data.whitelist.length > limit || data.whitelist.length > 5) {
    throw new Error('官方防火墙返回的白名单无效。');
  }

  const seenSlots = new Set();
  const whitelist = data.whitelist.map((entry) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      throw new Error('官方防火墙返回的白名单无效。');
    }
    const ip = officialCidr24(entry.ip);
    if (!ip) throw new Error('官方防火墙返回的白名单 IP 无效。');

    let slot = null;
    if (entry.slot !== undefined && entry.slot !== null && entry.slot !== '') {
      if (!Number.isInteger(entry.slot) || entry.slot < 0 || entry.slot > 4) {
        throw new Error('官方防火墙返回的槽位无效。');
      }
      if (seenSlots.has(entry.slot)) {
        throw new Error('官方防火墙返回了重复槽位。');
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

async function officialPayloadFromResponse(response) {
  const status = Number(response?.status);
  if (!Number.isInteger(status) || status < 200 || status >= 300) {
    const suffix = Number.isInteger(status) ? `（HTTP ${status}）` : '';
    throw new Error(`官方防火墙请求失败${suffix}。`);
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
    throw new Error('官方防火墙返回数据无效。');
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
    throw new Error('Egern HTTP 能力不可用。');
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
  } catch (_) {
    throw new Error('官方防火墙网络请求失败。');
  }
  return await officialPayloadFromResponse(response);
}

function officialSafeError(error) {
  const text = String(error?.message || '');
  if (text === '官方防火墙网络请求失败。' || text === 'Egern HTTP 能力不可用。') return text;
  const http = text.match(/^官方防火墙请求失败（HTTP (\d{3})）。$/);
  if (http) return `官方防火墙请求失败（HTTP ${http[1]}）。`;
  if (/^官方防火墙(?:当前未启用|未返回有效当前出口 IPv4|返回数据无效|返回的名额无效|返回的白名单无效|返回的槽位无效|返回了重复槽位|加白后未确认当前出口)。$/.test(text)) return text;
  if (/^PO0 官方防火墙 token (?:配置包含空项或换行|配置无效：槽位只能写 @0 到 @4|配置无效：请使用 pgnfw_\.\.\.|列表包含重复项|数量超过上限（最多 16 个）)。$/.test(text)) return text;
  return '官方防火墙请求失败。';
}

function normalizeDeviceId(value) {
  const id = String(value || '').trim();
  if (!id) return '';
  if (!/^[A-Za-z0-9._-]{1,64}$/.test(id)) {
    throw new Error('设备 ID 只能包含英文、数字、点号、下划线和短横线，长度 1-64。');
  }
  return id;
}

function deviceDisplayName(deviceId) {
  return deviceId || '未设置';
}

function expandDevicePlaceholder(value, deviceId) {
  const text = String(value || '');
  if (!text.includes('{device}')) return text;
  return text.replace(/\{device\}/g, deviceId || DEVICE_ID_FALLBACK);
}

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function scriptLabel(ctx) {
  return [
    ctx?.name,
    ctx?.script?.name,
    ctx?.script?.type,
    ctx?.trigger,
    ctx?.type,
    ctx?.executionType,
  ].filter(Boolean).join(' ');
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
  return /官方防火墙.*状态|official firewall status/i.test(scriptLabel(ctx));
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
  if (!value) return 'never';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit', hour12: false });
}

function ttlRemaining(expiresAt) {
  if (!expiresAt) return '未知';
  const ms = new Date(expiresAt).getTime() - Date.now();
  if (!Number.isFinite(ms)) return '未知';
  if (ms <= 0) return 'expired';
  const minutes = Math.floor(ms / 60000);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return `${hours}h ${rest}m`;
}

function formatDurationSeconds(seconds) {
  const value = Number(seconds);
  if (!Number.isFinite(value) || value <= 0) return '未知';
  if (value < 60) return `${Math.floor(value)}s`;
  const minutes = Math.floor(value / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest > 0 ? `${hours}h ${rest}m` : `${hours}h`;
}

const WIDGET_COLORS = {
  background: '#111318',
  text: '#F4F7FB',
  heading: '#C9D7EA',
  dim: '#8E8E93',
  line: '#2A2D34',
  blue: '#0A84FF',
  green: '#30D158',
  red: '#FF453A',
  yellow: '#FFD60A',
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
    padding: family === 'large' ? 14 : 10,
    widgetGap: family === 'large' ? 6 : 5,
    titleSize: family === 'small' ? 14 : 15,
    bodySize: family === 'medium' ? 13 : 14,
    captionSize: 11,
    cardGap: family === 'large' ? 5 : 3,
  };
}

function widgetText(text, size = 12, color = WIDGET_COLORS.text, weight = 'regular') {
  return { ...textNode(redactSensitiveText(String(text)), size, weight, color), minScale: 0.9 };
}

function widgetRow(children, gap = 5) {
  return { type: 'stack', direction: 'row', alignItems: 'center', gap, children };
}

function widgetPanel(title, content, ok, ctx) {
  const lines = (Array.isArray(content) ? content : String(content || '').split('\n'))
    .map(line => String(line || '').trim()).filter(Boolean);
  const metrics = widgetMetrics(ctx);
  const maxLines = !ctx?.widgetFamily ? lines.length : widgetFamily(ctx) === 'small' ? 4 : widgetFamily(ctx) === 'large' ? 12 : 7;
  return {
    type: 'widget', padding: metrics.padding, gap: metrics.widgetGap,
    backgroundColor: WIDGET_COLORS.background,
    refreshAfter: new Date(Date.now() + 600000).toISOString(),
    children: [
      widgetRow([iconNode(ok ? 'checkmark.shield.fill' : 'exclamationmark.triangle.fill', ok ? WIDGET_COLORS.green : WIDGET_COLORS.red, 15), widgetText(title, metrics.titleSize, WIDGET_COLORS.text, 'semibold')]),
      ...lines.slice(0, maxLines).map(line => ({ ...widgetText(line, metrics.bodySize), maxLines: 2 })),
    ],
  };
}

function targetName(target) {
  const host = target.host || 'PO0';
  const port = target.port ? `:${target.port}` : '';
  return `${target.sourceId || 'egern'}@${host}${port}`;
}

function officialStatusText(entry) {
  if (entry?.status === 'hit') return '当前出口已命中';
  if (entry?.status === 'updated') return '已更新当前出口';
  if (entry?.status === 'missing') return '当前出口未加白（只读）';
  if (entry?.status === 'error') return entry.error || '检查失败';
  return '未检查';
}

function officialDisplaySlot(slot) {
  return Number.isInteger(slot) && slot >= 0 && slot <= 4 ? slot + 1 : null;
}

function officialWhitelistText(entry) {
  const rows = Array.isArray(entry?.whitelist) ? entry.whitelist : [];
  return rows.length ? rows.map(row => `${row.ip} #${officialDisplaySlot(row.slot) || '自动'}`).join('，') : '空';
}

function widgetTargets(state, env, deviceId) {
  const previous = Array.isArray(state?.targets) ? state.targets : [];
  if (!workerConfigRequested(env)) return [];
  try {
    return parseTargets(env, deviceId).map(target => ({
      ...target,
      ...previous.find(item => item.sourceId === target.sourceId && item.host === target.host && Number(item.port || 22) === target.port),
      // Configuration supplies the current display name and effective TTL, even before a new report.
      identity: target.identity, ttlSeconds: target.ttlSeconds,
    }));
  } catch (_) { return previous; }
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
    }));
  } catch (_) { return previous.map((entry, index) => ({ ...entry, name: officialAccountName(displayEnv, index) })); }
}

function widgetAutoState(configured, enabled, ssidMatched) {
  if (!configured) return { text: '未配置', icon: 'circle.dashed', color: WIDGET_COLORS.dim };
  if (!enabled) return { text: '自动停用', icon: 'pause.circle.fill', color: WIDGET_COLORS.yellow };
  if (ssidMatched) return { text: 'SSID跳过', icon: 'wifi.slash', color: WIDGET_COLORS.blue };
  return { text: '自动开启', icon: 'clock.arrow.circlepath', color: WIDGET_COLORS.green };
}

function widgetLane(title, auto, entries, official, ctx, env) {
  const metrics = widgetMetrics(ctx);
  const family = widgetFamily(ctx);
  const limit = family === 'small' ? 1 : family === 'large' ? 3 : 2;
  const shown = entries.slice(0, limit);
  const children = [widgetRow([
    widgetText(title, metrics.bodySize, WIDGET_COLORS.heading, 'semibold'), spacerNode(),
    iconNode(auto.icon, auto.color, 11), widgetText(auto.text, 11, auto.color),
  ], 3)];
  shown.forEach(entry => {
    const name = official ? entry.name : entry.sourceId || entry.host;
    const success = official ? entry.status === 'hit' || entry.status === 'updated' : entry.ok === true;
    const failed = official ? entry.status === 'error' : entry.ok === false;
    const result = official ? success ? '已加白' : entry.status === 'missing' ? '未加白' : failed ? '失败' : '待检查'
      : success ? '成功' : failed ? '失败' : '待上报';
    const color = failed ? WIDGET_COLORS.red : success ? WIDGET_COLORS.green : WIDGET_COLORS.dim;
    const suffix = entries.length > limit && entry === shown[shown.length - 1] ? ` +${entries.length - limit}` : '';
    children.push(widgetRow([
      { ...widgetText((name || '目标') + suffix, metrics.bodySize, WIDGET_COLORS.text, 'medium'), flex: 1 },
      ...(family === 'large' && official ? [widgetText('#' + (officialDisplaySlot(entry.fixedSlot) || '自动') + ' · ' + (entry.used ?? '?') + '/' + (entry.limit ?? 5), 11, WIDGET_COLORS.dim)] : []),
      widgetText(result, 12, color),
    ]));
  });
  if (!shown.length && family !== 'small') children.push(widgetText(auto.text === '未配置' ? '尚未设置目标' : '等待首次结果', metrics.bodySize, WIDGET_COLORS.dim));
  if (family !== 'small') {
    const first = shown[0];
    const fixed = officialDisplaySlot(first?.fixedSlot);
    const detail = entries.length > 1 || family === 'large'
      ? `${entries.length} 个${official ? '账号 · 检查 10分钟' : '目标 · 周期 ' + formatDurationSeconds(autoReportIntervalSeconds(env))}`
      : official ? (first ? `固定槽位 ${fixed ? '#' + fixed : '自动'} · 名额 ${first.used ?? '?'}/${first.limit ?? 5}` : '检查周期 10 分钟')
      : `自动周期 ${formatDurationSeconds(autoReportIntervalSeconds(env))}`;
    children.push(widgetText(detail, 11, WIDGET_COLORS.dim));
  }
  return { type: 'stack', direction: 'column', alignItems: 'start', gap: metrics.cardGap, flex: family === 'medium' ? 1 : 0, children };
}

function officialReadOnlyWidget(state, ctx, env) {
  const metrics = widgetMetrics(ctx);
  const entries = widgetOfficialEntries(state, env, ctx?.env);
  const lines = ['本次只查询，不新增白名单。'];
  for (const entry of entries) {
    lines.push(entry.name + ' · ' + officialStatusText(entry));
    lines.push(`出口 ${entry.currentIp || '未知'} · 固定槽位 ${officialDisplaySlot(entry.fixedSlot) ? '#' + officialDisplaySlot(entry.fixedSlot) : '自动'}`);
    lines.push(`白名单 ${officialWhitelistText(entry)} · 名额 ${entry.used ?? '?'}/${entry.limit ?? 5}`);
  }
  if (!entries.length) lines.push(state?.error || '官方防火墙尚无结果。');
  return {
    type: 'widget', padding: metrics.padding, gap: 5, backgroundColor: WIDGET_COLORS.background,
    children: [widgetText('官方防火墙 · 只读状态', 14, WIDGET_COLORS.text, 'semibold'), ...lines.map(line => ({ ...widgetText(line, 12), maxLines: 2 }))],
  };
}

function widgetFromState(state, ctx, deviceId = '', env = ctx?.env || {}) {
  if (isOfficialStatusRun(ctx)) return officialReadOnlyWidget(state, ctx, env);
  const family = widgetFamily(ctx);
  const metrics = widgetMetrics(ctx);
  const network = ctx?.device ? networkInfo(ctx) : normalizeNetworkInfo(state?.network);
  const ssid = currentWifiSsidFromNetwork(ctx, network);
  const ssidMatched = Boolean(ssid && normalizeSsidSkipList(env.SKIP_WIFI_SSIDS).includes(ssid));
  const targets = widgetTargets(state, env, deviceId);
  const entries = widgetOfficialEntries(state, env, ctx?.env);
  const workerAuto = widgetAutoState(workerConfigRequested(env), boolEnv(env.WORKER_AUTO_ENABLED, true), ssidMatched);
  const officialAuto = widgetAutoState(officialTokensConfigured(env), boolEnv(env.OFFICIAL_AUTO_ENABLED, true), ssidMatched);
  const worker = widgetLane('自建', workerAuto, targets, false, ctx, env);
  const official = widgetLane('官方', officialAuto, entries, true, ctx, env);
  const lastTime = state?.at || state?.official?.lastSuccessAt || state?.checkedAt;
  const ip = state?.ip || state?.official?.currentIp?.replace(/\/\d+$/, '') || '暂无出口结果';
  const small = family === 'small';
  const networkText = ssid || network.value || '';
  const note = state?.uiNotice || (state?.error ? '上报未完成 · ' + redactSensitiveText(state.error) : state?.skipped && state?.skipType === 'wifi-ssid'
    ? '本次 SSID 跳过 · 保留上次结果'
    : state?.skipped ? '本次无需续报 · 保留上次结果'
    : shouldReturnWidget(ctx) ? '本次强制上报 · 自动开关保持不变' : '最近上报结果');
  const children = [
    widgetRow([widgetText(small ? 'PO0 防火墙' : REPORT_TITLE, metrics.titleSize, WIDGET_COLORS.text, 'semibold'), spacerNode(), widgetText(lastTime ? formatTime(lastTime) : '未上报', 11, WIDGET_COLORS.dim)]),
    widgetRow([{ ...widgetText(ip, metrics.bodySize), flex: 1 }, ...(!small && networkText ? [widgetText(networkText, 11, WIDGET_COLORS.dim)] : [])]),
  ];
  if (family === 'medium') children.push(widgetRow([worker, official], 14));
  else children.push(worker, official);
  if (family === 'large') {
    const profile = normalizeIpProfile(state?.ipProfile);
    const details = [deviceId || state?.deviceId, profile.location, profile.isp].filter(Boolean).join(' · ');
    if (details) children.push(widgetText(details, 12, WIDGET_COLORS.dim));
  }
  if (!small) children.push(widgetText(note, 11, WIDGET_COLORS.dim));
  else if (state?.uiNotice) children[0].children[2] = widgetText('上报中', 11, WIDGET_COLORS.yellow);
  return {
    type: 'widget', padding: metrics.padding, gap: metrics.widgetGap,
    backgroundColor: WIDGET_COLORS.background,
    refreshAfter: new Date(Date.now() + 600000).toISOString(), children,
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
  if (!isAutomaticReportRun(ctx)) return { skip: false };
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
    await storage.set(key, value);
    return true;
  }
  if (typeof storage.setItem === 'function') {
    await storage.setItem(key, value);
    return true;
  }
  if (typeof storage.write === 'function') {
    await storage.write(key, value);
    return true;
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

async function storedDeviceId(ctx) {
  const raw = await storageGet(ctx, DEVICE_ID_KEY);
  try {
    return normalizeDeviceId(raw);
  } catch (_) {
    return '';
  }
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

function reportConfigSaveCandidate(storedValues, runtimeEnv) {
  const candidate = { ...(storedValues || {}) };
  const runtimeValues = persistableEnvValues(runtimeEnv);
  for (const [key, value] of Object.entries(runtimeValues)) {
    const schemaDefault = MODULE_DEFAULT_ENV_VALUES[key];
    const hasDifferentStoredValue = String(candidate[key] || '').trim()
      && schemaDefault === value
      && candidate[key] !== value;
    if (hasDifferentStoredValue) continue;
    candidate[key] = value;
  }
  return candidate;
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
      throw new Error('本机 PO0 上报配置已损坏；请运行“清除本机全部 PO0 上报配置”后重新保存。');
    }
  }

  if (
    !parsed
    || typeof parsed !== 'object'
    || parsed.version !== CONFIG_STORAGE_VERSION
    || !parsed.values
    || typeof parsed.values !== 'object'
  ) {
    throw new Error('本机 PO0 上报配置版本无效；请运行“清除本机全部 PO0 上报配置”后重新保存。');
  }

  const values = persistableEnvValues(parsed.values);
  if (Object.keys(values).length === 0) {
    throw new Error('本机 PO0 上报配置为空；请运行“清除本机全部 PO0 上报配置”后重新保存。');
  }
  return {
    exists: true,
    values,
    savedAt: String(parsed.savedAt || ''),
  };
}

async function saveReportConfig(ctx, env) {
  const values = persistableEnvValues(env);
  const savedAt = new Date().toISOString();
  const saved = await storageSet(ctx, CONFIG_STORAGE_KEY, JSON.stringify({
    version: CONFIG_STORAGE_VERSION,
    savedAt,
    values,
  }));
  if (!saved) {
    throw new Error('当前 Egern 脚本环境不支持本机 storage，无法保存 PO0 上报配置。');
  }
  return { values, savedAt };
}

async function storageIndex(ctx, key, length) {
  if (!Number.isFinite(length) || length <= 0) return 0;
  const raw = await storageGet(ctx, key);
  const index = Number.parseInt(String(raw ?? ''), 10);
  if (!Number.isFinite(index) || index < 0) return 0;
  return index % length;
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

function targetSignature(target) {
  return [
    target.sourceId || '',
    target.host || '',
    String(target.port || ''),
    target.identity || '',
    String(target.ttlSeconds || ''),
  ].join('|');
}

function targetSignatures(targets) {
  return (targets || []).map(targetSignature).sort().join('\n');
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

function targetConfigSignature(target) {
  return [
    target.sourceId || '',
    target.host || '',
    String(target.port || ''),
    target.username || '',
    target.script || '',
    target.identity || '',
    String(target.ttlSeconds || ''),
    String(target.cidrPrefix || 32),
    shortHash(target.token || ''),
  ].join('|');
}

function targetConfigSignatures(targets) {
  return (targets || []).map(targetConfigSignature).sort().join('\n');
}

function sanitizedTargetStatus(target, skipped = false) {
  const clean = {
    sourceId: target?.sourceId || '',
    host: target?.host || '',
    port: target?.port || '',
    identity: target?.identity || '',
    ttlSeconds: target?.ttlSeconds || '',
  };
  if (target?.ok !== undefined) clean.ok = Boolean(target.ok);
  if (target?.cidrPrefix !== undefined) clean.cidrPrefix = target.cidrPrefix;
  if (target?.reportedCidr) clean.reportedCidr = target.reportedCidr;
  if (target?.expiresAt) clean.expiresAt = target.expiresAt;
  if (target?.error) clean.error = redactSensitiveText(target.error, [target?.token]);
  if (skipped || target?.skipped) clean.skipped = true;
  return clean;
}

function sanitizedStoredState(raw) {
  const state = parseStoredState(raw);
  if (!state || typeof state !== 'object') return null;
  const clean = {};
  for (const key of [
    'ok',
    'sourceId',
    'ip',
    'reportedCidr',
    'cidrPrefix',
    'ipProfile',
    'po0Host',
    'identity',
    'network',
    'at',
    'checkedAt',
    'deviceId',
    'targetCount',
    'successCount',
    'failureCount',
    'targetConfigSignature',
    'official',
    'expiresAt',
    'skipped',
    'skipType',
    'skipReason',
  ]) {
    if (state[key] !== undefined) {
      clean[key] = key === 'official'
        ? sanitizeOfficialState(state[key])
        : typeof state[key] === 'string' ? redactSensitiveText(state[key]) : state[key];
    }
  }
  if (Array.isArray(state.targets)) {
    clean.targets = state.targets.map((target) => sanitizedTargetStatus(target));
  }
  return clean;
}

async function buildWifiSsidSkippedState(ctx, targets, network, deviceId, decision) {
  const now = new Date().toISOString();
  const previous = sanitizedStoredState(await storageGet(ctx, STORAGE_KEY));
  const currentTargets = (targets || []).map((target) => sanitizedTargetStatus(target, true));
  const previousHasSuccess = previous?.ok && (previous.ip || previous.reportedCidr || previous.targets?.length);
  const base = previousHasSuccess ? previous : {
    ok: true,
    sourceId: (targets || []).map((target) => target.sourceId).join(','),
    po0Host: (targets || []).map((target) => target.host).join(','),
    identity: (targets || []).map((target) => target.identity).filter(Boolean).join(','),
    network,
    deviceId,
    targetCount: targets.length,
    successCount: 0,
    failureCount: 0,
    targets: currentTargets,
  };
  return {
    ...base,
    ok: true,
    skipped: true,
    skipType: 'wifi-ssid',
    checkedAt: now,
    skipReason: `当前 Wi-Fi SSID "${decision.ssid}" 命中跳过列表，本次未探测公网 IP，未上传 PO0。`,
    network,
    deviceId,
    targetConfigSignature: targetConfigSignatures(targets),
    targetCount: base.targetCount || targets.length,
    targets: previousHasSuccess && Array.isArray(base.targets) && base.targets.length > 0 ? base.targets : currentTargets,
  };
}

function clampInteger(value, fallback, min, max) {
  if (value === undefined || value === null || String(value).trim() === '') return fallback;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  const integer = Math.floor(parsed);
  if (integer < min) return min;
  if (integer > max) return max;
  return integer;
}

function autoReportIntervalSeconds(env) {
  return clampInteger(
    env?.AUTO_REPORT_INTERVAL_SECONDS,
    DEFAULT_AUTO_REPORT_INTERVAL_SECONDS,
    MIN_AUTO_REPORT_INTERVAL_SECONDS,
    MAX_AUTO_REPORT_INTERVAL_SECONDS,
  );
}

function normalizeCidrPrefix(value, fallback = 32) {
  const text = String(value ?? '').trim();
  const parsed = text ? Number.parseInt(text, 10) : fallback;
  if (parsed === 24 || parsed === 32) return parsed;
  return fallback === 24 ? 24 : 32;
}

function reportCidrPrefixForNetwork(env, network) {
  if (network?.kind === 'cellular') {
    return normalizeCidrPrefix(env?.CELLULAR_CIDR_PREFIX, DEFAULT_CELLULAR_CIDR_PREFIX);
  }
  return 32;
}

function cidrForIPv4(ip, prefix) {
  const parts = String(ip || '').trim().split('.').map((part) => Number.parseInt(part, 10));
  if (parts.length !== 4 || parts.some((part) => !Number.isFinite(part) || part < 0 || part > 255)) {
    throw new Error(`invalid IPv4 for CIDR: ${ip}`);
  }
  const normalizedPrefix = normalizeCidrPrefix(prefix, 32);
  if (normalizedPrefix === 24) return `${parts[0]}.${parts[1]}.${parts[2]}.0/24`;
  return `${parts[0]}.${parts[1]}.${parts[2]}.${parts[3]}/32`;
}

function stateReportedCidr(state) {
  if (state?.reportedCidr) return String(state.reportedCidr);
  if (state?.ip) {
    try {
      return cidrForIPv4(state.ip, state?.cidrPrefix || 32);
    } catch (_) {
      return String(state.ip);
    }
  }
  return '';
}

function attachReportCidr(targets, cidrPrefix, reportedCidr) {
  return (targets || []).map((target) => ({
    ...target,
    cidrPrefix,
    reportedCidr,
  }));
}

function minTargetTtlSeconds(targets) {
  const ttls = (targets || [])
    .map((target) => Number(target?.ttlSeconds))
    .filter((ttl) => Number.isFinite(ttl) && ttl > 0);
  if (!ttls.length) return DEFAULT_TTL_SECONDS;
  return Math.max(60, Math.min(...ttls));
}

function effectiveAutoRefreshAfterSeconds(env, targets) {
  const configured = autoReportIntervalSeconds(env);
  const ttlSafeRefreshAfter = Math.max(0, minTargetTtlSeconds(targets) - 600);
  if (ttlSafeRefreshAfter <= 0) return 0;
  return Math.min(configured, ttlSafeRefreshAfter);
}

async function shouldSkipUnchangedAutoReport(ctx, env, targets, ip, reportedCidr) {
  if (isManualRun(ctx) || isWidgetRun(ctx) || isStatusRun(ctx) || isNetworkChangeRun(ctx)) return { skip: false };

  const previous = parseStoredState(await storageGet(ctx, STORAGE_KEY));
  if (!previous || !previous.ok || stateReportedCidr(previous) !== reportedCidr) return { skip: false };

  const currentConfigSignature = targetConfigSignatures(targets);
  if (previous.targetConfigSignature) {
    if (previous.targetConfigSignature !== currentConfigSignature) return { skip: false };
  } else if (targetSignatures(previous.targets || []) !== targetSignatures(targets)) {
    return { skip: false };
  }

  const lastSuccessAt = new Date(previous.at || '').getTime();
  if (!Number.isFinite(lastSuccessAt)) return { skip: false };

  const ageSeconds = Math.floor((Date.now() - lastSuccessAt) / 1000);
  const refreshAfter = effectiveAutoRefreshAfterSeconds(env, targets);
  if (refreshAfter <= 0) return { skip: false, ageSeconds, refreshAfter };
  if (ageSeconds < 0 || ageSeconds >= refreshAfter) return { skip: false, ageSeconds, refreshAfter };

  return {
    skip: true,
    previous,
    ageSeconds,
    refreshAfter,
    currentConfigSignature,
    previousIp: previous.ip || '',
  };
}

function sanitizeOfficialEntry(entry = {}) {
  const clean = {
    name: String(entry.name || ''),
    accountKey: /^[0-9a-f]{1,8}$/.test(String(entry.accountKey || '')) ? String(entry.accountKey) : '',
    ordinal: Number.isInteger(entry.ordinal) ? entry.ordinal : 0,
    slot: Number.isInteger(entry.slot) ? entry.slot : null,
    fixedSlot: Number.isInteger(entry.fixedSlot) ? entry.fixedSlot : null,
    status: String(entry.status || 'error'),
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
function officialIntervalSeconds(env) {
  const value = Number(env?.OFFICIAL_INTERVAL_SECONDS ?? DEFAULT_OFFICIAL_INTERVAL_SECONDS);
  if (!Number.isInteger(value) || value < 60 || value > 86400) throw new Error('官方定时周期必须为 60..86400 秒');
  return value;
}
function officialIsDue(ctx, state, env = {}) {
  if (!isAutomaticReportRun(ctx) || isNetworkChangeRun(ctx)) return true;
  if (!boolEnv(env.OFFICIAL_TIMER_ENABLED, true)) return false;
  const last = Date.parse(String(state?.lastAttemptAt || ''));
  if (!Number.isFinite(last)) return true;
  const age = officialNowMs() - last;
  return age < 0 || age >= officialIntervalSeconds(env) * 1000;
}

function officialStateFromEntries(entries, mode, now, previous, skipped = false) {
  const cleanEntries = entries.map(sanitizeOfficialEntry);
  const failures = cleanEntries.filter((entry) => entry.status === 'error').length;
  const successes = cleanEntries.length - failures;
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
  const previous = await storedOfficialState(ctx);
  let items;
  try {
    items = parseOfficialTokens(env?.PO0_FIREWALL_TOKENS);
  } catch (error) {
    return officialConfigErrorState(error, mode, previous);
  }
  if (items.length === 0) return { active: false, ok: true, state: previous, skipped: false, needsNotification: false };

  if (mode === 'report' && !officialIsDue(ctx, previous, env)) {
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
      entries: [],
    }));
  }

  const runOfficialAccount = async (item, index) => {
    const entry = {
      accountKey: shortHash(item.token),
      name: officialAccountName(env, index),
      ordinal: index + 1,
      slot: item.slot,
      fixedSlot: item.slot,
      status: 'error',
      currentIp: '',
      used: 0,
      limit: 0,
      currentInWhitelist: false,
      whitelist: [],
    };
    try {
      const status = await officialDirectRequest(ctx, item, 'get');
      entry.currentIp = status.currentIp;
      entry.whitelist = status.whitelist;
      entry.used = status.used;
      entry.limit = status.limit;
      entry.currentInWhitelist = status.whitelist.some((row) => row.ip === status.currentIp
        && (item.slot === null || row.slot === item.slot));
      if (entry.currentInWhitelist) {
        entry.status = 'hit';
      } else if (mode === 'status') {
        entry.status = 'missing';
      } else {
        const updated = await officialDirectRequest(ctx, item, 'post');
        const updatedHit = updated.whitelist.some((row) => row.ip === updated.currentIp
          && (item.slot === null || row.slot === item.slot));
        if (!updatedHit) throw new Error('官方防火墙加白后未确认当前出口。');
        entry.status = 'updated';
        entry.currentIp = updated.currentIp;
        entry.whitelist = updated.whitelist;
        entry.used = updated.used;
        entry.limit = updated.limit;
        entry.currentInWhitelist = true;
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
  // configured order for state/UI output. Worker SSH starts only afterwards.
  const results = await Promise.all(items.map((item, index) => runOfficialAccount(item, index)));
  for (const result of results) {
    entries.push(result.entry);
    if (result.entry.status === 'error') {
      try { logMessage(ctx, 'error', '官方防火墙账号 #' + result.entry.ordinal + ' 失败', result.entry.error); } catch (_) {}
    }
  }
  needsNotification = results.some((result) => result.needsNotification);

  const state = officialStateFromEntries(entries, mode, now, previous);
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

function notifyLong(ctx, title, body) {
  const text = redactSensitiveText(body).trim();
  if (!text) return;
  const chunks = wrapText(text, 180).slice(0, 4);
  if (chunks.length <= 1) {
    notify(ctx, title, text);
    return;
  }
  chunks.forEach((chunk, index) => {
    notify(ctx, `${title} ${index + 1}/${chunks.length}`, chunk);
  });
}

function oneLineOutput(value) {
  return String(value || '')
    .replace(/\r/g, '\n')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .join(' | ');
}

function commandResultError(result) {
  const stderr = oneLineOutput(result?.stderr);
  const stdout = oneLineOutput(result?.stdout);
  const code = result?.code ?? result?.exitCode ?? 'unknown';
  return stderr || stdout || `exit ${code}`;
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

function htmlResponse(ctx, status, title, lines) {
  const bodyLines = (Array.isArray(lines) ? lines : [lines])
    .filter((line) => line !== undefined && line !== null)
    .map((line) => `<p>${escapeHtml(redactSensitiveText(line))}</p>`)
    .join('\n');
  const body = `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;margin:24px;line-height:1.5;color:#111}
code{background:#f1f3f5;border-radius:4px;padding:2px 4px}
</style>
</head>
<body>
<h1>${escapeHtml(title)}</h1>
${bodyLines}
</body>
</html>`;
  const response = {
    status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
    },
    body,
  };
  if (typeof ctx?.respond === 'function') return ctx.respond(response);
  return response;
}

function parseRequestUrl(ctx) {
  const raw = String(ctx?.request?.url || '');
  if (!raw) return null;
  try {
    return new URL(raw);
  } catch (_) {
    return null;
  }
}

function isLegacyDeviceHttpRun(ctx) {
  return /PO0 防火墙本机设备 ID/.test(scriptLabel(ctx));
}

async function handleDeviceHttpRequest(ctx) {
  const url = parseRequestUrl(ctx);
  if (!url || url.protocol !== 'http:' || url.hostname !== 'po0-egern.local') return null;

  if (url.pathname === '/set-device') {
    try {
      const deviceId = normalizeDeviceId(url.searchParams.get('id') || '');
      await storageSet(ctx, DEVICE_ID_KEY, deviceId);
      notify(ctx, 'PO0 Egern Device', `设备 ID 已设置为 ${deviceId}`);
      return htmlResponse(ctx, 200, 'PO0 Egern Device', [
        `设备 ID 已设置为: ${deviceId}`,
        '以后自动上报会用这个本机 ID 展开 {device}。',
        '写错时重新打开 /set-device?id=新ID 即可覆盖。',
      ]);
    } catch (error) {
      return htmlResponse(ctx, 400, 'PO0 Egern Device', [
        redactError(error, ctx?.env || {}),
        '示例: http://po0-egern.local/set-device?id=iphone15pm',
      ]);
    }
  }

  if (url.pathname === '/clear-device') {
    await storageDelete(ctx, DEVICE_ID_KEY);
    notify(ctx, 'PO0 Egern Device', '设备 ID 已清除');
    return htmlResponse(ctx, 200, 'PO0 Egern Device', [
      '设备 ID 已清除。',
      `未设置时，上报里的 {device} 会回退为 ${DEVICE_ID_FALLBACK}。`,
    ]);
  }

  if (url.pathname === '/' || url.pathname === '/device') {
    const deviceId = await storedDeviceId(ctx);
    return htmlResponse(ctx, 200, 'PO0 Egern Device', [
      `当前设备 ID: ${deviceDisplayName(deviceId)}`,
      '设置示例: http://po0-egern.local/set-device?id=iphone15pm',
      '清除: http://po0-egern.local/clear-device',
      '设备 ID 不显示在模块设置表单里；请在 PO0 防火墙上报状态里确认。',
    ]);
  }

  return htmlResponse(ctx, 404, 'PO0 Egern Device', [
    '未知路径。',
    '可用路径: /device, /set-device?id=iphone15pm, /clear-device',
  ]);
}

async function handleDeviceSetupScript(ctx, env) {
  try {
    const deviceId = normalizeDeviceId(env.DEVICE_ID_SETUP || env.LOCAL_DEVICE_ID || '');
    await storageSet(ctx, DEVICE_ID_KEY, deviceId);
    notify(ctx, 'PO0 Egern Device', `设备 ID 已保存为 ${deviceId}`);
    return widgetPanel(REPORT_TITLE, [
      `设备: ${deviceId}`,
      '已保存到本机 storage。',
      '后续上报会用它展开 {device}。',
    ], true, ctx);
  } catch (error) {
    return widgetPanel(REPORT_TITLE, [
      '设备: 未设置',
      redactError(error, env),
      '请在 DEVICE_ID_SETUP 填入如 iphone15pm 后再运行本脚本。',
    ], false, ctx);
  }
}

async function handleDeviceClearScript(ctx) {
  await storageDelete(ctx, DEVICE_ID_KEY);
  notify(ctx, 'PO0 Egern Device', '设备 ID 已清除');
  return widgetPanel(REPORT_TITLE, [
    '设备: 未设置',
    '本机设备 ID 已清除。',
    `后续 {device} 会回退为 ${DEVICE_ID_FALLBACK}。`,
  ], true, ctx);
}

function targetValue(target, env, keys, fallback = '') {
  for (const source of [target, env]) {
    for (const key of keys) {
      const value = source?.[key];
      if (String(value ?? '').trim()) return String(value).trim();
    }
  }
  return fallback;
}

function normalizeTarget(env, input, index, deviceId = '') {
  const target = input || {};
  const sourceId = expandDevicePlaceholder(targetValue(target, env, ['sourceId', 'SSH_REPORT_SOURCE', 'source', 'sourceId', 'name'], 'egern'), deviceId);
  const host = targetValue(target, env, ['host', 'PO0_HOST', 'po0Host']);
  const port = Number(targetValue(target, env, ['port', 'PO0_PORT'], '22'));
  const username = targetValue(target, env, ['user', 'username', 'PO0_USER'], 'root');
  const script = targetValue(target, env, ['script', 'PO0_SCRIPT', 'po0Script'], '/root/nftables-relay-manager.sh');
  const token = targetValue(target, env, ['token', 'SSH_REPORT_TOKEN', 'reportToken']);
  const identity = expandDevicePlaceholder(targetValue(target, env, ['identity', 'REPORT_IDENTITY'], 'egern'), deviceId);
  const ttl = Number(targetValue(target, env, ['ttl', 'ttlSeconds', 'TTL_SECONDS'], String(DEFAULT_TTL_SECONDS)));

  if (!host) throw new Error(`PO0 目标 #${index + 1} 缺少主机`);
  if (!token) throw new Error(`PO0 目标 #${index + 1} 缺少 token`);

  return {
    sourceId,
    host,
    port: Number.isFinite(port) && port > 0 ? port : 22,
    username,
    script,
    token,
    identity,
    ttlSeconds: Number.isFinite(ttl) && ttl > 0 ? ttl : DEFAULT_TTL_SECONDS,
    password: targetValue(target, env, ['password', 'PO0_PASSWORD']),
    privateKey: targetValue(target, env, ['privateKey', 'PO0_PRIVATE_KEY']),
    passphrase: targetValue(target, env, ['passphrase', 'PO0_PASSPHRASE']),
  };
}

function parseTargetLine(env, line, index, deviceId = '') {
  const parts = String(line || '').split('|').map((part) => part.trim());
  return normalizeTarget(env, {
    SSH_REPORT_SOURCE: parts[0],
    PO0_HOST: parts[1],
    PO0_PORT: parts[2],
    PO0_USER: parts[3],
    PO0_SCRIPT: parts[4],
    SSH_REPORT_TOKEN: parts[5],
    REPORT_IDENTITY: parts[6],
    TTL_SECONDS: parts[7],
  }, index, deviceId);
}

function splitTargetLines(raw) {
  return String(raw || '')
    .split(/\r?\n|[;,，；]/)
    .flatMap((line) => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) return [];

      const chunks = trimmed.split(/\s+/).filter(Boolean);
      if (chunks.length > 1 && chunks.every((chunk) => chunk.includes('|'))) {
        return chunks;
      }

      return [trimmed];
    });
}

function parseTargets(env, deviceId = '') {
  const raw = String(env.SSH_REPORT_TARGETS || '').trim();
  if (!raw) {
    return [normalizeTarget(env, {}, 0, deviceId)];
  }

  if (raw.startsWith('[')) {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed) || parsed.length === 0) {
      throw new Error('SSH_REPORT_TARGETS JSON 必须是非空数组');
    }
    return parsed.map((target, index) => normalizeTarget(env, target, index, deviceId));
  }

  const lines = splitTargetLines(raw);
  if (lines.length === 0) {
    throw new Error('SSH_REPORT_TARGETS 为空');
  }
  return lines.map((line, index) => parseTargetLine(env, line, index, deviceId));
}

function sshConfig(env, target) {
  const config = {
    host: target.host,
    port: target.port,
    username: target.username,
    timeout: 10000,
  };
  if (String(target.privateKey || '').trim()) {
    config.privateKey = normalizeSshPrivateKey(target.privateKey);
    if (String(target.passphrase || '').trim()) {
      config.passphrase = target.passphrase;
    }
  } else {
    if (!String(target.password || '').trim()) {
      throw new Error(`PO0 目标 ${target.sourceId}@${target.host} 缺少 SSH 密码或私钥`);
    }
    config.password = target.password;
  }
  return config;
}

function validateReportConfig(env, deviceId = '') {
  const targets = parseTargets(env, deviceId);
  for (const target of targets) {
    sshConfig(env, target);
  }
  return targets;
}

function workerConfigRequested(env) {
  const requiredKeys = [
    'PO0_HOST',
    'PO0_PASSWORD',
    'PO0_PRIVATE_KEY',
    'PO0_PASSPHRASE',
    'SSH_REPORT_TOKEN',
    'SSH_REPORT_TARGETS',
  ];
  if (requiredKeys.some((key) => String(env?.[key] ?? '').trim() !== '')) return true;
  return [
    'PO0_PORT',
    'PO0_USER',
    'PO0_SCRIPT',
    'SSH_REPORT_SOURCE',
    'REPORT_IDENTITY',
    'TTL_SECONDS',
  ].some((key) => {
    const value = String(env?.[key] ?? '').trim();
    const schemaDefault = String(MODULE_DEFAULT_ENV_VALUES[key] ?? '').trim();
    return value !== '' && value !== schemaDefault;
  });
}

function validateReportChannels(env, deviceId = '') {
  const officialRequested = officialTokensConfigured(env);
  const workerRequested = workerConfigRequested(env);
  let officialTokens = [];
  let officialError = null;
  let workerTargets = [];
  let workerError = null;

  if (officialRequested) {
    try {
      officialTokens = parseOfficialTokens(env?.PO0_FIREWALL_TOKENS);
    } catch (error) {
      officialError = error;
    }
  }
  if (workerRequested) {
    try {
      workerTargets = validateReportConfig(env, deviceId);
    } catch (error) {
      workerError = error;
    }
  }

  return {
    officialRequested,
    officialTokens,
    officialError,
    workerRequested,
    workerTargets,
    workerError,
    anyRequested: officialRequested || workerRequested,
    anyValid: officialTokens.length > 0 || workerTargets.length > 0,
  };
}

function reportConfigAuthSummary(targets) {
  const keyCount = targets.filter((target) => String(target.privateKey || '').trim()).length;
  const passwordCount = targets.length - keyCount;
  const parts = [];
  if (keyCount > 0) parts.push(`${keyCount} 个私钥认证`);
  if (passwordCount > 0) parts.push(`${passwordCount} 个密码认证`);
  return parts.join('，') || '未识别认证方式';
}

async function handleScopedConfigSaveScript(ctx, runtimeEnv, storedValues, deviceId, officialOnly) {
  const title = officialOnly ? '官方防火墙配置' : '自建防火墙 / 通用设置';
  try {
    let candidate;
    if (officialOnly) {
      const input = String(runtimeEnv.PO0_FIREWALL_TOKENS || '').trim() || String(storedValues?.PO0_FIREWALL_TOKENS || '').trim();
      if (!input) throw new Error('请填写官方 Token；清除请使用独立的清除官方 Token 操作。');
      parseOfficialTokens(input);
      candidate = { ...(storedValues || {}), PO0_FIREWALL_TOKENS: input };
      candidate.PO0_FIREWALL_NAMES = officialNamesForSave(storedValues || {}, runtimeEnv, input);
      if (runtimeEnv.OFFICIAL_AUTO_ENABLED !== undefined) candidate.OFFICIAL_AUTO_ENABLED = String(runtimeEnv.OFFICIAL_AUTO_ENABLED);
      for (const key of ['OFFICIAL_INTERVAL_SECONDS', 'OFFICIAL_TIMER_ENABLED']) {
        if (runtimeEnv[key] !== undefined && String(runtimeEnv[key]).trim()) candidate[key] = String(runtimeEnv[key]);
      }
      officialIntervalSeconds(candidate);
    } else {
      const scopedEnv = { ...runtimeEnv };
      for (const key of OFFICIAL_CONFIG_KEYS) delete scopedEnv[key];
      candidate = reportConfigSaveCandidate(storedValues, scopedEnv);
      const workerEnv = { ...candidate };
      delete workerEnv.PO0_FIREWALL_TOKENS;
      const channels = validateReportChannels(workerEnv, deviceId);
      if (channels.workerError) throw channels.workerError;
      if (!channels.anyValid && !String(candidate.PO0_FIREWALL_TOKENS || '').trim()) {
        throw new Error('请先填写自建防火墙上报目标和 SSH 认证，或单独保存官方防火墙配置。');
      }
    }
    await saveReportConfig(ctx, candidate);
    notify(ctx, 'PO0 Egern Config', title + '已保存');
    return widgetPanel(REPORT_TITLE, [title + '已保存。', ...(officialOnly ? officialSavedNameRows(candidate) : []), '另一通道的已保存参数保持不变；本次只保存，不发起上报。'], true, ctx);
  } catch (error) {
    return widgetPanel(REPORT_TITLE, [title + '未保存。', redactError(error, { ...(storedValues || {}), ...runtimeEnv })], false, ctx);
  }
}

async function handleReportConfigSaveScript(ctx, runtimeEnv, storedValues, deviceId) {
  try {
    const candidate = reportConfigSaveCandidate(storedValues, runtimeEnv);
    if (officialTokensConfigured(candidate)) candidate.PO0_FIREWALL_NAMES = officialNamesForSave(storedValues || {}, runtimeEnv, candidate.PO0_FIREWALL_TOKENS);
    const channels = validateReportChannels(candidate, deviceId);
    if (!channels.anyRequested || !channels.anyValid) {
      throw channels.officialError || channels.workerError || new Error('至少配置一个可用的 PO0 上报通道。');
    }
    if (channels.officialError) throw channels.officialError;
    if (channels.workerError) throw channels.workerError;
    await saveReportConfig(ctx, candidate);
    const summaryParts = [];
    if (channels.workerTargets.length > 0) {
      summaryParts.push(`${channels.workerTargets.length} 个自建防火墙目标，${reportConfigAuthSummary(channels.workerTargets)}`);
    }
    if (channels.officialTokens.length > 0) {
      summaryParts.push(`官方防火墙 ${channels.officialTokens.length} 个账号（内容不显示）`);
    }
    const summary = summaryParts.join('；');
    notify(ctx, 'PO0 Egern Config', `本机上报配置已保存：${summary}`);
    return widgetPanel(REPORT_TITLE, [
      `设备: ${deviceDisplayName(deviceId)}`,
      `已保存: ${summary}`,
      ...officialSavedNameRows(candidate),
      '密码、私钥和 Token 仅写入本机 ctx.storage；运行状态不保存 Token。',
      '后续更换 Egern 配置时无需重新填写。',
    ], true, ctx);
  } catch (error) {
    return widgetPanel(REPORT_TITLE, [
      `设备: ${deviceDisplayName(deviceId)}`,
      '本机上报配置未保存。',
      redactError(error, { ...(storedValues || {}), ...(runtimeEnv || {}) }),
      '请补齐模块环境变量后重新运行本脚本。',
    ], false, ctx);
  }
}

async function handleReportConfigClearScript(ctx) {
  await saveReportConfig(ctx, { WORKER_AUTO_ENABLED: 'false', OFFICIAL_AUTO_ENABLED: 'false' });
  await storageDelete(ctx, STORAGE_KEY);
  await storageDelete(ctx, ERROR_STORAGE_KEY);
  await storageDelete(ctx, OFFICIAL_STORAGE_KEY);
  notify(ctx, 'PO0 Egern Config', '本机上报配置已清除');
  return widgetPanel(REPORT_TITLE, [
    '本机 PO0 上报配置及最近状态已清除。',
    '本机设备 ID 保留不变。',
    '如需恢复，请重新填写模块环境变量并运行“保存本机 PO0 自建防火墙配置”或“保存本机 PO0 官方防火墙配置”。',
  ], true, ctx);
}

async function handleOfficialConfigClearScript(ctx, storedValues) {
  const next = { ...(storedValues || {}) };
  for (const key of OFFICIAL_CONFIG_KEYS) delete next[key];
  next.OFFICIAL_AUTO_ENABLED = 'false';
  if (Object.keys(next).length === 0) {
    await storageDelete(ctx, CONFIG_STORAGE_KEY);
  } else {
    await saveReportConfig(ctx, next);
  }
  await storageDelete(ctx, OFFICIAL_STORAGE_KEY);
  notify(ctx, 'PO0 Egern Config', '本机官方防火墙 token 已清除');
  return widgetPanel(REPORT_TITLE, [
    '本机官方防火墙 token 已清除。',
    '自建防火墙配置和本机设备 ID 保留不变。',
    '如需恢复，请填写 PO0_FIREWALL_TOKENS 后运行“保存本机 PO0 官方防火墙配置”。',
  ], true, ctx);
}

function missingReportConfigState(deviceId, error, env = {}) {
  return {
    ok: false,
    skipped: true,
    skipType: 'missing-config',
    configured: false,
    deviceId,
    error: redactError(error, env) || '本机未保存 PO0 上报配置',
  };
}

function missingReportConfigPanel(ctx, deviceId, error, env = ctx?.env || {}) {
  return widgetPanel(REPORT_TITLE, [
    `设备: ${deviceDisplayName(deviceId)}`,
    '本机尚未保存 PO0 上报配置。',
    redactError(error, env),
    '请填写模块环境变量并运行“保存本机 PO0 自建防火墙配置”或“保存本机 PO0 官方防火墙配置”。',
    '定时和网络变化任务会保持静默，不会反复报错。',
  ], false, ctx);
}

async function reportToPO0(ctx, env, target, ip) {
  const session = await ctx.ssh.connect(sshConfig(env, target));
  try {
    const command = [
      'bash',
      shQuote(target.script),
      '--ssh-ip-report',
      shQuote(target.sourceId),
      shQuote(ip),
      shQuote(target.token),
      shQuote(target.identity),
      shQuote(String(target.ttlSeconds)),
      shQuote(String(target.cidrPrefix || 32)),
    ].join(' ');
    const result = await session.exec(command);
    const code = result.code ?? result.exitCode ?? 0;
    if (code !== 0) {
      throw new Error(`exit ${code}: ${commandResultError(result)}`);
    }
    return oneLineOutput(result.stdout) || `OK ${target.sourceId} ${ip}`;
  } finally {
    await session.close();
  }
}

function officialFailureSummary(result) {
  const entries = Array.isArray(result?.state?.entries) ? result.state.entries : [];
  return entries
    .filter((entry) => entry.status === 'error')
    .map((entry) => {
      const displaySlot = officialDisplaySlot(entry.slot);
      const slot = displaySlot === null ? '' : `（槽位 ${displaySlot}）`;
      return `官方账号 #${entry.ordinal || '?'}${slot}：${entry.error || '官方防火墙请求失败。'}`;
    })
    .join('；');
}

function officialUpdateSummary(result) {
  const entries = Array.isArray(result?.state?.entries) ? result.state.entries : [];
  return entries
    .filter((entry) => entry.status === 'updated')
    .map((entry) => {
      const displaySlot = officialDisplaySlot(entry.slot);
      const slot = displaySlot === null ? '' : `，槽位 ${displaySlot}`;
      return `账号 #${entry.ordinal || '?'}${slot} 当前出口 ${entry.currentIp || '未知'}`;
    })
    .join('；');
}

function parseOfficialNames(value) {
  const raw = String(value || '').trim();
  return raw === '-' ? [] : raw.replace(/\r\n?/g, '\n').split(/[,;，；\n]/).map(name => name.trim());
}

function officialAccountName(env, index) {
  return parseOfficialNames(env.PO0_FIREWALL_NAMES)[index] || ('官方账号 ' + (index + 1));
}

function officialDisplayEnv(env, runtimeEnv) {
  if (!String(runtimeEnv?.PO0_FIREWALL_NAMES || '').trim()) return env;
  try {
    const accounts = parseOfficialTokens(env.PO0_FIREWALL_TOKENS);
    const moduleAccounts = String(runtimeEnv.PO0_FIREWALL_TOKENS || '').trim()
      ? parseOfficialTokens(runtimeEnv.PO0_FIREWALL_TOKENS) : accounts;
    const moduleNames = parseOfficialNames(runtimeEnv.PO0_FIREWALL_NAMES);
    const savedNames = parseOfficialNames(env.PO0_FIREWALL_NAMES);
    // Names are display-only. Match token identities so synced ordering/slots never
    // rename a different local account or replace its saved reporting configuration.
    const names = accounts.map((account, index) => {
      const moduleIndex = moduleAccounts.findIndex(item => item.token === account.token);
      return moduleIndex >= 0 ? moduleNames[moduleIndex] || '' : savedNames[index] || '';
    });
    return { ...env, PO0_FIREWALL_NAMES: names.join(';') };
  } catch (_) { return env; }
}

function officialSavedNameRows(env) {
  return widgetOfficialEntries(null, env).map(entry => '官方目标：' + entry.name + ' · ' + (officialDisplaySlot(entry.fixedSlot) ? '固定槽位 #' + officialDisplaySlot(entry.fixedSlot) : '自动槽位'));
}

function officialNamesForSave(stored, runtime, tokens) {
  if (String(runtime.PO0_FIREWALL_NAMES || '').trim()) {
    return parseOfficialNames(runtime.PO0_FIREWALL_NAMES).join(';');
  }
  const oldTokens = String(stored.PO0_FIREWALL_TOKENS || '').split(/[,;，；\s]+/).filter(Boolean);
  const oldNames = parseOfficialNames(stored.PO0_FIREWALL_NAMES);
  return parseOfficialTokens(tokens).map(item => {
    const index = oldTokens.findIndex(old => old.split('@')[0] === item.token);
    return index < 0 ? '' : oldNames[index] || '';
  }).join(';');
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
  if (/查看本机上报设置/.test(label)) return 'settings';
  return '';
}

async function handleLocalChannelAction(ctx, env, action) {
  const next = { ...env };
  let message = '';
  if (action === 'clear-worker') {
    for (const key of WORKER_CONFIG_KEYS) delete next[key];
    next.WORKER_AUTO_ENABLED = 'false';
    await saveReportConfig(ctx, next);
    await storageDelete(ctx, STORAGE_KEY);
    message = '自建防火墙的本机配置已清除，官方及公共设置保留。';
  } else if (/^(toggle|enable|disable)-/.test(action)) {
    const worker = action.endsWith('-worker');
    const key = worker ? 'WORKER_AUTO_ENABLED' : 'OFFICIAL_AUTO_ENABLED';
    const enabled = action.startsWith('enable-') || (action.startsWith('toggle-') && !boolEnv(next[key], true));
    next[key] = enabled ? 'true' : 'false';
    await saveReportConfig(ctx, next);
    const channel = worker ? '自建防火墙' : '官方防火墙';
    const otherKey = worker ? 'OFFICIAL_AUTO_ENABLED' : 'WORKER_AUTO_ENABLED';
    const otherChannel = worker ? '官方防火墙' : '自建防火墙';
    return widgetPanel(REPORT_TITLE + ' · 自动上报', [
      channel + '自动上报：已' + (enabled ? '启用' : '停用') + '。',
      '只控制定时检查和网络变化触发。' + (action.startsWith('toggle-') ? '旧切换动作每次会反转开关。' : '重复点击不会反转。'),
      '配置保留；手动强制上报和小组件刷新仍可执行。',
      otherChannel + '自动上报保持' + (boolEnv(next[otherKey], true) ? '启用' : '停用') + '；未配置的通道不会上报。',
    ], true, ctx);
  }
  const rows = [message,
    '自建防火墙：' + (workerConfigRequested(next) ? boolEnv(next.WORKER_AUTO_ENABLED, true) ? '自动上报启用' : '自动上报停用（配置保留）' : '未配置'),
    '自建上报周期：' + autoReportIntervalSeconds(next) + ' 秒（不是白名单 TTL）',
    '官方防火墙：' + (officialTokensConfigured(next) ? boolEnv(next.OFFICIAL_AUTO_ENABLED, true) ? '自动上报启用' : '自动上报停用（配置保留）' : '未配置'),
    '官方定时：' + (boolEnv(next.OFFICIAL_TIMER_ENABLED, true) ? officialIntervalSeconds(next) + ' 秒' : '已关闭') + '；网络变化立即检查，TTL 由官方服务管理。',
    ...officialSavedNameRows(officialDisplayEnv(next, ctx?.env)),
    ...widgetTargets(null, next, await storedDeviceId(ctx)).map(target => target.sourceId + ' · 生效 TTL ' + target.ttlSeconds + ' 秒'),
    'SSID 跳过：' + (next.SKIP_WIFI_SSIDS || '未设置') + '；匹配时同时跳过两个自动上报通道。',
    '定时 / 网络变化共用两个通道；手动操作仍沿用原有强制上报规则。',
  ].filter(Boolean);
  if (message) notify(ctx, REPORT_TITLE, message);
  return widgetPanel(REPORT_TITLE + ' · 本机设置', rows, true, ctx);
}

function selectReportChannels(ctx, env, channels) {
  const automatic = isAutomaticReportRun(ctx);
  const label = scriptLabel(ctx);
  const timer = automatic && !isNetworkChangeRun(ctx);
  if ((timer && !boolEnv(env.WORKER_TIMER_ENABLED, true)) || (automatic && !boolEnv(env.WORKER_AUTO_ENABLED, true)) || /仅官方防火墙(?:立即|强制)上报/.test(label)) {
    channels.workerRequested = false; channels.workerTargets = []; channels.workerError = null;
  }
  if ((timer && !boolEnv(env.OFFICIAL_TIMER_ENABLED, true)) || (automatic && !boolEnv(env.OFFICIAL_AUTO_ENABLED, true)) || /仅自建(?: PO0 立即|防火墙强制)上报/.test(label)) {
    channels.officialRequested = false; channels.officialTokens = []; channels.officialError = null;
  }
  channels.anyRequested = channels.workerRequested || channels.officialRequested;
  channels.anyValid = channels.workerTargets.length > 0 || channels.officialTokens.length > 0;
  return channels;
}

async function runEgernReportUnlocked(ctx) {
  const deviceHttpResponse = await handleDeviceHttpRequest(ctx);
  if (deviceHttpResponse) return deviceHttpResponse;
  if (isLegacyDeviceHttpRun(ctx)) {
    if (ctx?.request) return;
    return widgetPanel(REPORT_TITLE, [
      '这是旧版浏览器设备 ID 入口。',
      '查看请运行“查看本机上报设置”。',
      '修改请运行“保存本机设备 ID”或“清除本机设备 ID”。',
      '本次没有发起上报。',
    ], true, ctx);
  }

  const runtimeEnv = ctx.env || {};
  if (isDeviceSetupRun(ctx)) return await handleDeviceSetupScript(ctx, runtimeEnv);
  if (isDeviceClearRun(ctx)) return await handleDeviceClearScript(ctx);
  if (isReportConfigClearRun(ctx)) return await handleReportConfigClearScript(ctx);

  const startedAt = new Date(officialNowMs());
  let deviceId = '';
  let env = runtimeEnv;
  let policy = 'DIRECT';
  let notifySuccess = isManualRun(ctx);
  let notifyFailure = true;
  let channels = {
    officialRequested: false,
    officialTokens: [],
    officialError: null,
    workerRequested: false,
    workerTargets: [],
    workerError: null,
    anyRequested: false,
    anyValid: false,
  };
  let targets = [];
  let officialResult = { active: false, ok: true, state: null, skipped: false, needsNotification: false };
  let ip = '';
  let ipProfile = { location: '', isp: '' };
  let network = normalizeNetworkInfo(null);
  let cidrPrefix = 32;
  let reportedCidr = '';

  try {
    deviceId = await storedDeviceId(ctx);
    const storedConfig = await storedReportConfig(ctx);
    if (isWorkerConfigSaveRun(ctx) || isOfficialConfigSaveRun(ctx)) {
      return await handleScopedConfigSaveScript(ctx, runtimeEnv, storedConfig.values, deviceId, isOfficialConfigSaveRun(ctx));
    }
    if (isReportConfigSaveRun(ctx)) {
      return await handleReportConfigSaveScript(ctx, runtimeEnv, storedConfig.values, deviceId);
    }
    if (storedConfig.exists) {
      env = storedConfig.values;
    }
    if (localChannelAction(ctx)) return await handleLocalChannelAction(ctx, env, localChannelAction(ctx));
    if (isOfficialConfigClearRun(ctx)) {
      return await handleOfficialConfigClearScript(ctx, storedConfig.values);
    }

    channels = validateReportChannels(env, deviceId);
    if (!channels.anyRequested) {
      const configError = channels.workerError || new Error('本机尚未配置 PO0 上报通道。');
      if (isAutomaticReportRun(ctx)) return missingReportConfigState(deviceId, configError, env);
      return missingReportConfigPanel(ctx, deviceId, configError, env);
    }
    if (!channels.anyValid && !channels.officialRequested) {
      const configError = channels.workerError || new Error('本机 PO0 自建防火墙配置无效。');
      if (isAutomaticReportRun(ctx)) return missingReportConfigState(deviceId, configError, env);
      return missingReportConfigPanel(ctx, deviceId, configError, env);
    }
    if (!storedConfig.exists && channels.anyValid && !channels.officialError && !channels.workerError) {
      await saveReportConfig(ctx, env);
    }

    channels = selectReportChannels(ctx, env, channels);
    if (!channels.anyRequested) {
      if (shouldReturnWidget(ctx)) return widgetPanel(REPORT_TITLE, [
        '所选上报通道尚未配置。',
        '请先保存该通道配置，再运行强制上报。',
        '本次没有发起网络请求。',
      ], false, ctx);
      return { ok: true, skipped: true, skipType: 'channels-paused', reason: '本次没有启用的自动上报通道；配置保留。' };
    }
    policy = env.POLICY || 'DIRECT';
    notifySuccess = boolEnv(env.NOTIFY_SUCCESS, false) || isManualRun(ctx);
    notifyFailure = boolEnv(env.NOTIFY_FAILURE, true) || isManualRun(ctx);
    targets = channels.workerTargets;
    network = networkInfo(ctx);
    const wifiSsidSkip = ssidSkipDecision(ctx, env, network);
    if (wifiSsidSkip.skip) {
      const state = await buildWifiSsidSkippedState(ctx, targets, network, deviceId, wifiSsidSkip);
      if (channels.officialRequested) state.official = await storedOfficialState(ctx);
      await storageSet(ctx, STORAGE_KEY, JSON.stringify(state));
      logMessage(ctx, 'info', '跳过本轮上报', state.skipReason);
      return shouldReturnWidget(ctx) ? widgetFromState(state, ctx, deviceId, env) : state;
    }

    if (channels.officialRequested) {
      const officialMode = isOfficialStatusRun(ctx) ? 'status' : 'report';
      try {
        officialResult = channels.officialError
          ? officialConfigErrorState(channels.officialError, officialMode, await storedOfficialState(ctx))
          : await runOfficialFirewall(ctx, env, officialMode);
      } catch (error) {
        officialResult = officialConfigErrorState(error, officialMode, null);
      }
    }

    const workerFailures = [];
    if (channels.workerError) workerFailures.push('自建防火墙配置无效。');

    if (targets.length === 0 || isOfficialStatusRun(ctx)) {
      const officialState = officialResult.state || null;
      const officialIp = officialState?.currentIp || '';
      const state = {
        ok: Boolean(officialResult.ok) && workerFailures.length === 0,
        ip: officialIp.replace(/\/24$/, ''),
        reportedCidr: officialIp,
        cidrPrefix: 24,
        ipProfile,
        network,
        at: startedAt.toISOString(),
        checkedAt: officialState?.checkedAt || startedAt.toISOString(),
        deviceId,
        targetCount: 0,
        successCount: 0,
        failureCount: (officialResult.ok ? 0 : 1) + workerFailures.length,
      };
      if (channels.officialRequested) state.official = officialState;
      const officialError = officialFailureSummary(officialResult);
      const errors = [officialError, ...workerFailures].filter(Boolean);
      if (errors.length > 0) state.error = errors.join('；');
      await storageSet(ctx, STORAGE_KEY, JSON.stringify(state));
      if (!state.ok) {
        await storageSet(ctx, ERROR_STORAGE_KEY, state.error || '官方防火墙上报失败。');
        if (notifyFailure) notifyLong(ctx, REPORT_FAILED_TITLE, state.error || '官方防火墙上报失败。');
      } else if (officialResult.needsNotification) {
        notify(ctx, REPORT_TITLE, `官方防火墙已更新：${officialUpdateSummary(officialResult)}`);
      }
      return shouldReturnWidget(ctx) ? widgetFromState(state, ctx, deviceId, env) : state;
    }

    const detected = await detectCurrentIPv4WithFallback(ctx, env, policy);
    ip = detected.ip;
    ipProfile = normalizeIpProfile(detected.ipProfile);
    if (!ipProfile.location && !ipProfile.isp) {
      ipProfile = await fetchIpProfile(ctx, ip, policy);
    }
    network = networkInfo(ctx);
    cidrPrefix = reportCidrPrefixForNetwork(env, network);
    reportedCidr = cidrForIPv4(ip, cidrPrefix);
    targets = attachReportCidr(targets, cidrPrefix, reportedCidr);
    const skipDecision = await shouldSkipUnchangedAutoReport(ctx, env, targets, ip, reportedCidr);
    if (skipDecision.skip) {
      const previousIpProfile = normalizeIpProfile(skipDecision.previous?.ipProfile);
      if (!ipProfile.location && !ipProfile.isp && (previousIpProfile.location || previousIpProfile.isp)) {
        ipProfile = previousIpProfile;
      }
      const changedInsideCidr = skipDecision.previousIp && skipDecision.previousIp !== ip
        ? `；本次 IP ${ip} 仍在 ${reportedCidr}`
        : '';
      const state = {
        ...skipDecision.previous,
        ip,
        reportedCidr,
        cidrPrefix,
        skipped: true,
        skipType: 'unchanged',
        checkedAt: new Date().toISOString(),
        targetConfigSignature: skipDecision.currentConfigSignature,
        skipReason: `上报 CIDR 未变化${changedInsideCidr}，距离上次成功 ${skipDecision.ageSeconds}s，小于自动刷新间隔 ${skipDecision.refreshAfter}s`,
        network,
        ipProfile,
        deviceId,
      };
      if (channels.officialRequested) state.official = officialResult.state || await storedOfficialState(ctx);
      await storageSet(ctx, STORAGE_KEY, JSON.stringify(state));
      logMessage(ctx, 'info', '跳过 SSH 上报', state.skipReason);
      return state;
    }

    const results = [];
    const failures = [];
    const targetReports = [];

    for (const target of targets) {
      try {
        const output = await reportToPO0(ctx, env, target, ip);
        const report = {
          ok: true,
          sourceId: target.sourceId,
          host: target.host,
          port: target.port,
          identity: target.identity,
          ttlSeconds: target.ttlSeconds,
          cidrPrefix: target.cidrPrefix,
          reportedCidr: target.reportedCidr,
          expiresAt: new Date(startedAt.getTime() + Math.max(60, target.ttlSeconds) * 1000).toISOString(),
          output: redactSensitiveText(String(output || '').trim(), [target.token]),
        };
        results.push(report);
        targetReports.push(report);
      } catch (error) {
        const errorText = redactError(error, env, channels, [target]);
        logMessage(ctx, 'error', `${targetName(target)} 失败`, errorText);
        const report = {
          ok: false,
          sourceId: target.sourceId,
          host: target.host,
          port: target.port,
          cidrPrefix: target.cidrPrefix,
          reportedCidr: target.reportedCidr,
          error: errorText,
        };
        failures.push(report);
        targetReports.push(report);
      }
    }

    if (channels.workerError) {
      failures.push({ error: '自建防火墙配置无效。' });
    }
    const officialError = officialFailureSummary(officialResult);
    const overallFailure = failures.length > 0 || Boolean(officialResult.active && !officialResult.ok);
    const state = {
      ok: !overallFailure,
      sourceId: targets.map((target) => target.sourceId).join(','),
      ip,
      reportedCidr,
      cidrPrefix,
      ipProfile,
      po0Host: targets.map((target) => target.host).join(','),
      identity: targets.map((target) => target.identity).filter(Boolean).join(','),
      network,
      at: startedAt.toISOString(),
      deviceId,
      targetCount: targets.length,
      successCount: results.length,
      failureCount: failures.length + (officialResult.active && !officialResult.ok ? 1 : 0),
      targetConfigSignature: targetConfigSignatures(targets),
      targets: targetReports,
    };
    if (channels.officialRequested) state.official = officialResult.state || await storedOfficialState(ctx);
    const errorParts = [officialError, ...failures.map((failure) => failure.error)].filter(Boolean);
    if (errorParts.length > 0) state.error = errorParts.join('；');
    await storageSet(ctx, STORAGE_KEY, JSON.stringify(state));

    if (overallFailure) {
      const workerErrorSummary = failures
        .filter((failure) => failure.sourceId || failure.host)
        .map((failure) => `${targetName(failure)}: ${failure.error}`)
        .join('; ');
      const errorSummary = [officialError, workerErrorSummary, channels.workerError ? '自建防火墙配置无效。' : '']
        .filter(Boolean)
        .join('；') || '本轮上报未完成。';
      await storageSet(ctx, ERROR_STORAGE_KEY, errorSummary);
      if (notifyFailure) {
        notifyLong(ctx, REPORT_FAILED_TITLE, `${ip || officialResult.state?.currentIp || '当前出口'}：${results.length}/${targets.length} 个自建防火墙目标完成；${errorSummary}`);
      }
      return shouldReturnWidget(ctx) ? widgetFromState(state, ctx, deviceId, env) : state;
    }

    if (officialResult.needsNotification) {
      notify(ctx, REPORT_TITLE, `官方防火墙已更新：${officialUpdateSummary(officialResult)}`);
    }
    if (notifySuccess) {
      notify(ctx, REPORT_TITLE, `${ip}: ${results.length}/${targets.length} 个 PO0 已更新`);
    }
    return shouldReturnWidget(ctx) ? widgetFromState(state, ctx, deviceId, env) : state;
  } catch (error) {
    const errorText = redactError(error, env, channels, targets) || '本轮上报未完成。';
    const state = {
      ok: false,
      sourceId: targets.map((target) => target.sourceId).join(',') || String(env.SSH_REPORT_SOURCE || 'egern').trim() || 'egern',
      po0Host: targets.map((target) => target.host).join(',') || env.PO0_HOST || '',
      ip,
      reportedCidr,
      cidrPrefix,
      ipProfile,
      network,
      at: new Date().toISOString(),
      deviceId,
      targetCount: targets.length,
      successCount: 0,
      failureCount: targets.length || 1,
      error: errorText,
    };
    if (officialResult.active && officialResult.state) state.official = officialResult.state;
    await storageSet(ctx, STORAGE_KEY, JSON.stringify(state));
    await storageSet(ctx, ERROR_STORAGE_KEY, state.error);
    logMessage(ctx, 'error', '运行失败', state.error);
    if (notifyFailure) {
      notifyLong(ctx, REPORT_FAILED_TITLE, state.error);
    }
    if (shouldReturnWidget(ctx)) {
      return widgetFromState(state, ctx, deviceId, env);
    }
    throw new Error(errorText);
  }
}

function reportLockBypass(ctx) {
  const requestUrl = parseRequestUrl(ctx);
  const isDeviceRequest = requestUrl
    && requestUrl.protocol === 'http:'
    && requestUrl.hostname === 'po0-egern.local';
  return Boolean(isDeviceRequest)
    || isLegacyDeviceHttpRun(ctx)
    || isDeviceSetupRun(ctx)
    || isDeviceClearRun(ctx)
    || isReportConfigSaveRun(ctx)
    || isReportConfigClearRun(ctx)
    || isOfficialConfigClearRun(ctx)
    || isWorkerConfigSaveRun(ctx)
    || isOfficialConfigSaveRun(ctx)
    || Boolean(localChannelAction(ctx));
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
      deviceId = await storedDeviceId(ctx);
      const config = await storedReportConfig(ctx);
      if (config.exists) env = config.values;
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
      '可在“查看本机上报设置”核对保存结果。',
    ], false, ctx);
  }
}
