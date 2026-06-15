function required(env, key) {
  const value = (env[key] || '').trim();
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

async function resolveA(ctx, domain, dohUrl, policy) {
  const url = `${dohUrl}?name=${encodeURIComponent(domain)}&type=A`;
  const resp = await ctx.http.get(url, { timeout: 10000, policy });
  if (resp.status < 200 || resp.status >= 300) {
    throw new Error(`DoH failed: HTTP ${resp.status}`);
  }
  const data = await resp.json();
  const seen = new Set();
  const ips = [];
  for (const answer of data.Answer || []) {
    const ip = String(answer.data || '').trim();
    if (isPublicIPv4(ip) && !seen.has(ip)) {
      seen.add(ip);
      ips.push(ip);
    }
  }
  if (ips.length === 0) throw new Error(`No public IPv4 for ${domain}`);
  return ips;
}

export default async function(ctx) {
  const env = ctx.env || {};
  const host = required(env, 'PO0_HOST');
  const username = env.PO0_USER || 'root';
  const port = Number(env.PO0_PORT || 22);
  const script = env.PO0_SCRIPT || '/root/nftables-relay-manager.sh';
  const domain = required(env, 'DDNS_DOMAIN');
  const name = (env.DDNS_NAME || '').trim() || domain;
  const token = (env.DDNS_TOKEN || '').trim();
  const dohUrl = env.DOH_URL || 'https://dns.alidns.com/resolve';
  const policy = env.POLICY || 'DIRECT';
  const notify = env.NOTIFY === 'true';

  const ips = await resolveA(ctx, domain, dohUrl, policy);
  const config = { host, port, username, timeout: 10000 };
  if ((env.PO0_PRIVATE_KEY || '').trim()) {
    config.privateKey = env.PO0_PRIVATE_KEY.replace(/\\n/g, '\n');
    if ((env.PO0_PASSPHRASE || '').trim()) {
      config.passphrase = env.PO0_PASSPHRASE;
    }
  } else {
    config.password = required(env, 'PO0_PASSWORD');
  }

  const session = await ctx.ssh.connect(config);
  try {
    const command = [
      'bash',
      shQuote(script),
      '--ddns-report',
      shQuote(name),
      shQuote(ips.join(',')),
      token ? shQuote(token) : '',
    ].filter(Boolean).join(' ');
    const result = await session.exec(command);
    if (result.code !== 0) {
      throw new Error(`PO0 report failed: ${result.stderr || result.stdout || result.code}`);
    }
    if (notify) {
      ctx.notify({
        title: 'PO0 DDNS Report',
        body: `${name} ${domain} -> ${ips.join(', ')}`,
      });
    }
  } finally {
    await session.close();
  }
}
