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


// Saving an official form must neither parse nor validate any Worker/common input.
const fieldStart = source.indexOf('   function field(');
const fieldEnd = source.indexOf('   function resultSection(', fieldStart);
const parsedFields = [];
const formTypes = { SectionValue: {}, Value: {}, Flag: {}, Button: {} };
const mapScope = { po0SaveChannel: 'official', channelKeys: {worker:[],official:[],network:[]} };
const sectionStub = { taboption(tab, type, key) { return {
    parse() { parsedFields.push(key); if (tab === 'worker') throw new Error('invalid Worker fixture'); return Promise.resolve(); },
    depends() {}
}; } };
const scopedField = Function('s','m','form','_', source.slice(fieldStart, fieldEnd) + '; return field;')(sectionStub, mapScope, formTypes, globalThis._);
const badWorker = scopedField('worker', formTypes.Value, 'worker_url', 'URL');
const officialInput = scopedField('official', formTypes.SectionValue, '_official_targets', {}, 'official_target');
await badWorker.parse();
await officialInput.parse();
if (parsedFields.join(',') !== '_official_targets') throw new Error('official save parsed opposite-channel fields');
mapScope.po0SaveChannel = 'worker';
parsedFields.length = 0;
await officialInput.parse();
if (parsedFields.length) throw new Error('Worker save parsed official target fields');

// Query/report actions use saved configuration and cannot call the save routine.
const actionStart = source.indexOf('function runChannelAction(');
const actionEnd = source.indexOf('\nfunction refreshChannelResult(', actionStart);
const calls = [];
const runAction = Function('fs','CONTROL','showActionResult','renderOfficialStatus','officialActionSummary','showChannelResult','pollChannelResult','redactOfficialText','_',
    'var channelActionRunning = {};\n' + source.slice(actionStart, actionEnd) + ';return runChannelAction;')(
    { exec: async (_, args) => { calls.push(args[0]); return { code:0,stdout:'',stderr:'' }; } }, 'mock-control',
    () => {}, () => ({rows:[]}), () => '', () => ({}), async () => {}, x => x, globalThis._);
const neverSave = { save() { throw new Error('read/report must not save'); } };
for (const action of ['official-status','official-report','worker-force-report']) await runAction(neverSave, action.startsWith('official')?'official':'worker', action);
if (calls.join(',') !== 'official-status,official-report,worker-force-report') throw new Error('explicit actions did not run independently');
console.log('OpenWrt LuCI scoped-save and no-implicit-save action tests passed.');

// Pending native table edits must never be committed by the other save button.
const persistStart = source.indexOf('function persistReporterChannel(map)');
const persistEnd = source.indexOf('function saveReporter(map)', persistStart);
const initial = {
 main: {'.type':'reporter','.name':'main',worker_url:'saved-worker',secret:'saved-secret',source_id:'stable-source',interval_seconds:'5400',worker_timer_enabled:'0',official_enabled:'1',official_interval_seconds:'900',enabled:'1'},
 account: {'.type':'official_target','.name':'account',token:'pgnfw_saved_fixture',label:'saved-account'},
 binding: {'.type':'official_binding','.name':'binding',target:'account',wan:'wan1',slot:'3'}
};
let stored = structuredClone(initial);
const draft = structuredClone(initial);
draft.main.worker_url = 'edited-worker';
draft.main.official_interval_seconds = '1800';
delete draft.account;
draft.new_account = {'.type':'official_target','.name':'new_account',token:'pgnfw_new_fixture',label:'edited-account'};
draft.binding.target = 'new_account';
const mutations=[];
const backend = {
 unload() {}, async load() {}, async save() {mutations.push('save');},
 get(_c,id,key) {return key ? stored[id]?.[key] : stored[id];},
 set(_c,id,key,value) {if(value == null) delete stored[id][key]; else stored[id][key]=value; mutations.push(id+'.'+key);},
 sections(_c,type) {return Object.values(stored).filter(x=>x['.type']===type);},
 remove(_c,id) {delete stored[id]; mutations.push('remove:'+id);},
 add(_c,type,id) {stored[id]={'.type':type,'.name':id};mutations.push('add:'+id);},
 move() {}
};
const persist = Function('uci', source.slice(persistStart,persistEnd)+';return persistReporterChannel;')(backend);
const pendingMap = {
 po0SaveChannel:'worker', channelKeys:{worker:['worker_url','secret','source_id','interval_seconds','worker_timer_enabled'],official:['official_enabled','official_interval_seconds'],network:['enabled']},
 data:{get(_c,id,key){return draft[id]?.[key];},sections(_c,type){return Object.values(draft).filter(x=>x['.type']===type);}}
};
await persist(pendingMap);
if (stored.main.worker_url!=='edited-worker' || JSON.stringify(stored.account)!==JSON.stringify(initial.account) || stored.binding.target!=='account' || stored.new_account || stored.main.official_interval_seconds!=='900') throw new Error('Worker save committed pending official table/interval edits');
stored=structuredClone(initial); mutations.length=0; pendingMap.po0SaveChannel='official';
await persist(pendingMap);
if(stored.main.worker_url!=='saved-worker' || stored.main.secret!=='saved-secret' || stored.main.worker_timer_enabled!=='0' || stored.main.interval_seconds!=='5400' || stored.main.source_id!=='stable-source') throw new Error('official save overwrote Worker parameters');
if(stored.account || !stored.new_account || stored.binding.target!=='new_account' || stored.binding.slot!=='3' || stored.main.official_interval_seconds!=='1800') throw new Error('official target/binding save lost stable slot or pending edits');
console.log('OpenWrt LuCI pending table edits and channel persistence isolation tests passed.');
