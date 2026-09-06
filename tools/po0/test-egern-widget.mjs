import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const source = await readFile(resolve(root, 'scripts/po0/nftables/clients/egern/po0-ssh-ip-report.js'), 'utf8');
const { widgetFromState, parseTargets, widgetOfficialEntries, shortHash } = await import('data:text/javascript;base64,' + Buffer.from(source + '\nexport { widgetFromState, parseTargets, widgetOfficialEntries, shortHash };').toString('base64'));
const ctx = family => ({ widgetFamily: family, script: { name: 'PO0 防火墙上报状态' }, device: { wifi: { ssid: 'HomeWiFi' }, ipv4: { address: '192.168.1.20', gateway: '192.168.1.1' } } });
const env = {
  SSH_REPORT_TARGETS: 'sg|sg.example.com||||ssh-one|新加坡|7200,us|us.example.com||||ssh-two|美国|14400',
  PO0_PASSWORD: 'mock-password',
  PO0_FIREWALL_TOKENS: 'pgnfw_one@0,pgnfw_two@2', PO0_FIREWALL_NAMES: '家庭防火墙;办公室',
};
const state = {
  ok: true, ip: '203.0.113.45', at: '2026-09-06T08:20:00Z', deviceId: 'iPhone',
  targets: [
    { sourceId: 'sg', host: 'sg.example.com', port: 22, identity: '旧备注', ttlSeconds: 999, ok: true },
    { sourceId: 'us', host: 'us.example.com', port: 22, ok: true },
  ],
  official: { entries: [
    { accountKey: shortHash('pgnfw_one'), ordinal: 1, name: '旧名称', status: 'hit', currentIp: '203.0.113.45/24', used: 1, limit: 5, fixedSlot: 0 },
    { accountKey: shortHash('pgnfw_two'), ordinal: 2, name: '', status: 'updated', currentIp: '203.0.113.45/24', used: 2, limit: 5, fixedSlot: 2 },
  ] },
};
function nodes(node) { return [node, ...(node.children || []).flatMap(nodes)]; }
function texts(widget) { return nodes(widget).filter(n => n.type === 'text').map(n => n.text); }
const previews = [];
for (const family of ['systemSmall', 'systemMedium', 'systemLarge']) {
  for (const scenario of [
    { name: '两通道正常', config: env },
    { name: 'SSID 命中', config: { ...env, SKIP_WIFI_SSIDS: 'HomeWiFi' } },
    { name: '两通道自动停用', config: { ...env, WORKER_AUTO_ENABLED: 'false', OFFICIAL_AUTO_ENABLED: 'false' } },
    { name: '仅自建停用', config: { ...env, WORKER_AUTO_ENABLED: 'false' } },
  ]) {
    const widget = widgetFromState(state, ctx(family), 'iPhone', scenario.config);
    const visible = texts(widget);
    assert(visible.some(t => t.startsWith('家庭防火墙')), 'saved official name must display despite an old cached name');
    assert(!visible.includes('旧名称'));
    assert(!visible.includes('旧备注'));
    assert(!visible.some(t => t.includes('0/1')));
    if (family !== 'systemSmall') assert(visible.includes('办公室'), 'medium/large must show both configured official names');
    for (const node of nodes(widget).filter(n => n.type === 'text')) {
      assert(node.text.trim(), 'no empty text rows');
      assert(typeof node.font.size === 'number' && node.font.size >= 11, 'widget fonts must be explicit and readable');
      assert(node.minScale >= 0.9, 'long lines must not shrink to tiny text');
    }
    const count = text => visible.filter(t => t === text).length;
    if (scenario.name === 'SSID 命中') {
      assert.equal(count('SSID跳过'), 2, 'the shared SSID guard must appear on both lanes');
      assert.equal(count('自动停用'), 0, 'SSID skip must not claim that persistent switches are off');
    } else if (scenario.name === '两通道自动停用') assert.equal(count('自动停用'), 2);
    else if (scenario.name === '仅自建停用') { assert.equal(count('自动停用'), 1); assert.equal(count('自动开启'), 1); }
    else assert.equal(count('自动开启'), 2);
    assert(!JSON.stringify(widget).includes('pgnfw_'));
    previews.push({ name: scenario.name, family, widget });
  }
}

const reordered = widgetOfficialEntries(state, { ...env, PO0_FIREWALL_TOKENS: 'pgnfw_two@2,pgnfw_one@0', PO0_FIREWALL_NAMES: '办公室;家庭防火墙' });
assert.deepEqual(reordered.map(x => [x.name, x.used]), [['办公室', 2], ['家庭防火墙', 1]]);
assert.equal(widgetOfficialEntries(state, { ...env, PO0_FIREWALL_TOKENS: 'pgnfw_new@0' })[0].status, undefined, 'new account must not inherit another account result');
assert.equal(widgetOfficialEntries(state, { ...env, PO0_FIREWALL_TOKENS: 'pgnfw_one@3' })[0].status, undefined, 'changed fixed slot must be checked again');
const mixed = texts(widgetFromState(state, ctx('systemMedium'), '', { ...env, SKIP_WIFI_SSIDS: 'HomeWiFi', WORKER_AUTO_ENABLED: 'false' }));
assert.equal(mixed.filter(t => t === '自动停用').length, 1);
assert.equal(mixed.filter(t => t === 'SSID跳过').length, 1);
const skipped = widgetFromState({ ...state, skipped: true, skipType: 'wifi-ssid' }, ctx('systemMedium'), '', { ...env, SKIP_WIFI_SSIDS: 'HomeWiFi' });
assert(texts(skipped).includes('本次 SSID 跳过 · 保留上次结果'));
for (const family of ['systemSmall', 'systemMedium', 'systemLarge']) {
  const many = { ...env, SSH_REPORT_TARGETS: [1,2,3,4].map(i => 's'+i+'|s'+i+'.example.com||||token'+i+'|设备'+i+'|'+(i*3600)).join(','), PO0_FIREWALL_TOKENS: [1,2,3,4,5].map(i => 'pgnfw_many'+i+'@'+(i-1)).join(','), PO0_FIREWALL_NAMES: '家庭防火墙;办公室;测试环境;备用账号;第五个账号' };
  const widget = widgetFromState(state, ctx(family), 'iPhone', many);
  previews.push({ name: '较多目标', family, widget });
}

const legacy = { PO0_HOST: 'legacy.example.com', PO0_PORT: '2200', PO0_USER: 'legacy-user', PO0_SCRIPT: '/root/legacy.sh', SSH_REPORT_SOURCE: 'legacy-source', SSH_REPORT_TOKEN: 'legacy-token', REPORT_IDENTITY: 'legacy-name', TTL_SECONDS: '3600', PO0_PASSWORD: 'shared-pass' };
for (const raw of [
  'custom|target.example.com|2222|reporter|/root/target.sh|target-token|target-name|7200',
  JSON.stringify([{ sourceId: 'custom', host: 'target.example.com', port: 2222, user: 'reporter', script: '/root/target.sh', token: 'target-token', identity: 'target-name', ttl: 7200 }]),
  JSON.stringify([{ source: 'custom', po0Host: 'target.example.com', port: 2222, username: 'reporter', po0Script: '/root/target.sh', reportToken: 'target-token', identity: 'target-name', ttlSeconds: 7200 }]),
]) {
  const [target] = parseTargets({ ...legacy, SSH_REPORT_TARGETS: raw });
  assert.deepEqual([target.sourceId, target.host, target.port, target.username, target.script, target.token, target.identity, target.ttlSeconds], ['custom', 'target.example.com', 2222, 'reporter', '/root/target.sh', 'target-token', 'target-name', 7200]);
}
assert.equal(parseTargets({ ...legacy, SSH_REPORT_TARGETS: 'phone|target.example.com||||token' })[0].ttlSeconds, 3600, 'omitted TTL may inherit legacy default');
assert.equal(parseTargets({ SSH_REPORT_TARGETS: 'phone|target.example.com||||token' })[0].ttlSeconds, 43200, 'no target/default TTL uses built-in default');
assert.equal(parseTargets(legacy)[0].ttlSeconds, 3600, 'legacy single target remains compatible');
if (process.argv.includes('--preview')) {
  await mkdir(resolve(root, '.tmp/po0-egern-widget-preview'), { recursive: true });
  await writeFile(resolve(root, '.tmp/po0-egern-widget-preview/widgets.json'), JSON.stringify(previews));
}
console.log('PASS: Egern widget names, both automatic states, typography, and target/default precedence.');
