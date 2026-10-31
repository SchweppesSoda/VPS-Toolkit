import fs from 'node:fs';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const viewPath = path.join(repoRoot, 'packaging', 'openwrt', 'po0-outbound-ip-report', 'files', 'www', 'luci-static', 'resources', 'view', 'po0', 'outbound-ip-report.js');
const source = fs.readFileSync(viewPath, 'utf8');
const start = source.indexOf('function safeOfficialText');
const end = source.indexOf('\n\nreturn view.extend', start);

if (start < 0 || end < 0)
    throw new Error('LuCI result formatting helpers not found');
if (source.includes('ui.addNotification'))
    throw new Error('PO0 LuCI actions must use one inline result area, not global notifications');
if (source.includes("fs.exec(CONTROL, [ 'test' ])") || source.includes("fs.exec(CONTROL, [ 'test-force' ])"))
    throw new Error('PO0 LuCI manual tests must not block one RPC request');
for (const expectedSource of [
    "channel + '-report'",
    "channel + '-progress'",
    'po0-result-card',
    '保存并应用配置'
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
const normalizeToken = Function('_', `${source.slice(source.indexOf('function normalizeOfficialToken'), end)}\nreturn normalizeOfficialToken;`)(globalThis._);
if (normalizeToken('https://124.221.69.228/api/firewall/pgnfw_example/add') !== 'pgnfw_example') throw new Error('token normalization changed');

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
    const save = Function('commitReporter', 'persistReporterConfig', 'fs', 'CONTROL', 'renderOfficialStatus', 'lastOfficialResult',
        `${source.slice(saveStart, saveEnd)}; return saveReporter;`)(
        commit, async () => { events.push('persist-all'); },
        { exec: async (_path, args) => { events.push(args.join(' ')); return {code: 0}; } }, 'mock-control',
        () => { events.push('render-cache'); }, 'cached');
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
const expectedEvents = ['form-save', 'persist-all', {
    object: 'uci', method: 'commit', params: { config: configName }
}, 'reload', 'render-cache'];
if (saved.failure || JSON.stringify(saved.events) !== JSON.stringify(expectedEvents))
    throw new Error('apply must persist all settings, commit only this config and reload without a query or report');
const withoutCommit = structuredClone(reporterAcl);
delete withoutCommit.write.ubus.uci;
const deniedMethod = await exerciseSave(withoutCommit);
if (deniedMethod.failure !== 'ubus method access denied' || deniedMethod.events.length !== 3)
    throw new Error('legacy ACL must reproduce commit access denied before result refresh');
for (const config of ['network', 'firewall', '*', '']) {
    const deniedConfig = await exerciseSave(reporterAcl, { overrideConfig: config });
    if (deniedConfig.failure !== 'UCI config write access denied' || deniedConfig.events.length !== 3)
        throw new Error('commit method permission must not permit other UCI configs');
}
const invalidForm = await exerciseSave(reporterAcl, { saveFails: true });
if (invalidForm.failure !== 'form validation failed' || invalidForm.events.length !== 1)
    throw new Error('failed form validation must not commit or read results');
console.log('OpenWrt LuCI narrow-ACL save regression tests passed.');


// Query/report actions use saved configuration and cannot call the save routine.
const actionStart = source.indexOf('function runChannelAction(');
const actionEnd = source.indexOf('\nfunction refreshChannelResult(', actionStart);
const calls = [];
const runAction = Function('fs','CONTROL','showActionResult','renderOfficialStatus','officialActionSummary','showChannelResult','pollChannelResult','redactOfficialText','_',
    'var channelActionRunning = {};\n' + source.slice(actionStart, actionEnd) + ';return runChannelAction;')(
    { exec: async (_, args) => { calls.push(args[0]); return { code:0,stdout:'',stderr:'' }; } }, 'mock-control',
    () => {}, () => ({rows:[]}), () => '', () => ({}), async () => {}, x => x, globalThis._);
const neverSave = { save() { throw new Error('read/report must not save'); } };
for (const action of ['official-status','official-report','official-force-report']) await runAction(neverSave, action.startsWith('official')?'official':'worker', action);
if (calls.join(',') !== 'official-status,official-report,official-force-report') throw new Error('explicit actions did not run independently');
console.log('OpenWrt LuCI unified apply and independent manual action tests passed.');


// UCI fixture with ordered sections, so reordering persistence is exercised.
function store(initial) {
 const data = structuredClone(initial);
 return {
  data, unload() {}, async load() {}, async save() {},
  get(_c,id,key) {return key ? data[id]?.[key] : data[id];},
  set(_c,id,key,value) {if(value == null) delete data[id][key]; else data[id][key]=value;},
  sections(_c,type) {return Object.values(data).filter(x=>!type || x['.type']===type).sort((a,b)=>a['.index']-b['.index']);},
  remove(_c,id) {delete data[id];},
  add(_c,type,id) {data[id]={'.type':type,'.name':id,'.index':1000};},
  move(_c,id,neighbor,after) {
   if (!data[id] || !data[neighbor] || id===neighbor) return false;
   const rows=this.sections(_c).filter(row=>row['.name']!==id);
   rows.splice(rows.findIndex(row=>row['.name']===neighbor)+Number(!!after),0,data[id]);
   rows.forEach((row,index)=>{row['.index']=index;});
   return true;
  }
 };
}
const initial = Object.fromEntries([
 ['main','reporter',{enabled:'0',official_enabled:'1',official_interval_seconds:'600',probe_dns_server:'192.0.2.1',worker_url:'untouched'}],
 ['a','official_target',{label:'甲',token:'pgnfw_fixture_a',enabled:'1'}],
 ['b','official_target',{label:'乙',token:'pgnfw_fixture_b',enabled:'1'}],
 ['a1','official_binding',{target:'a',wan:'wan1',slot:'0',enabled:'1'}],
 ['b1','official_binding',{target:'b',wan:'wan1',slot:'0',enabled:'1'}],
 ['a2','official_binding',{target:'a',wan:'wan2',slot:'1',enabled:'1'}],
 ['b2','official_binding',{target:'b',wan:'wan2',slot:'1',enabled:'1'}]
].map(([id,type,values],index)=>[id,{'.name':id,'.type':type,'.index':index,...values}]));
const stored=store(initial), draft=store(initial);
const helperSource=source.slice(source.indexOf('function safeOfficialText'),source.indexOf('var OfficialStatusSection'))+
 source.slice(source.indexOf('function orderedBindings'),source.indexOf('var OrderedTableSection'));
const {orderedBindings,orderedOfficialRows,moveReporterRow,parseOfficialStatus}=Function('uci','_',helperSource+
 ';return {orderedBindings,orderedOfficialRows,moveReporterRow,parseOfficialStatus};')(stored,globalThis._);
const ids=rows=>rows.map(row=>row['.name']);
assert.deepEqual(ids(orderedBindings(draft,configName)),['a1','a2','b1','b2']);
assert.equal(moveReporterRow({data:draft},'official_target','b','a',false),true);
assert.deepEqual(ids(orderedBindings(draft,configName)),['b1','b2','a1','a2']);
assert.equal(moveReporterRow({data:draft},'official_binding','b2','b1',false),true);
assert.deepEqual(ids(orderedBindings(draft,configName)),['b2','b1','a1','a2']);
assert.equal(moveReporterRow({data:draft},'official_binding','a1','b2',false),false);
assert.equal(moveReporterRow({data:draft},'official_target','a','b1',false),false);
assert.equal(moveReporterRow({data:draft},'official_target','a','a',false),false);
assert.equal(moveReporterRow({data:draft},'official_binding','missing','a1',false),false);
assert.deepEqual(ids(stored.sections(configName,'official_target')),['a','b']);

// All tabs and the total switch save together, without touching retired fields.
draft.set(configName,'main','enabled','1');
draft.set(configName,'main','official_interval_seconds','900');
draft.set(configName,'main','probe_dns_server','192.0.2.53');
draft.set(configName,'main','worker_url','must-not-save');
draft.set(configName,'b','label','乙改名');
const persist=Function('uci','orderedBindings',source.slice(source.indexOf('function persistReporterConfig'),source.indexOf('function saveReporter'))+
 ';return persistReporterConfig;')(stored,orderedBindings);
const map={data:draft,configKeys:['enabled','official_enabled','official_interval_seconds','probe_dns_server']};
await persist(map);
assert.deepEqual(ids(stored.sections(configName,'official_target')),['b','a']);
assert.deepEqual(ids(stored.sections(configName,'official_binding')),['b2','b1','a1','a2']);
assert.equal(stored.data.main.enabled,'1');
assert.equal(stored.data.main.official_interval_seconds,'900');
assert.equal(stored.data.main.probe_dns_server,'192.0.2.53');
assert.equal(stored.data.main.worker_url,'untouched');
assert.equal(stored.data.b2.slot,'1');
assert.equal(stored.data.b.token,'pgnfw_fixture_b');

// Old logs and new binding IDs both follow saved target/WAN ordering.
const legacy=['a1','b1','a2','b2'].map(id=>{
 const row=initial[id];
 return `entry_target=${row.target}\nentry_wan=${row.wan}\nentry_slot=${row.slot}\nentry_status=success\nentry_current_ip=198.51.100.1\n`;
}).join('\n');
const oldRows=parseOfficialStatus(legacy).rows;
assert.equal(oldRows.length,4);
assert.deepEqual(orderedOfficialRows(oldRows).map(row=>`${row.target}/${row.wan}`),['b/wan2','b/wan1','a/wan1','a/wan2']);
assert.equal(orderedOfficialRows(oldRows)[0].label,'乙改名');
assert.equal(orderedOfficialRows(oldRows)[0].status,'success');
const current=parseOfficialStatus('entry_binding=b2\nentry_target=b\nentry_wan=wan2\nentry_slot=1\nentry_status=success\n\n').rows;
assert.equal(current.length,1,'binding ID must not split a result');
assert.equal(current[0].binding,'b2');
assert.equal(orderedOfficialRows(current)[0].status,'success');
stored.set(configName,'b2','slot','4');
assert.equal(orderedOfficialRows(current)[0].status,'unknown','changed slot must not reuse old success');
stored.set(configName,'b2','slot','1');
assert.equal(orderedOfficialRows([{...current[0],binding:'different'}])[0].status,'unknown');
assert.equal(orderedOfficialRows([])[0].status,'unknown');
stored.set(configName,'b2','enabled','0');
assert.equal(orderedOfficialRows(oldRows)[0].enabled,false);

// Add/remove preserves the remaining order; deleted results are not shown.
draft.remove(configName,'a2');
draft.add(configName,'official_target','c');
draft.set(configName,'c','label','丙');
draft.set(configName,'c','token','pgnfw_fixture_c');
draft.add(configName,'official_binding','c1');
draft.set(configName,'c1','target','c');
draft.set(configName,'c1','wan','wan1');
draft.set(configName,'c1','slot','3');
await persist(map);
assert.deepEqual(ids(stored.sections(configName,'official_binding')),['b2','b1','a1','c1']);
assert.equal(orderedOfficialRows(oldRows).length,4);
assert.equal(orderedOfficialRows(oldRows)[3].status,'unknown');
assert.ok(!source.includes('po0SaveChannel'));
assert.ok(!source.includes('_network_save'));
await runAction({po0Saving:true},'official','official-report');
assert.equal(calls.length,3,'apply and manual report cannot be started together');
console.log('OpenWrt target/WAN order, cache alignment and unified configuration persistence passed.');

// Exercise the actual table controls, grouping and drop handlers with a small DOM.
function element(tag, attrs = {}, children = []) {
 const node = {
  tag, attrs, children: [], handlers: {}, offsetHeight: 40,
  get firstChild() {return this.children[0];},
  getAttribute(key) {return this.attrs[key];},
  appendChild(child) {this.children.push(child); if(typeof child==='object') child.parentNode=this; return child;},
  insertBefore(child, before) {const i=this.children.indexOf(before); this.children.splice(i<0?this.children.length:i,0,child); child.parentNode=this;},
  addEventListener(name, handler) {this.handlers[name]=handler;},
  getBoundingClientRect() {return {top:0};},
  classList: {values:new Set(),add(...names){names.forEach(n=>this.values.add(n));},remove(...names){names.forEach(n=>this.values.delete(n));},contains(n){return this.values.has(n);}}
 };
 children.forEach(child=>node.appendChild(child));
 return node;
}
const formFixture = {TableSection:{extend: spec=>spec,prototype:{
 renderRowActions() {return element('td',{},[element('div',{},[element('button',{},['删除'])])]);},
 renderContents(ids) {
  const rows=ids.map(id=>element('tr',{'data-sid':id},[element('td'),element('td')]));
  const root=element('tbody',{},rows);
  root.querySelectorAll=()=>rows;
  return root;
 }
}}};
const tableSpec=Function('form','E','orderedBindings','moveReporterRow','renderOfficialStatus','showActionResult','_',
 'var lastOfficialResult="";'+source.slice(source.indexOf('var OrderedTableSection'),source.indexOf('function persistReporterConfig'))+';return OrderedTableSection;')(
 formFixture,element,orderedBindings,moveReporterRow,()=>{},()=>{},globalThis._);
const local=store(initial);
let localSaves=0;
const tableMap={config:configName,data:local,async save(callback){localSaves++; if(callback) callback();}};
const table=Object.assign(Object.create(tableSpec),{map:tableMap,sectiontype:'official_binding'});
assert.deepEqual(table.cfgsections(),['a1','a2','b1','b2']);
let buttons=table.renderRowActions('a1').firstChild.firstChild.children;
assert.equal(buttons[1].attrs.disabled,true,'first WAN cannot move up');
assert.equal(buttons[2].attrs.disabled,null,'first WAN can move down within its target');
await buttons[2].attrs.click();
assert.deepEqual(table.cfgsections(),['a2','a1','b1','b2']);
assert.equal(localSaves,1);
buttons=table.renderRowActions('a1').firstChild.firstChild.children;
assert.equal(buttons[2].attrs.disabled,true,'last WAN cannot move into next target');
let rendered=table.renderContents(table.cfgsections(),[]);
assert.deepEqual(rendered.children.filter(row=>row.attrs.class==='po0-wan-group').map(row=>row.firstChild.firstChild),['甲','乙']);
const first=rendered.children.find(row=>row.attrs['data-sid']==='a2');
buttons[0].attrs.dragstart({dataTransfer:{setData(){}}});
first.handlers.dragover({clientY:1,preventDefault(){}});
assert.equal(first.classList.contains('po0-drop-before'),true);
first.handlers.drop({preventDefault(){}});
await new Promise(resolve=>setImmediate(resolve));
assert.deepEqual(table.cfgsections(),['a1','a2','b1','b2']);
assert.equal(localSaves,2);
table.draggedRow='a1';
const other=rendered.children.find(row=>row.attrs['data-sid']==='b1');
other.handlers.drop({preventDefault(){}});
assert.equal(localSaves,2,'cross-target drop must not save or move');
tableMap.readonly=true;
await table.moveRow('a1','a2',true);
assert.equal(localSaves,2,'read-only table cannot move');
assert.deepEqual(ids(stored.sections(configName,'official_target')),['b','a','c'],'draft table operations must not persist');
console.log('OpenWrt table arrows, drag/drop, target grouping and draft-only edits passed.');

// Both result formats retain expanded quotas, counts and fixed-slot labels.
for(const limit of [5,6,10]) {
 const ips=Array.from({length:limit},(_,i)=>'192.0.2.'+i+'/24');
 const row={target:'expanded',wan:'wan1',slot:String(limit-1),limit,used:limit,whitelist:ips};
 const json=parseOfficialStatus(JSON.stringify({entries:[row]})).rows[0];
 const text=parseOfficialStatus('entry_target=expanded\nentry_wan=wan1\nentry_slot='+row.slot+'\nentry_limit='+limit+'\nentry_used='+limit+'\nentry_whitelist='+ips.join(';')+'\n').rows[0];
 for(const result of [json,text]) {
  assert.equal(result.limit,limit);
  assert.equal(result.used,limit);
  assert.equal(result.whitelist.length,limit);
 }
}
assert.equal(parseOfficialStatus('entry_target=unknown\n').rows[0].limit,0);
assert.equal(normalizeToken('https://124.221.69.228/api/firewall/pgnfw_example/add?slot=9'),'pgnfw_example');
assert.match(source,/slot <= 10/);
console.log('OpenWrt expanded quota JSON/text results and ten slot choices passed.');
