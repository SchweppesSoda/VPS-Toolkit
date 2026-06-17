const STORAGE_KEY = 'po0-ssh-ip-report:last';
const ERROR_STORAGE_KEY = 'po0-ssh-ip-report:last-error';
const IP_CHECK_INDEX_KEY = 'po0-ssh-ip-report:ip-check-index';
const DEVICE_ID_KEY = 'po0-ssh-ip-report:device-id';
const DEVICE_ID_FALLBACK = 'egern';
const REPORT_TITLE = 'PO0 SSH IP 上报';
const REPORT_FAILED_TITLE = 'PO0 SSH IP 上报失败';

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
    'https://exservice.12306.cn/excater/bonree/grip',
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
      if (ips.length > 0) return ips[0];
    }
    const ips = extractIPv4FromText(JSON.stringify(data));
    if (ips.length > 0) return ips[0];
  }

  const text = await responseText(resp);
  const ips = extractIPv4FromText(text);
  if (ips.length === 0) {
    throw new Error(`未从 ${url} 提取到公网 IPv4`);
  }
  return ips[0];
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
      const ip = await detectCurrentIPv4(ctx, url, policy);
      await storageSet(ctx, IP_CHECK_INDEX_KEY, String((index + 1) % urls.length));
      return ip;
    } catch (error) {
      errors.push(`${url}: ${error?.message || error}`);
    }
  }
  await storageSet(ctx, IP_CHECK_INDEX_KEY, String((start + 1) % urls.length));
  throw new Error(`所有公网 IPv4 探测地址均失败：${errors.join('; ')}`);
}

function boolEnv(value, fallback) {
  const raw = String(value || '').trim().toLowerCase();
  if (!raw) return fallback;
  return ['1', 'true', 'yes', 'on'].includes(raw);
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
  return /generic|manual|now|立即|手动/i.test(scriptLabel(ctx));
}

function isWidgetRun(ctx) {
  return Boolean(ctx?.widgetFamily);
}

function isStatusRun(ctx) {
  return /状态|status/i.test(scriptLabel(ctx));
}

function shouldReturnWidget(ctx) {
  return isWidgetRun(ctx) || isStatusRun(ctx);
}

function isDeviceSetupRun(ctx) {
  return /保存本机设备|设置本机设备|save device|set device/i.test(scriptLabel(ctx));
}

function isDeviceClearRun(ctx) {
  return /清除本机设备|clear device/i.test(scriptLabel(ctx));
}

function formatTime(value) {
  if (!value) return 'never';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return date.toLocaleString();
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

const WIDGET_COLORS = {
  background: '#111318',
  text: '#F4F7FB',
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

function rowNode(icon, iconColor, label, value, valueColor = WIDGET_COLORS.text) {
  return {
    type: 'stack',
    direction: 'row',
    alignItems: 'center',
    gap: 5,
    children: [
      iconNode(icon, iconColor, 11),
      textNode(label, 10, 'regular', WIDGET_COLORS.dim),
      spacerNode(),
      textNode(value || '未知', 10, 'medium', valueColor),
    ],
  };
}

function widgetPanel(title, content, ok, ctx) {
  const lines = Array.isArray(content) ? content : String(content || '').split('\n').filter(Boolean);
  const family = String(ctx?.widgetFamily || '').toLowerCase();
  const maxLines = family.includes('large') ? 10 : family.includes('small') ? 4 : 7;
  const shownLines = lines.slice(0, maxLines);
  const accent = ok ? '#34C759' : '#FF453A';

  return {
    type: 'widget',
    padding: 14,
    gap: 7,
    backgroundColor: WIDGET_COLORS.background,
    refreshAfter: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    children: [
      {
        type: 'stack',
        direction: 'row',
        alignItems: 'center',
        gap: 6,
        children: [
          iconNode(ok ? 'checkmark.shield.fill' : 'exclamationmark.triangle.fill', accent, 18),
          textNode(title, 'headline', 'semibold', WIDGET_COLORS.text),
        ],
      },
      ...shownLines.map((line) => textNode(line)),
    ],
  };
}

function shortHost(host) {
  const text = String(host || 'PO0');
  return text.length > 18 ? `${text.slice(0, 17)}...` : text;
}

function targetName(target) {
  const host = target.host || 'PO0';
  const port = target.port ? `:${target.port}` : '';
  return `${target.sourceId || 'egern'}@${host}${port}`;
}

function targetDisplayValue(target) {
  const name = `${target.sourceId || 'egern'}@${shortHost(target.host)}`;
  if (target.ok) return `${name} TTL ${ttlRemaining(target.expiresAt)}`;
  return `${name} 失败: ${target.error || '未知错误'}`;
}

function targetSummaryRows(state, ctx) {
  const targets = Array.isArray(state.targets) ? state.targets : [];
  if (targets.length === 0) {
    if (state.expiresAt) {
      return [rowNode('server.rack', WIDGET_COLORS.green, '目标1', `${state.sourceId || 'egern'} TTL ${ttlRemaining(state.expiresAt)}`)];
    }
    return [];
  }
  const family = String(ctx?.widgetFamily || '').toLowerCase();
  const maxTargets = family.includes('small') ? 1 : 2;
  const rows = targets.slice(0, maxTargets).map((target, index) => {
    const ok = Boolean(target.ok);
    return rowNode(
      ok ? 'server.rack' : 'exclamationmark.triangle.fill',
      ok ? WIDGET_COLORS.green : WIDGET_COLORS.red,
      `目标${index + 1}`,
      targetDisplayValue(target),
      ok ? WIDGET_COLORS.text : WIDGET_COLORS.red,
    );
  });
  if (targets.length > maxTargets && !family.includes('small')) {
    rows.push(rowNode('ellipsis.circle', WIDGET_COLORS.dim, '更多', `还有 ${targets.length - maxTargets} 个目标未显示`, WIDGET_COLORS.dim));
  }
  return rows;
}

function widgetFromState(state, ctx, deviceId = '') {
  const ok = Boolean(state?.ok);
  const family = String(ctx?.widgetFamily || '').toLowerCase();
  const isSmall = family.includes('small');
  const network = normalizeNetworkInfo(state?.network);
  const deviceName = deviceDisplayName(deviceId || state?.deviceId || '');
  const targets = Array.isArray(state?.targets) ? state.targets : [];
  const successCount = state?.successCount ?? targets.filter((target) => target.ok).length;
  const targetCount = state?.targetCount ?? targets.length;
  const statusColor = ok ? WIDGET_COLORS.green : WIDGET_COLORS.red;
  const statusIcon = ok ? 'checkmark.shield.fill' : 'exclamationmark.triangle.fill';
  const statusText = ok ? '已更新' : '上报异常';
  const timeText = formatTime(state?.at || state?.checkedAt);

  if (!state) {
    return widgetPanel(REPORT_TITLE, [`设备: ${deviceName}`, '暂无上报状态。', '点按刷新即可立即上报。'], false, ctx);
  }

  const coreRows = [
    rowNode('globe.asia.australia.fill', WIDGET_COLORS.blue, '公网', state.ip || '未知'),
    rowNode('iphone', WIDGET_COLORS.blue, '设备', deviceName),
    rowNode(ok ? 'checkmark.circle.fill' : 'xmark.circle.fill', statusColor, '目标', `${successCount}/${targetCount || 1} 成功`, statusColor),
  ];
  const networkRows = [
    rowNode(network.icon, WIDGET_COLORS.blue, network.label, network.value),
  ];
  if (network.localIp) networkRows.push(rowNode('iphone', WIDGET_COLORS.blue, '本机', network.localIp));
  if (network.gateway) networkRows.push(rowNode('wifi.router.fill', WIDGET_COLORS.blue, '网关', network.gateway));

  const detailChildren = isSmall ? [
    ...coreRows.slice(0, 2),
    ...networkRows.slice(0, 2),
  ] : [
    {
      type: 'stack',
      direction: 'row',
      gap: 10,
      children: [
        { type: 'stack', direction: 'column', gap: 5, flex: 1, children: coreRows },
        { type: 'stack', width: 0.5, backgroundColor: WIDGET_COLORS.line },
        { type: 'stack', direction: 'column', gap: 5, flex: 1, children: networkRows },
      ],
    },
  ];

  const targetRows = targetSummaryRows(state, ctx);
  if (!ok && targetRows.length === 0) {
    targetRows.push(rowNode('exclamationmark.triangle.fill', WIDGET_COLORS.red, '原因', state.error || '未知错误', WIDGET_COLORS.red));
  }

  return {
    type: 'widget',
    padding: 14,
    gap: 8,
    backgroundColor: WIDGET_COLORS.background,
    refreshAfter: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    children: [
      {
        type: 'stack',
        direction: 'row',
        alignItems: 'center',
        gap: 6,
        children: [
          iconNode(statusIcon, statusColor, 16),
          textNode(REPORT_TITLE, 'headline', 'semibold', WIDGET_COLORS.text),
          spacerNode(),
          textNode(statusText, 10, 'semibold', statusColor),
        ],
      },
      textNode(timeText, 10, 'regular', WIDGET_COLORS.dim),
      ...detailChildren,
      { type: 'stack', height: 0.5, backgroundColor: WIDGET_COLORS.line },
      ...targetRows,
    ],
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

function networkInfo(ctx) {
  const device = ctx?.device || {};
  const runtimeNetwork = (typeof $network !== 'undefined') ? $network : (ctx?.network || {});
  const localIp = runtimeNetwork?.v4?.primaryAddress || device?.ipv4?.address || '';
  const gateway = runtimeNetwork?.v4?.primaryRouter || device?.ipv4?.gateway || '';
  const wifiName = device?.wifi?.ssid || '';
  const carrier = carrierLabel(device?.cellular?.carrier || '');
  const radio = radioLabel(device?.cellular?.radio || '');

  if (wifiName) {
    return {
      label: 'Wi-Fi',
      value: wifiName,
      icon: 'wifi',
      localIp,
      gateway,
    };
  }

  if (radio || carrier) {
    return {
      label: '蜂窝',
      value: [carrier, radio].filter(Boolean).join(' ') || '未知',
      icon: 'antenna.radiowaves.left.and.right',
      localIp,
      gateway,
    };
  }

  return {
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
      label: value.label || '网络',
      value: value.value || '未知',
      icon: value.icon || 'network',
      localIp: value.localIp || '',
      gateway: value.gateway || '',
    };
  }
  return {
    label: '网络',
    value: String(value || '未知'),
    icon: 'network',
    localIp: '',
    gateway: '',
  };
}

async function storageSet(ctx, key, value) {
  const storage = ctx?.storage;
  if (!storage) return;
  if (typeof storage.set === 'function') return await storage.set(key, value);
  if (typeof storage.setItem === 'function') return await storage.setItem(key, value);
  if (typeof storage.write === 'function') return await storage.write(key, value);
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
  if (!storage) return;
  if (typeof storage.delete === 'function') return await storage.delete(key);
  if (typeof storage.remove === 'function') return await storage.remove(key);
  if (typeof storage.removeItem === 'function') return await storage.removeItem(key);
  return await storageSet(ctx, key, '');
}

async function storedDeviceId(ctx) {
  const raw = await storageGet(ctx, DEVICE_ID_KEY);
  try {
    return normalizeDeviceId(raw);
  } catch (_) {
    return '';
  }
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
    shortHash(target.token || ''),
  ].join('|');
}

function targetConfigSignatures(targets) {
  return (targets || []).map(targetConfigSignature).sort().join('\n');
}

function minTargetTtlSeconds(targets) {
  const ttls = (targets || [])
    .map((target) => Number(target.ttlSeconds))
    .filter((ttl) => Number.isFinite(ttl) && ttl > 0);
  if (ttls.length === 0) return 3600;
  return Math.min(...ttls);
}

function automaticRefreshAfterSeconds(targets) {
  const ttl = minTargetTtlSeconds(targets);
  const twoThirdsTtl = Math.floor(ttl * 2 / 3);
  const beforeExpiryMargin = ttl - 10 * 60;
  return Math.max(60, Math.min(twoThirdsTtl, beforeExpiryMargin));
}

async function shouldSkipUnchangedAutoReport(ctx, targets, ip) {
  if (isManualRun(ctx) || isWidgetRun(ctx)) return { skip: false };

  const previous = parseStoredState(await storageGet(ctx, STORAGE_KEY));
  if (!previous || !previous.ok || previous.ip !== ip) return { skip: false };

  const currentConfigSignature = targetConfigSignatures(targets);
  if (previous.targetConfigSignature) {
    if (previous.targetConfigSignature !== currentConfigSignature) return { skip: false };
  } else if (targetSignatures(previous.targets || []) !== targetSignatures(targets)) {
    return { skip: false };
  }

  const lastSuccessAt = new Date(previous.at || '').getTime();
  if (!Number.isFinite(lastSuccessAt)) return { skip: false };

  const refreshAfter = automaticRefreshAfterSeconds(targets);
  const ageSeconds = Math.floor((Date.now() - lastSuccessAt) / 1000);
  if (ageSeconds < 0 || ageSeconds >= refreshAfter) return { skip: false, ageSeconds, refreshAfter };

  return {
    skip: true,
    previous,
    ageSeconds,
    refreshAfter,
    currentConfigSignature,
  };
}

function notify(ctx, title, body) {
  if (!ctx || typeof ctx.notify !== 'function') return;
  ctx.notify({ title, body });
}

function notifyLong(ctx, title, body) {
  const text = String(body || '').trim();
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
  const line = `[${REPORT_TITLE}] ${message}${detail ? `: ${detail}` : ''}`;
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
    .map((line) => `<p>${escapeHtml(line)}</p>`)
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
        error?.message || String(error),
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
      '设备 ID 不显示在模块设置表单里；请在 PO0 SSH 上报状态里确认。',
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
      error?.message || String(error),
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
  for (const key of keys) {
    const value = target?.[key] ?? env?.[key];
    if (String(value || '').trim()) return String(value).trim();
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
  const ttl = Number(targetValue(target, env, ['ttl', 'ttlSeconds', 'TTL_SECONDS'], '3600'));

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
    ttlSeconds: Number.isFinite(ttl) && ttl > 0 ? ttl : 3600,
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

export default async function(ctx) {
  const deviceHttpResponse = await handleDeviceHttpRequest(ctx);
  if (deviceHttpResponse) return deviceHttpResponse;

  const env = ctx.env || {};
  if (isDeviceSetupRun(ctx)) return await handleDeviceSetupScript(ctx, env);
  if (isDeviceClearRun(ctx)) return await handleDeviceClearScript(ctx);

  const policy = env.POLICY || 'DIRECT';
  const notifySuccess = boolEnv(env.NOTIFY_SUCCESS, false) || isManualRun(ctx);
  const notifyFailure = boolEnv(env.NOTIFY_FAILURE, true) || isManualRun(ctx);
  const startedAt = new Date();
  const deviceId = await storedDeviceId(ctx);
  let targets = [];
  let ip = '';

  try {
    targets = parseTargets(env, deviceId);
    ip = await detectCurrentIPv4WithFallback(ctx, env, policy);
    const skipDecision = await shouldSkipUnchangedAutoReport(ctx, targets, ip);
    if (skipDecision.skip) {
      const state = {
        ...skipDecision.previous,
        skipped: true,
        checkedAt: new Date().toISOString(),
        targetConfigSignature: skipDecision.currentConfigSignature,
        skipReason: `IP 未变化，距离上次成功 ${skipDecision.ageSeconds}s，小于自动刷新间隔 ${skipDecision.refreshAfter}s`,
        network: networkInfo(ctx),
        deviceId,
      };
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
          expiresAt: new Date(startedAt.getTime() + Math.max(60, target.ttlSeconds) * 1000).toISOString(),
          output: String(output || '').trim(),
        };
        results.push(report);
        targetReports.push(report);
      } catch (error) {
        const errorText = error?.message || String(error);
        logMessage(ctx, 'error', `${targetName(target)} 失败`, errorText);
        const report = {
          ok: false,
          sourceId: target.sourceId,
          host: target.host,
          port: target.port,
          error: errorText,
        };
        failures.push(report);
        targetReports.push(report);
      }
    }

    const state = {
      ok: failures.length === 0,
      sourceId: targets.map((target) => target.sourceId).join(','),
      ip,
      po0Host: targets.map((target) => target.host).join(','),
      identity: targets.map((target) => target.identity).filter(Boolean).join(','),
      network: networkInfo(ctx),
      at: startedAt.toISOString(),
      deviceId,
      targetCount: targets.length,
      successCount: results.length,
      failureCount: failures.length,
      targetConfigSignature: targetConfigSignatures(targets),
      targets: targetReports,
    };
    await storageSet(ctx, STORAGE_KEY, JSON.stringify(state));

    if (failures.length > 0) {
      const errorSummary = failures.map((failure) => `${targetName(failure)}: ${failure.error}`).join('; ');
      await storageSet(ctx, ERROR_STORAGE_KEY, errorSummary);
      if (notifyFailure) {
        notifyLong(ctx, REPORT_FAILED_TITLE, `${ip}: ${results.length}/${targets.length} 成功；${errorSummary}`);
      }
      return shouldReturnWidget(ctx) ? widgetFromState(state, ctx, deviceId) : state;
    }

    if (notifySuccess) {
      notify(ctx, REPORT_TITLE, `${ip}: ${results.length}/${targets.length} 个 PO0 已更新`);
    }
    return shouldReturnWidget(ctx) ? widgetFromState(state, ctx, deviceId) : state;
  } catch (error) {
    const state = {
      ok: false,
      sourceId: targets.map((target) => target.sourceId).join(',') || String(env.SSH_REPORT_SOURCE || 'egern').trim() || 'egern',
      po0Host: targets.map((target) => target.host).join(',') || env.PO0_HOST || '',
      ip,
      network: networkInfo(ctx),
      at: new Date().toISOString(),
      deviceId,
      targetCount: targets.length,
      successCount: 0,
      failureCount: targets.length || 1,
      error: error?.message || String(error),
    };
    await storageSet(ctx, STORAGE_KEY, JSON.stringify(state));
    await storageSet(ctx, ERROR_STORAGE_KEY, state.error);
    logMessage(ctx, 'error', '运行失败', state.error);
    if (notifyFailure) {
      notifyLong(ctx, REPORT_FAILED_TITLE, state.error);
    }
    if (shouldReturnWidget(ctx)) {
      return widgetFromState(state, ctx, deviceId);
    }
    throw error;
  }
}
