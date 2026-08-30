import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const viewPath = path.join(repoRoot, 'packaging', 'openwrt', 'po0-outbound-ip-report', 'files', 'www', 'luci-static', 'resources', 'view', 'po0', 'outbound-ip-report.js');
const source = fs.readFileSync(viewPath, 'utf8');
const start = source.indexOf('function formatRecentResult');
const end = source.indexOf('\n\nreturn view.extend', start);

if (start < 0 || end < 0)
    throw new Error('formatRecentResult function not found');
if (source.includes('ui.addNotification'))
    throw new Error('PO0 LuCI actions must use one inline result area, not global notifications');
if (source.includes("fs.exec(CONTROL, [ 'test' ])") || source.includes("fs.exec(CONTROL, [ 'test-force' ])"))
    throw new Error('PO0 LuCI manual tests must not block one RPC request');
for (const expectedSource of [
    "'test-start'",
    "'test-force-start'",
    "[ 'test-status' ]",
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
    'exit_code=0',
    '上报上游路由器 WAN wan1的公网出口 IPv4 203.0.113.11 到 LAN Worker：https://report.example.test/report',
    'OK 203.0.113.11; targets=2; target_names=internal-a,internal-b',
    'PO0 Outbound IP Report 已完成：上游路由器 WAN wan1的公网出口 IPv4 203.0.113.11 已被 LAN Worker 接收。',
    'PO0 Outbound IP Report 已完成：上游路由器 WAN wan2的公网出口 IPv4 198.51.100.22 已被 LAN Worker 接收。',
    'PO0 Outbound IP Report 已完成：WAN 上报结束：成功 2 条，失败 0 条。'
].join('\n');
const result = formatRecentResult(raw);

for (const expected of [ '上报时间：', '执行状态：成功', 'wan1：成功', 'wan2：成功', '汇总：成功 2 条 · 失败 0 条' ]) {
    if (!result.text.includes(expected))
        throw new Error(`formatted result missing: ${expected}`);
}
for (const forbidden of [ 'observed_at=', 'LAN Worker：https://', 'targets=', 'target_names=' ]) {
    if (result.text.includes(forbidden))
        throw new Error(`formatted result leaked raw detail: ${forbidden}`);
}
if (result.error)
    throw new Error('successful report was formatted as an error');
if (result.level !== 'success' || result.title !== '上报成功')
    throw new Error('successful report did not produce the success result card state');

console.log('OpenWrt LuCI result formatting tests passed.');
