import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const viewPath = path.join(repoRoot, 'packaging', 'openwrt', 'po0-outbound-ip-report', 'files', 'www', 'luci-static', 'resources', 'view', 'po0', 'outbound-ip-report.js');
const source = fs.readFileSync(viewPath, 'utf8');
const start = source.indexOf('function pad2');
const end = source.indexOf('\n\nreturn view.extend', start);

if (start < 0 || end < 0)
    throw new Error('LuCI result formatting helpers not found');
if (source.includes('ui.addNotification'))
    throw new Error('PO0 LuCI actions must use one inline result area, not global notifications');
if (source.includes("fs.exec(CONTROL, [ 'test' ])") || source.includes("fs.exec(CONTROL, [ 'test-force' ])"))
    throw new Error('PO0 LuCI manual tests must not block one RPC request');
for (const expectedSource of [
    "channel + '-report'",
    "'worker-force-report'",
    "channel + '-progress'",
    'po0-result-card',
    '允许明文 HTTP（不推荐）'
]) {
    if (!source.includes(expectedSource))
        throw new Error(`LuCI source missing asynchronous/UI feature: ${expectedSource}`);
}
if (source.includes("E('pre'"))
    throw new Error('PO0 LuCI result UI must not render a raw preformatted text box');

String.prototype.format = function(...args) {
    let index = 0;
    return this.replace(/%[sd]/g, () => String(args[index++]));
};
globalThis._ = value => value;
const formatRecentResult = Function('_', `${source.slice(start, end)}\nreturn formatRecentResult;`)(globalThis._);

const raw = [
    'observed_at=1788074964',
    'finished_at=1788074988',
    'exit_code=0',
    '上报上游路由器 WAN wan1的公网出口 IPv4 203.0.113.11 到 LAN Worker：https://report.example.test/report',
    'OK 203.0.113.11; targets=2; target_names=internal-a,internal-b',
    'PO0 Outbound IP Report 已完成：上游路由器 WAN wan1的公网出口 IPv4 203.0.113.11 已被 LAN Worker 接收。',
    'PO0 Outbound IP Report 已完成：上游路由器 WAN wan2的公网出口 IPv4 198.51.100.22 已被 LAN Worker 接收。',
    'PO0 Outbound IP Report 已完成：WAN 上报结束：成功 2 条，失败 0 条。'
].join('\n');
const result = formatRecentResult(raw);

for (const expected of [
    '任务开始时间：',
    '任务完成时间：',
    '执行耗时：24 秒',
    '执行状态：成功',
    'wan1：成功',
    'wan2：成功',
    '汇总：成功 2 条 · 失败 0 条'
]) {
    if (!result.text.includes(expected))
        throw new Error(`formatted result missing: ${expected}`);
}
for (const forbidden of [ 'observed_at=', 'LAN Worker：https://', 'targets=', 'target_names=' ]) {
    if (result.text.includes(forbidden))
        throw new Error(`formatted result leaked raw detail: ${forbidden}`);
}
if (result.level !== 'success' || result.title !== '上报成功')
    throw new Error('successful report did not produce the success result card state');
if (!source.includes('页面刷新时间：%s'))
    throw new Error('result card must label browser rendering time as page refresh time');
if (!/任务开始时间：\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/.test(result.text))
    throw new Error('task start time is not formatted as Chinese 24-hour date-time');
if (!/任务完成时间：\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/.test(result.text))
    throw new Error('task finish time is not formatted as Chinese 24-hour date-time');

const legacyResult = formatRecentResult(raw.replace(/^finished_at=.*\n/m, ''));
if (legacyResult.text.includes('任务完成时间：') || legacyResult.text.includes('执行耗时：'))
    throw new Error('legacy state without finished_at must not fabricate completion time or duration');

const direct = formatRecentResult(raw.replaceAll('上游路由器 WAN', 'WAN'));
if (!direct.text.includes('wan1：成功') || !direct.text.includes('wan2：成功'))
    throw new Error('direct gateway results lost per-WAN status');
const normalizeToken = Function('_', `${source.slice(start, end)}\nreturn normalizeOfficialToken;`)(globalThis._);
if (normalizeToken('https://124.221.69.228/api/firewall/pgnfw_example/add') !== 'pgnfw_example')
    throw new Error('full official URL was not normalized');
console.log('OpenWrt LuCI result formatting tests passed.');

// rpcd checks ubus method access and UCI config write access independently.
// Exercise the real page RPC declaration and save function under both checks.
const aclPath = path.join(repoRoot, 'packaging', 'openwrt', 'po0-outbound-ip-report', 'files', 'usr', 'share', 'rpcd', 'acl.d', 'po0-outbound-ip-report.json');
const reporterAcl = JSON.parse(fs.readFileSync(aclPath, 'utf8'))['po0-outbound-ip-report'];
const configName = 'po0_outbound_ip_report';
const declaration = source.match(/^var commitReporter = (rpc\.declare\([^\n]+\));$/m)?.[1];
const saveStart = source.indexOf('function saveReporter(map) {');
const saveEnd = source.indexOf('\nfunction runChannelAction', saveStart);
if (!declaration || saveStart < 0 || saveEnd < 0)
    throw new Error('reporter save implementation not found');
for (const mode of ['read', 'write']) {
    if (JSON.stringify(reporterAcl[mode].uci) !== JSON.stringify([configName]))
        throw new Error(`reporter ${mode} UCI access must name only its own config`);
}
if (JSON.stringify(reporterAcl.write.ubus.uci) !== JSON.stringify(['commit']))
    throw new Error('reporter must grant only the missing commit method');

async function exerciseSave(acl, { saveFails = false, overrideConfig } = {}) {
    const events = [];
    const rpc = {
        declare(spec) {
            return async function(...args) {
                const params = Object.fromEntries(spec.params.map((key, index) => [key, args[index]]));
                if (overrideConfig !== undefined) params.config = overrideConfig;
                events.push({ object: spec.object, method: spec.method, params });
                if (!acl.write.ubus?.[spec.object]?.includes(spec.method))
                    throw new Error('ubus method access denied');
                if (!acl.write.uci?.includes(params.config))
                    throw new Error('UCI config write access denied');
            };
        }
    };
    const commit = Function('rpc', `return ${declaration};`)(rpc);
    const save = Function('commitReporter', 'refreshChannelResult',
        `${source.slice(saveStart, saveEnd)}; return saveReporter;`)(
        commit, async channel => { events.push(`cached-result:${channel}`); });
    let failure;
    try {
        await save({ save: async () => {
            events.push('form-save');
            if (saveFails) throw new Error('form validation failed');
        } });
    } catch (err) { failure = err.message; }
    return { events, failure };
}
const saved = await exerciseSave(reporterAcl);
const expectedEvents = ['form-save', {
    object: 'uci', method: 'commit', params: { config: configName }
}, 'cached-result:worker', 'cached-result:official'];
if (saved.failure || JSON.stringify(saved.events) !== JSON.stringify(expectedEvents))
    throw new Error('save must commit exactly the reporter config before reading cached results');
const withoutCommit = structuredClone(reporterAcl);
delete withoutCommit.write.ubus.uci;
const deniedMethod = await exerciseSave(withoutCommit);
if (deniedMethod.failure !== 'ubus method access denied' || deniedMethod.events.length !== 2)
    throw new Error('legacy ACL must reproduce commit access denied before result refresh');
for (const config of ['network', 'firewall', '*', '']) {
    const deniedConfig = await exerciseSave(reporterAcl, { overrideConfig: config });
    if (deniedConfig.failure !== 'UCI config write access denied' || deniedConfig.events.length !== 2)
        throw new Error('commit method permission must not permit other UCI configs');
}
const invalidForm = await exerciseSave(reporterAcl, { saveFails: true });
if (invalidForm.failure !== 'form validation failed' || invalidForm.events.length !== 1)
    throw new Error('failed form validation must not commit or read results');
console.log('OpenWrt LuCI narrow-ACL save regression tests passed.');
