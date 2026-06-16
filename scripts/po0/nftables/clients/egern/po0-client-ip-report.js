const STORAGE_KEY = 'po0-client-ip-report:last';
const IP_CHECK_INDEX_KEY = 'po0-client-ip-report:ip-check-index';

function required(env, key) {
  const value = String(env[key] || '').trim();
  if (!value) throw new Error(`${key} is required`);
  return value;
}

function shQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
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
    throw new Error(`IP check failed: HTTP ${resp.status}`);
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
    throw new Error(`No public IPv4 found from ${url}`);
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
  throw new Error(`All IP checks failed: ${errors.join('; ')}`);
}

function boolEnv(value, fallback) {
  const raw = String(value || '').trim().toLowerCase();
  if (!raw) return fallback;
  return ['1', 'true', 'yes', 'on'].includes(raw);
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

function networkLabel(ctx) {
  const network = ctx?.network || ctx?.networks || ctx?.environment?.network;
  if (!network) return 'unknown';
  if (typeof network === 'string') return network;
  try {
    return JSON.stringify(network);
  } catch (_) {
    return 'unknown';
  }
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

async function storageIndex(ctx, key, length) {
  if (!Number.isFinite(length) || length <= 0) return 0;
  const raw = await storageGet(ctx, key);
  const index = Number.parseInt(String(raw ?? ''), 10);
  if (!Number.isFinite(index) || index < 0) return 0;
  return index % length;
}

function notify(ctx, title, body) {
  if (!ctx || typeof ctx.notify !== 'function') return;
  ctx.notify({ title, body });
}

function targetValue(target, env, keys, fallback = '') {
  for (const key of keys) {
    const value = target?.[key] ?? env?.[key];
    if (String(value || '').trim()) return String(value).trim();
  }
  return fallback;
}

function normalizeTarget(env, input, index) {
  const target = input || {};
  const reportName = targetValue(target, env, ['reportName', 'REPORT_NAME', 'source', 'sourceId', 'name'], 'egern');
  const host = targetValue(target, env, ['host', 'PO0_HOST', 'po0Host']);
  const port = Number(targetValue(target, env, ['port', 'PO0_PORT'], '22'));
  const username = targetValue(target, env, ['user', 'username', 'PO0_USER'], 'root');
  const script = targetValue(target, env, ['script', 'PO0_SCRIPT', 'po0Script'], '/root/nftables-relay-manager.sh');
  const token = targetValue(target, env, ['token', 'REPORT_TOKEN', 'reportToken']);
  const identity = targetValue(target, env, ['identity', 'REPORT_IDENTITY'], 'egern');
  const ttl = Number(targetValue(target, env, ['ttl', 'ttlSeconds', 'TTL_SECONDS'], '3600'));

  if (!host) throw new Error(`PO0 target #${index + 1} missing host`);
  if (!token) throw new Error(`PO0 target #${index + 1} missing token`);

  return {
    reportName,
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

function parseTargetLine(env, line, index) {
  const parts = String(line || '').split('|').map((part) => part.trim());
  return normalizeTarget(env, {
    REPORT_NAME: parts[0],
    PO0_HOST: parts[1],
    PO0_PORT: parts[2],
    PO0_USER: parts[3],
    PO0_SCRIPT: parts[4],
    REPORT_TOKEN: parts[5],
    REPORT_IDENTITY: parts[6],
    TTL_SECONDS: parts[7],
  }, index);
}

function parseTargets(env) {
  const raw = String(env.PO0_TARGETS || '').trim();
  if (!raw) {
    return [normalizeTarget(env, {}, 0)];
  }

  if (raw.startsWith('[')) {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed) || parsed.length === 0) {
      throw new Error('PO0_TARGETS JSON must be a non-empty array');
    }
    return parsed.map((target, index) => normalizeTarget(env, target, index));
  }

  const lines = raw
    .split(/\r?\n|;/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('#'));
  if (lines.length === 0) {
    throw new Error('PO0_TARGETS is empty');
  }
  return lines.map((line, index) => parseTargetLine(env, line, index));
}

function sshConfig(env, target) {
  const config = {
    host: target.host,
    port: target.port,
    username: target.username,
    timeout: 10000,
  };
  if (String(target.privateKey || '').trim()) {
    config.privateKey = String(target.privateKey).replace(/\\n/g, '\n');
    if (String(target.passphrase || '').trim()) {
      config.passphrase = target.passphrase;
    }
  } else {
    if (!String(target.password || '').trim()) {
      throw new Error(`PO0 target ${target.reportName}@${target.host} missing SSH password/private key`);
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
      '--client-ip-report',
      shQuote(target.reportName),
      shQuote(ip),
      shQuote(target.token),
      shQuote(target.identity),
      shQuote(String(target.ttlSeconds)),
    ].join(' ');
    const result = await session.exec(command);
    const code = result.code ?? result.exitCode ?? 0;
    if (code !== 0) {
      throw new Error(`${target.reportName}@${target.host}: ${result.stderr || result.stdout || code}`);
    }
    return result.stdout || `OK ${target.reportName} ${ip}`;
  } finally {
    await session.close();
  }
}

export default async function(ctx) {
  const env = ctx.env || {};
  const policy = env.POLICY || 'DIRECT';
  const notifySuccess = boolEnv(env.NOTIFY_SUCCESS, false) || isManualRun(ctx);
  const notifyFailure = boolEnv(env.NOTIFY_FAILURE, true) || isManualRun(ctx);
  const startedAt = new Date();
  let targets = [];
  let ip = '';

  try {
    targets = parseTargets(env);
    ip = await detectCurrentIPv4WithFallback(ctx, env, policy);
    const results = [];
    const failures = [];

    for (const target of targets) {
      try {
        const output = await reportToPO0(ctx, env, target, ip);
        results.push({
          ok: true,
          reportName: target.reportName,
          host: target.host,
          port: target.port,
          identity: target.identity,
          ttlSeconds: target.ttlSeconds,
          expiresAt: new Date(startedAt.getTime() + Math.max(60, target.ttlSeconds) * 1000).toISOString(),
          output: String(output || '').trim(),
        });
      } catch (error) {
        failures.push({
          ok: false,
          reportName: target.reportName,
          host: target.host,
          port: target.port,
          error: error?.message || String(error),
        });
      }
    }

    const state = {
      ok: failures.length === 0,
      reportName: targets.map((target) => target.reportName).join(','),
      ip,
      po0Host: targets.map((target) => target.host).join(','),
      identity: targets.map((target) => target.identity).filter(Boolean).join(','),
      network: networkLabel(ctx),
      at: startedAt.toISOString(),
      targetCount: targets.length,
      successCount: results.length,
      failureCount: failures.length,
      targets: [...results, ...failures],
    };
    await storageSet(ctx, STORAGE_KEY, JSON.stringify(state));

    if (failures.length > 0) {
      const errorSummary = failures.map((failure) => `${failure.reportName}@${failure.host}: ${failure.error}`).join('; ');
      if (notifyFailure) {
        notify(ctx, 'PO0 Client IP Report Failed', `${ip}: ${results.length}/${targets.length} OK; ${errorSummary}`);
      }
      return state;
    }

    if (notifySuccess) {
      notify(ctx, 'PO0 Client IP Report', `${ip}: ${results.length}/${targets.length} PO0 updated`);
    }
    return state;
  } catch (error) {
    const state = {
      ok: false,
      reportName: targets.map((target) => target.reportName).join(',') || String(env.REPORT_NAME || 'egern').trim() || 'egern',
      po0Host: targets.map((target) => target.host).join(',') || env.PO0_HOST || '',
      ip,
      network: networkLabel(ctx),
      at: new Date().toISOString(),
      targetCount: targets.length,
      successCount: 0,
      failureCount: targets.length || 1,
      error: error?.message || String(error),
    };
    await storageSet(ctx, STORAGE_KEY, JSON.stringify(state));
    if (notifyFailure) {
      notify(ctx, 'PO0 Client IP Report Failed', state.error);
    }
    throw error;
  }
}
