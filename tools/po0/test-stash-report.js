"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const clientDir = path.join(__dirname, "..", "..", "scripts", "po0", "nftables", "clients", "stash");
const scriptPath = path.join(clientDir, "po0-firewall.js");
const overridePath = path.join(clientDir, "PO0-Firewall.stoverride");
const sshOverridePath = path.join(clientDir, "PO0.SSH-Report.PoC.stoverride");
const source = fs.readFileSync(scriptPath, "utf8");
const override = fs.readFileSync(overridePath, "utf8");

const STORE_KEY = "proxyconfig.po0.stash-report.v1";
const RUN_LOCK_KEY = STORE_KEY + ".run-lock";
const FIREWALL_KEY = "PO0_FIREWALL_TOKENS";
const OFFICIAL_URL = "https://124.221.69.228/api/firewall";

function futureWorkerResponse(now = Date.now()) {
  return {
    ok: true,
    source_id: "iphone-stash",
    accepted_cidr: "8.8.8.8/32",
    accepted_at: new Date(now - 1_000).toISOString(),
    expires_at: new Date(now + 12 * 60 * 60 * 1000).toISOString(),
    targets: [{ name: "po0", ok: true }],
  };
}

function officialBody(whitelist, currentIp = "8.8.8.8/24") {
  return { enabled: true, currentIp, limit: 5, whitelist };
}

function reportArgument(mode, extra) {
  return JSON.stringify(Object.assign({
    mode,
    worker_url: "",
    source_id: "",
    secret: "",
  }, extra || {}));
}

function execute(options = {}) {
  return new Promise((resolve, reject) => {
    const store = options.store instanceof Map
      ? options.store
      : new Map(Object.entries(options.store || {}));
    const requests = [];
    const notifications = [];
    const logs = [];
    const diagnostics = [];
    const officialGets = (options.officialGets || []).slice();
    const officialPosts = (options.officialPosts || []).slice();
    let doneCalls = 0, writes = 0;
    const timeout = setTimeout(() => reject(new Error("PO0 Stash script test timed out")), 2_000);

    function invokeSpec(spec, fallback) {
      const reply = spec || {};
      if (reply.error) return { error: reply.error };
      const body = reply.body === undefined ? fallback : reply.body;
      return {
        response: { status: reply.status || 200 },
        data: typeof body === "string" ? body : JSON.stringify(body),
      };
    }

    const httpClient = {
      get: (request, callback) => {
        requests.push({ method: "get", request });
        const isOfficial = String(request.url || "").includes("/api/firewall/");
        const spec = isOfficial ? (officialGets.shift() || {}) : null;
        const delayMs = isOfficial ? Math.max(0, Number(spec && spec.delayMs) || 0) : 0;
        const reply = () => {
          let result;
          if (isOfficial) {
            result = invokeSpec(spec, officialBody([]));
          } else if (String(request.url || "").includes("generate_204")) {
            const group = decodeURIComponent(request.headers['X-Stash-Selected-Proxy'] || '');
            const network = options.network || 'wifi';
            const probeArgs = JSON.parse(options.argument || '{}');
            const wifiGroup = probeArgs.PO0_PROBE_WIFI_GROUP || '📡 PO0 Wi-Fi 探测';
            const cellularGroup = probeArgs.PO0_PROBE_CELLULAR_GROUP || '📡 PO0 蜂窝探测';
            const blocked = group === wifiGroup ? network !== 'wifi' : group === cellularGroup ? network !== 'cellular' : false;
            result = blocked && network !== 'both' ? { error: 'mock blocked probe' } : { response: { status: 204 }, data: '' };
          } else {
            result = { response: { status: 200 }, data: JSON.stringify({ ip: "8.8.8.8" }) };
          }
          if (result.error) callback(result.error);
          else callback(null, result.response, result.data);
        };
        if (options.asyncHttp || delayMs > 0) setTimeout(reply, delayMs + (options.asyncHttp ? 5 : 0));
        else reply();
      },
      post: (request, callback) => {
        requests.push({ method: "post", request });
        const isOfficial = String(request.url || "").includes("/api/firewall/");
        const spec = isOfficial ? (officialPosts.shift() || {}) : null;
        const delayMs = isOfficial ? Math.max(0, Number(spec && spec.delayMs) || 0) : 0;
        const reply = () => {
          let result;
          if (isOfficial) {
            result = invokeSpec(spec, officialBody([{ ip: "8.8.8.8/24", slot: null }]));
          } else if (options.workerError) {
            result = { error: options.workerError };
          } else {
            result = { response: { status: 200 }, data: JSON.stringify(options.workerResponse || futureWorkerResponse()) };
          }
          if (result.error) callback(result.error);
          else callback(null, result.response, result.data);
        };
        if (options.asyncHttp || delayMs > 0) setTimeout(reply, delayMs + (options.asyncHttp ? 5 : 0));
        else reply();
      },
    };

    const context = {
      console: { log: (message) => logs.push(String(message)) },
      Date,
      Math,
      Number,
      String,
      Array,
      Object,
      Promise,
      JSON,
      setTimeout,
      clearTimeout,
      $argument: options.argument === undefined ? JSON.stringify({
        mode: options.mode || "auto",
        worker_url: "https://report.example.com/stash-report/v1",
        source_id: "iphone-stash",
        secret: "worker-secret",
        selected_proxy: "DIRECT",
      }) : options.argument,
      $script: { type: options.scriptType || "cron" },
      $persistentStore: {
        read: (key) => store.has(key) ? store.get(key) : null,
        write: (value, key) => {
          writes += 1;
          if (options.writeError) throw new Error("persistent store unavailable");
          store.set(key, value);
          return true;
        },
      },
      $notification: {
        post: (title, subtitle, content) => notifications.push({ title, subtitle, content }),
      },
      $httpClient: httpClient,
      $done: (value) => {
        doneCalls += 1;
        if (doneCalls > 1) {
          clearTimeout(timeout);
          reject(new Error("$done called more than once"));
          return;
        }
        if (typeof options.onDone === "function") options.onDone(store, value);
        clearTimeout(timeout);
        resolve({ store, requests, diagnostics, notifications, logs, doneCalls, writes, value });
      },
    };

    if (Object.hasOwn(options, "networkInfo")) {
      context.$httpAPI = async (method, path) => {
        diagnostics.push([method, path]);
        if (options.networkInfo instanceof Error) throw options.networkInfo;
        return options.networkInfo;
      };
    }
    try {
      vm.runInNewContext(source, context, { filename: "po0-firewall.js" });
    } catch (error) {
      clearTimeout(timeout);
      reject(error);
    }
  });
}

async function testOfficialGetFirstAndFixedSlot() {
  const token = "pgnfw_stash_fixture";
  const result = await execute({
    argument: reportArgument("force"),
    store: { [FIREWALL_KEY]: token + "@3" },
    officialGets: [{ body: officialBody([{ ip: "1.1.1.1/24", slot: 0 }]) }],
    officialPosts: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: 3 }]) }],
  });
  assert.deepStrictEqual(result.requests.map((entry) => entry.method), ["get", "post"]);
  const officialGet = result.requests[0].request;
  const officialPost = result.requests[1].request;
  assert.strictEqual(officialGet.url, OFFICIAL_URL + "/" + token);
  assert.strictEqual(officialGet.headers["X-Stash-Selected-Proxy"], "DIRECT");
  assert.ok(officialPost.url.endsWith("/add?slot=3"));
  assert.strictEqual(officialPost.headers["X-Stash-Selected-Proxy"], "DIRECT");
  const state = JSON.parse(result.store.get(STORE_KEY));
  assert.strictEqual(state.official.accounts[0].fixed_slot, 3);
  assert.strictEqual(state.official.accounts[0].current, "8.8.8.8/24");
  assert.ok(!JSON.stringify(state).includes(token));
}

async function testHitAndGetFailureNeverPost() {
  const token = "pgnfw_stash_readonly";
  const hit = await execute({
    argument: reportArgument("force"),
    store: { [FIREWALL_KEY]: token + "@2" },
    officialGets: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: 2 }]) }],
  });
  assert.deepStrictEqual(hit.requests.map((entry) => entry.method), ["get"]);
  assert.ok(!hit.requests.some((entry) => entry.method === "post"));

  const failed = await execute({
    argument: reportArgument("force"),
    store: { [FIREWALL_KEY]: token },
    officialGets: [{ status: 503, body: "upstream unavailable" }],
  });
  assert.deepStrictEqual(failed.requests.map((entry) => entry.method), ["get"]);
  assert.ok(!failed.requests.some((entry) => entry.method === "post"));
  assert.ok(!failed.logs.join("\n").includes(token));
  assert.ok(!failed.notifications.map((item) => item.content).join("\n").includes(token));
}

async function testStatusMissingIsSuccessAndReadOnly() {
  const token = "pgnfw_stash_status";
  const result = await execute({
    argument: reportArgument("status"),
    scriptType: "request",
    store: { [FIREWALL_KEY]: token },
    officialGets: [{ body: officialBody([{ ip: "1.1.1.1/24", slot: null }]) }],
  });
  assert.deepStrictEqual(result.requests.map((entry) => entry.method), ["get"]);
  assert.ok(!result.requests.some((entry) => entry.method === "post"));
  const state = JSON.parse(result.store.get(STORE_KEY));
  assert.strictEqual(state.official.accounts[0].status, "missing");
  assert.strictEqual(state.official.accounts[0].used, 1);
  assert.strictEqual(result.value.response.status, 200, "合法 missing status must be a successful read-only response");
  assert.match(result.value.response.body, /均未放行/);
  assert.match(result.value.response.body, /只读查询/);
}

async function testStrictDuplicateSlotsAndTokenPersistence() {
  const token = "pgnfw_stash_bad_slots";
  const result = await execute({
    argument: reportArgument("force", { PO0_FIREWALL_TOKENS: token }),
    officialGets: [{ body: officialBody([{ ip: "1.1.1.1/24", slot: 0 }, { ip: "2.2.2.2/24", slot: 0 }]) }],
  });
  assert.strictEqual(JSON.parse(result.store.get(STORE_KEY + ".official-config")).tokens, token);
  assert.deepStrictEqual(result.requests.map((entry) => entry.method), ["get"]);
  assert.ok(!result.requests.some((entry) => entry.method === "post"));
  assert.ok(!JSON.stringify(result.store.get(STORE_KEY)).includes(token));

  const invalid = await execute({
    argument: reportArgument("force", { PO0_FIREWALL_TOKENS: "bad-token" }),
  });
   assert.deepStrictEqual(invalid.requests.map((entry) => entry.method), []);
  assert.ok(!invalid.logs.join("\n").includes("bad-token"));

  const cleared = await execute({
    argument: reportArgument("clear-official", { PO0_FIREWALL_TOKENS: "-" }),
    store: { [FIREWALL_KEY]: token },
  });
  assert.strictEqual(JSON.parse(cleared.store.get(STORE_KEY + ".official-config")).tokens, "");
  assert.deepStrictEqual(cleared.requests, []);
}

async function testSameTokenDifferentSlotsFailClosed() {
  const token = "pgnfw_stash_same_account";
  const result = await execute({
    argument: reportArgument("force", { PO0_FIREWALL_TOKENS: token + "@0," + token + "@1" }),
  });
  assert.deepStrictEqual(result.requests, [], "the same official account must not run concurrently through different slots");
  assert.ok(!result.logs.join("\n").includes(token));
  assert.ok(!result.notifications.map((item) => item.content).join("\n").includes(token));
}

async function testPartialOfficialAccountsContinue() {
  const first = "pgnfw_stash_partial_one";
  const second = "pgnfw_stash_partial_two";
  const result = await execute({
    argument: reportArgument("force"),
    store: { [FIREWALL_KEY]: first + "," + second },
    officialGets: [
      { status: 503, body: "temporary failure" },
      { body: officialBody([{ ip: "1.1.1.1/24", slot: null }]) },
    ],
    officialPosts: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: null }]) }],
  });
  assert.deepStrictEqual(result.requests.map((entry) => entry.method), ["get", "get", "post"]);
  assert.strictEqual(result.requests[0].request.url, OFFICIAL_URL + "/" + first);
  assert.strictEqual(result.requests[1].request.url, OFFICIAL_URL + "/" + second);
  assert.strictEqual(result.requests[2].request.url, OFFICIAL_URL + "/" + second + "/add");
  const state = JSON.parse(result.store.get(STORE_KEY));
  assert.strictEqual(state.official.accounts[0].status, "error");
  assert.strictEqual(state.official.accounts[1].status, "ok");
  assert.strictEqual(result.value.response.status, 502);
}

async function testPersistentLockWriteFailureFailsClosed() {
  const token = "pgnfw_stash_lock_store_failure";
  const result = await execute({
    argument: reportArgument("force"),
    store: { [FIREWALL_KEY]: token },
    writeError: true,
    officialGets: [{ body: officialBody([]) }],
    officialPosts: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: null }]) }],
  });
  assert.deepStrictEqual(result.requests, [], "a failed lock write must block all network reports");
}

function testLocalSlotSurvivesSync() {
  const store = new Map();
  const sandbox = {
    $persistentStore: { read: key => store.has(key) ? store.get(key) : null, write: (value, key) => { store.set(key, value); return true; } },
  };
  vm.createContext(sandbox);
  const start = source.indexOf('function channelSettings(');
  const end = source.indexOf('function parseFirewallTokens(');
  const parseEnd = source.indexOf('\nfunction ', end + 10);
  const intervalStart = source.indexOf('function reportInterval(');
  const intervalEnd = source.indexOf('\nfunction ', intervalStart + 10);
  const functions = source.slice(start, parseEnd) + source.slice(intervalStart, intervalEnd);
  const prefix = `const STORE_ID = 'device-test'; const LEGACY_ID = 'PO0_FIREWALL_TOKENS'; const MAX_ID = 16;`;
  const renamed = functions.replaceAll('STORE_KEY', 'STORE_ID').replaceAll('FIREWALL_TOKENS_KEY', 'LEGACY_ID').replaceAll('MAX_FIREWALL_TOKENS', 'MAX_ID');
  vm.runInContext(prefix + `
    function readStore(k) { return $persistentStore.read(k); }
    function readJSON(k,fallback) { return JSON.parse(readStore(k) || "null") || fallback; }
    function writeJSON(k,v) { return $persistentStore.write(JSON.stringify(v),k); }
    function firstNonEmpty(v) { return v.find(x => x !== null && x !== undefined && String(x).trim()) || ''; }
  ` + renamed, sandbox);
  vm.runInContext("saveLocalFirewall({PO0_FIREWALL_TOKENS:'pgnfw_this_device@0'}, false)", sandbox);
  assert.equal(vm.runInContext("firewallRawValue({PO0_FIREWALL_TOKENS:'pgnfw_synced_device@4'})", sandbox), 'pgnfw_this_device@0');
  vm.runInContext("saveLocalFirewall({}, true)", sandbox);
  assert.equal(vm.runInContext("firewallRawValue({PO0_FIREWALL_TOKENS:'pgnfw_synced_device@4'})", sandbox), '');
}

async function testFlexibleOfficialSeparators() {
  const saved = await execute({ argument: JSON.stringify({ mode: 'save-official', PO0_FIREWALL_TOKENS: ' ,pgnfw_a@0 pgnfw_b@1\npgnfw_c@2; pgnfw_d@3，pgnfw_e@4；pgnfw_f, ' }) });
  assert.equal(saved.requests.length, 0);
  const config = JSON.parse(saved.store.get(STORE_KEY + '.official-config'));
  assert.ok(config.tokens.includes('pgnfw_f'));
  const status = await execute({ argument: JSON.stringify({ mode: 'status' }), store: saved.store });
  assert.equal(status.requests.filter(x => x.request.url.includes('/api/firewall/')).length, 6);
  assert.ok(status.requests.every(x => x.method === 'get'));
}

async function testOfficialNetworkTargets() {
  const store = new Map();
  const token = 'pgnfw_network_fixture';
  const call = async (args, network = 'wifi', extra = {}) => { const result = await execute(Object.assign({ store, argument: JSON.stringify(args), network, ssid: network === 'cellular' ? 'cellular' : network === 'unknown' ? '' : 'Cafe-WiFi' }, extra)); await new Promise(resolve => setImmediate(resolve)); return result; };
  const posts = result => result.requests.filter(x => x.method === 'post' && x.request.url.includes('/api/firewall/'));
  const officialRequests = result => result.requests.filter(x => x.request.url.includes('/api/firewall/'));
  const save = { mode: 'save-official', PO0_FIREWALL_TOKENS: token + '@1', PO0_FIREWALL_WIFI_TOKENS: token, PO0_FIREWALL_WIFI_NAMES: 'Wi-Fi 自填名称', OFFICIAL_NETWORK_TARGETS_ENABLED: true };
  let result = await call(save);
  assert.equal(result.requests.length, 0, 'saving network targets must stay offline');
  const snapshot = store.get(STORE_KEY + '.official-config');
  assert.equal(JSON.parse(snapshot).networkTargetsEnabled, true);
  const groupHeaders = result => result.requests.filter(x => x.request.url.includes('generate_204')).map(x => decodeURIComponent(x.request.headers['X-Stash-Selected-Proxy']));
  result = await call({mode:'auto', channel:'official', trigger:'network'}, 'cellular', {officialPosts:[{body:officialBody([{ip:'8.8.8.8/24',slot:1}])}]});
  assert.deepEqual(groupHeaders(result), ['📡 PO0 Wi-Fi 探测', '📡 PO0 蜂窝探测'], 'old configurations retain both original probe names');
  assert(posts(result)[0].request.url.endsWith('/add?slot=1'), 'cellular must use the original user slot');
  result = await call({mode:'auto', channel:'official', trigger:'network', PO0_FIREWALL_WIFI_TOKENS:'pgnfw_synced_other@4'});
  assert(posts(result)[0].request.url.endsWith('/add'), 'Wi-Fi uses the saved unslotted target exactly');
  assert.equal(JSON.parse(store.get(STORE_KEY)).official.accounts[0].name, 'Wi-Fi 自填名称');
  assert.equal(store.get(STORE_KEY + '.official-config'), snapshot, 'sync cannot change saved network settings');
  result = await call({mode:'auto', channel:'official'});
  assert.deepEqual(result.requests, [], 'a cron tick before the deadline must stay offline even with network-specific targets');
  result = await call({mode:'auto', channel:'official', trigger:'network'}, 'cellular', {officialPosts:[{body:officialBody([{ip:'8.8.8.8/24',slot:1}])}]});
  assert(posts(result)[0].request.url.endsWith('/add?slot=1'), 'switching back must not reuse Wi-Fi due cache');
  result = await call({mode:'status'});
  assert.equal(posts(result).length, 0, 'network-selected status stays read-only');
  result = await call({mode:'auto', channel:'official'});
  assert(posts(result).length, 'read-only on a new network cannot suppress its next report');
  result = await call({mode:'force', channel:'official'}, 'unknown');
  assert.equal(officialRequests(result).length, 0, 'unknown network must not select either official list');
  result = await call({mode:'force', channel:'official'}, 'both');
  assert.equal(officialRequests(result).length, 0, 'ambiguous complementary probes must not select a target');
  const plainGroups = {PO0_PROBE_WIFI_GROUP:'PO0 Wi-Fi 探测', PO0_PROBE_CELLULAR_GROUP:'PO0 蜂窝探测'};
  result = await call({mode:'status', ...plainGroups}, 'wifi');
  assert.deepEqual(groupHeaders(result), ['PO0 Wi-Fi 探测', 'PO0 蜂窝探测'], 'new configurations explicitly bind the renamed probes');
  assert(officialRequests(result).length > 0 && posts(result).length === 0, 'renamed Wi-Fi probes keep official status read-only');
  result = await call({mode:'force', channel:'official', ...plainGroups}, 'cellular', {officialPosts:[{body:officialBody([{ip:'8.8.8.8/24',slot:1}])}]});
  assert(posts(result)[0].request.url.endsWith('/add?slot=1'), 'renamed cellular probes preserve the original slot');
  for (const network of ['unknown','both']) {
    result = await call({mode:'force', channel:'official', ...plainGroups}, network);
    assert.equal(officialRequests(result).length, 0, 'renamed uncertain probes must retain the existing fail-closed behavior');
  }
  await call(Object.assign({},save,{PO0_FIREWALL_WIFI_TOKENS:token+'@4'}));
  result = await call({mode:'force', channel:'official'}, 'wifi', {officialPosts:[{body:officialBody([{ip:'8.8.8.8/24',slot:4}])}]});
  assert(posts(result)[0].request.url.endsWith('/add?slot=4'), 'Wi-Fi fixed slot must never be stripped');
  const valid = store.get(STORE_KEY + '.official-config');
  result = await call(Object.assign({},save,{PO0_FIREWALL_WIFI_TOKENS:token+'@2,'+token+'@3'}));
  assert.equal(result.requests.length, 0);
  assert.equal(store.get(STORE_KEY + '.official-config'), valid, 'invalid list must not overwrite saved config');
  await call({mode:'save-official', OFFICIAL_NETWORK_TARGETS_ENABLED:false});
  result = await call({mode:'force', channel:'official'}, 'wifi', {officialPosts:[{body:officialBody([{ip:'8.8.8.8/24',slot:1}])}]});
  assert(posts(result)[0].request.url.endsWith('/add?slot=1'), 'disabled switch restores original behavior');
  assert.equal(JSON.parse(store.get(STORE_KEY + '.official-config')).wifiTokens, token+'@4', 'disable retains Wi-Fi configuration');
  await call(save);
  const seconds = Math.floor(Date.now()/1000);
  store.set(STORE_KEY, JSON.stringify({ip:'8.8.8.8', detected_ip:'8.8.8.8', network:'wifi', context:'wifi:Cafe-WiFi', accepted_at:seconds, expires_at:seconds+43200, next_refresh_at:seconds+600, official:{network:'cellular',last_attempt_at:seconds}}));
  result = await call({mode:'auto', trigger:'network', worker_url:'https://report.example.com/stash-report/v1', secret:'worker-fixture', token:'worker-fixture', source_id:'phone'});
  assert(posts(result).length, 'official selection change checks its new target');
  assert.equal(result.requests.filter(x=>x.method==='post'&&!x.request.url.includes('/api/firewall/')).length,0,'official network selection must not force a cached self-report');
  await call(Object.assign({},save,{PO0_FIREWALL_WIFI_TOKENS:'pgnfw_second@2,'+token,PO0_FIREWALL_WIFI_NAMES:'第二个;第一个'}));
  await call({mode:'save-official',PO0_FIREWALL_WIFI_TOKENS:token+',pgnfw_second@2'});
  assert.equal(JSON.parse(store.get(STORE_KEY+'.official-config')).wifiNames,'第一个;第二个','Wi-Fi names follow account identity on reorder');
  await call({mode:'clear-official'});
  const cleared = JSON.parse(store.get(STORE_KEY + '.official-config'));
  assert.equal(cleared.tokens, '');
  assert.equal(cleared.wifiTokens, undefined);
  result = await call({mode:'force', PO0_FIREWALL_TOKENS:token, OFFICIAL_NETWORK_TARGETS_ENABLED:true, PO0_FIREWALL_WIFI_TOKENS:token+'@2'});
  assert.equal(officialRequests(result).length, 0, 'clear cannot be undone by synced parameters');
}

async function testRetirementMigration() {
  const token = 'pgnfw_retirement_fixture';
  const official = JSON.stringify({ version: 1, tokens: token + '@2' });
  const legacy = JSON.stringify({version:1,values:{worker_url:'http://invalid',secret:'retired-secret'}});
  const store = new Map([[STORE_KEY+'.official-config',official],[STORE_KEY+'.worker-config',legacy],[STORE_KEY+'.channel-settings',JSON.stringify({version:1,workerAutoEnabled:true,officialAutoEnabled:true,officialNames:'保留名称',officialIntervalSeconds:1200,officialTimerEnabled:false})],[STORE_KEY,JSON.stringify({expires_at:9999999999,accepted_at:123,ip:'old worker address'})]]);
  const result = await execute({store,argument:JSON.stringify({mode:'force',worker_url:'http://invalid',secret:'retired-secret'}),ssid:'cellular',officialPosts:[{body:officialBody([{ip:'8.8.8.8/24',slot:2}])}]});
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(store.get(STORE_KEY+'.official-config'),official,'official token/slot bytes preserved');
  const settings=JSON.parse(store.get(STORE_KEY+'.channel-settings'));
  assert.equal(settings.officialNames,'保留名称'); assert.equal(settings.officialIntervalSeconds,1200); assert.equal(settings.officialTimerEnabled,false);
  assert.equal(settings.workerAutoEnabled,undefined);
  assert.equal(JSON.parse(store.get(STORE_KEY+'.pre-retirement-v1')).worker,legacy,'raw legacy asset backed up locally');
  assert.equal(JSON.parse(store.get(STORE_KEY)).expires_at,undefined,'no old expiry in active state');
  assert(result.requests.length>0); assert(result.requests.every(x=>!x.request.url.includes('/stash-report/')&&!x.request.url.includes('invalid')));
  const backup=store.get(STORE_KEY+'.pre-retirement-v1');
  const retired=await execute({store,argument:JSON.stringify({mode:'force',channel:'worker'}),ssid:'cellular'});
  assert.equal(retired.requests.length,0,'explicit retired action cannot trigger official');
  assert.equal(store.get(STORE_KEY+'.pre-retirement-v1'),backup,'backup is immutable');
  await execute({store,argument:JSON.stringify({mode:'clear-official'})});
  const cleared=await execute({store,argument:JSON.stringify({mode:'force',PO0_FIREWALL_TOKENS:token}),ssid:'cellular'});
  assert.equal(cleared.requests.length,0,'clear remains a tombstone against synchronized arguments');
}

function routeArgument(route) {
  const url = 'http://po0-report.invalid/' + route;
  const blocks = override.split(/^    - match: /m).slice(1);
  const matches = blocks.filter(block => new RegExp(block.split('\n')[0].trim()).test(url));
  assert.equal(matches.length, 1, 'one HTTP route must handle ' + route);
  assert.match(matches[0], /name: po0-stash-report-worker-v2/);
  const argument = /^      argument: '(.*)'$/m.exec(matches[0]);
  assert(argument, 'route must supply an argument: ' + route);
  return JSON.parse(argument[1]);
}

async function testStandardEntrypointsAndLegacyRoutes() {
  const normalize = text => text.replace(/\r\n?/g, '\n');
  assert.equal(normalize(fs.readFileSync(path.join(clientDir, 'po0-stash-report.js'), 'utf8')), normalize(source));
  assert.equal(normalize(fs.readFileSync(path.join(clientDir, 'PO0.LAN-Report.stoverride'), 'utf8')), normalize(override));
  assert.match(override, /^name: PO0 防火墙$/m);
  assert.match(override, /stash\/po0-firewall\.js\?rev=20261126-panel/);
  assert.match(override, /^  po0-stash-report-worker-v2:$/m);
  for (const route of ['report', 'official-now', 'report-now', 'official-force']) {
    const token = 'pgnfw_legacy_route_fixture';
    const result = await execute({ argument: JSON.stringify(routeArgument(route)), scriptType: 'request', store: { [FIREWALL_KEY]: token + '@2' }, officialGets: [{ body: officialBody([{ ip: '8.8.8.8/24', slot: 2 }]) }] });
    assert.deepEqual(result.requests.map(item => item.method), ['get'], route + ' must use the official engine');
    assert.equal(result.value.response.status, 200);
    assert.equal(JSON.parse(result.store.get(STORE_KEY)).official.accounts[0].fixed_slot, 2);
    assert.match(result.value.response.body, /<title>PO0 防火墙 · /);
    assert.equal((result.value.response.body.match(/>立即上报<\/a>/g) || []).length, 1);
    assert.equal((result.value.response.body.match(/>强制上报<\/a>/g) || []).length, 1);
  }
}

async function testNativeNetworkAndSsid() {
  const store = new Map();
  const cell = "pgnfw_test_cell", wifi = "pgnfw_test_wifi";
  const hit = officialBody([{ip: "8.8.8.42/24", slot: 3}]);
  const methods = result => result.requests.map(r => r.method);
  const state = () => JSON.parse(store.get(STORE_KEY));
  const save = values => execute({store, argument: reportArgument("save-official", values)});
  const run = (mode, info, extra = {}) => execute({store, scriptType: mode === "auto" ? "event" : "request",
    argument: reportArgument(mode, mode === "auto" ? {trigger: "network"} : {}), networkInfo: info,
    officialGets: [{body: hit}], ...extra});
  await save({PO0_FIREWALL_TOKENS: cell + "@1|Mobile SIM", PO0_FIREWALL_WIFI_TOKENS: wifi + "@3|Wi-Fi Line",
    SKIP_WIFI_SSIDS: " Primary ; Private WiFi ", OFFICIAL_NETWORK_TARGETS_ENABLED: true});
  const checkRead = (result, token, name, slot) => {
    assert.deepEqual(result.diagnostics, [["GET", "/diagnosis/network"]]);
    assert.deepEqual(result.requests.map(r => [r.method, r.request.url]), [["get", OFFICIAL_URL + "/" + token]]);
    const account = state().official.accounts[0];
    assert.deepEqual([account.name, account.fixed_slot], [name, slot]);
  };

  const cellular = await run("auto", {interface: "cellular", ssid: "Private WiFi"});
  checkRead(cellular, cell, "Mobile SIM", 1);
  const cached = state().official;
  const protectedWifi = {interface: "wifi", ssid: "Private WiFi"};
  for (const mode of ["auto", "report"]) {
    const skip = await run(mode, protectedWifi);
    assert.deepEqual(methods(skip), []);
    assert.deepEqual(skip.notifications, []);
    assert.deepEqual(state().official, cached);
    assert.equal(state().notice, "Wi-Fi 已跳过");
    assert(!JSON.stringify([state(), skip.logs, skip.notifications, skip.value]).includes(protectedWifi.ssid));
  }
  const recent = await run("recent", protectedWifi);
  assert.match(recent.value.response.body, /Wi-Fi 已跳过.*上次检查.*蜂窝/);
  assert.deepEqual(recent.diagnostics, []);
  const idle = await execute({store, scriptType: 'cron', argument: reportArgument('auto'), networkInfo: {interface: 'cellular'}});
  assert.deepEqual(methods(idle), []);
  assert.equal(state().notice, 'Wi-Fi 已跳过', 'an idle tick does not confirm the previous whitelist again');
  checkRead(await run("force", protectedWifi), wifi, "Wi-Fi Line", 3);
  const readonly = await run("status", protectedWifi, {officialGets: [{body: officialBody([])}]});
  checkRead(readonly, wifi, "Wi-Fi Line", 3);
  assert.equal(state().official.accounts[0].status, "missing");
  assert.equal(state().notice, undefined);

  for (const ssid of ["PRIVATE WIFI", "Private WiFi guest", "", "<redacted>", null]) {
    checkRead(await run("auto", {interface: "wifi", ssid}), wifi, "Wi-Fi Line", 3);
  }
  for (const info of [{interface: "wired"}, new Error("local API unavailable")]) {
    const unknown = await run("force", info);
    assert.deepEqual(methods(unknown), []);
    assert.equal(state().notice, "网络类型未知");
  }
  // A missed network event cannot make a due Wi-Fi check wait on the cellular clock.
  await run("auto", {interface: "cellular"});
  const cron = info => run("auto", info, {scriptType: "cron", argument: reportArgument("auto")});
  checkRead(await cron({interface: "wifi", ssid: "Other"}), wifi, "Wi-Fi Line", 3);
  assert.deepEqual(methods(await cron({interface: "wifi", ssid: "Other"})), []);
  await save({OFFICIAL_NETWORK_TARGETS_ENABLED: false});
  assert.deepEqual(methods(await run("auto", protectedWifi)), []);
  checkRead(await run("auto", new Error("unavailable")), cell, "Mobile SIM", 1);
  assert.equal(state().official.network, "default");
  checkRead(await run("report", {interface: "wifi", ssid: "Other"}), cell, "Mobile SIM", 1);
  assert.equal(state().official.network, "wifi");
}

async function testSavedNotificationOptions() {
  const store = new Map();
  await execute({store, argument: reportArgument("save-official", {
    PO0_FIREWALL_TOKENS: "pgnfw_notify", NOTIFY_SUCCESS: true, NOTIFY_FAILURE: false,
  })});
  const hit = officialBody([{ip: "8.8.8.0/24", slot: null}]);
  for (const [mode, body, count] of [["report", hit, 1], ["auto", hit, 0], ["status", officialBody([]), 1]]) {
    const result = await execute({store, argument: reportArgument(mode, {trigger: "network"}), officialGets: [{body}]});
    assert.equal(result.notifications.length, count);
    if (count) assert.equal(result.notifications[0].subtitle, "检查完成");
  }
  const failed = await execute({store, argument: reportArgument("report"), officialGets: [{status: 503}]});
  assert.deepEqual(failed.notifications, []);
}

async function testSharedSubnetAndRejectedWrite() {
  const token = "pgnfw_test_shared";
  const row = slot => ({ip: "8.8.8.0/24", slot});
  const simulate = (gets, posts = [], targets = token + "@2") => execute({
    argument: reportArgument("report", {PO0_FIREWALL_TOKENS: targets}), officialGets: gets, officialPosts: posts,
  });
  const body = rows => ({body: officialBody(rows, "8.8.8.77/24")});
  const account = result => JSON.parse(result.store.get(STORE_KEY)).official.accounts[0];
  const methods = result => result.requests.map(r => r.method);
  for (const [rows, actual, targets] of [
    [[row(1)], 1], [[row(null)], null], [[row(1), row(2)], 2], [[row(1), row(null)], 1, token],
  ]) {
    const hit = await simulate([body(rows)], [], targets);
    assert.deepEqual(methods(hit), ["get"]);
    assert.deepEqual([account(hit).status, account(hit).covered_slot, account(hit).added], ["ok", actual, false]);
    assert.deepEqual(hit.notifications, []);
  }
  const denied = {status: 403};
  const race = await simulate([body([]), body([row(1)])], [denied]);
  assert.deepEqual(methods(race), ["get", "post", "get"]);
  assert.deepEqual([account(race).status, account(race).covered_slot, account(race).added], ["ok", 1, false]);
  assert.deepEqual(race.notifications, []);
  for (const [reads, writes, expected] of [
    [[body([]), body([])], [denied], ["get", "post", "get"]],
    [[body([]), {status: 500}], [denied], ["get", "post", "get"]],
    [[body([])], [{status: 500}], ["get", "post"]],
    [[denied], [], ["get"]],
  ]) {
    const failed = await simulate(reads, writes);
    assert.deepEqual(methods(failed), expected);
    assert.equal(account(failed).status, "error");
    assert.equal(failed.notifications.length, 1);
  }
}

async function testNetworkEvent() {
  const match = /^event:\n  script:\n    - name: po0-stash-report-worker-v2\n      event: network-changed\n      timeout: \d+\n      argument: '(.*)'$/m.exec(override);
  assert(match, "register the PO0 worker for Stash network changes");
  const argument = match[1];
  const store = new Map();
  await execute({store, argument: reportArgument("save-official", {PO0_FIREWALL_TOKENS: "pgnfw_event_test"})});
  await execute({store, argument: JSON.stringify({mode: "toggle-official-timer"})});
  const body = officialBody([{ip: "8.8.8.8/24", slot: null}]);
  const tick = () => execute({scriptType: "cron", argument: reportArgument("auto"), store, officialGets: [{body}]});
  assert.deepEqual((await tick()).requests, [], "disabled timer stays offline");
  await execute({store, argument: JSON.stringify({mode: "toggle-official-timer"})});
  const due = await tick();
  assert.deepEqual(due.requests.map(r => [r.method, r.request.url]), [["get", OFFICIAL_URL + "/pgnfw_event_test"]]);
  assert.deepEqual((await tick()).requests, [], "cron checks the deadline locally");
  await execute({store, argument: JSON.stringify({mode: "toggle-official-timer"})});
  const event = () => execute({scriptType: "event", argument, store, officialGets: [{body}]});
  const hit = await event();
  assert.deepEqual(hit.requests.map(r => [r.method, r.request.url]), [["get", OFFICIAL_URL + "/pgnfw_event_test"]]);
  const repair = await execute({scriptType: "event", argument, store, officialGets: [{body: officialBody([])}], officialPosts: [{body}]});
  assert.deepEqual(repair.requests.map(r => r.method), ["get", "post"]);
  await execute({store, argument: JSON.stringify({mode: "toggle-official"})});
  assert.deepEqual((await event()).requests, []);
}

function inlineTile(store) {
  const normalized = override.replace(/\r\n/g, '\n');
  assert.match(normalized, /^  - name: po0-stash-status-tile-v6\n    collapsed: true$/m);
  const block = /  po0-stash-status-tile-v6:\n    interval: \d+\n    payload: \|\n([\s\S]*?)(?=^\S)/m.exec(normalized);
  let tile, done = 0, sideEffects = 0;
  const unexpected = () => { sideEffects++; throw new Error('Tile must only read local storage'); };
  vm.runInNewContext(block[1].replace(/^      /gm, ''), {
    $persistentStore: { read: key => store.get(key) || null, write: unexpected },
    $httpAPI: unexpected, $httpClient: { get: unexpected, post: unexpected }, $notification: { post: unexpected },
    $done: value => { done++; tile = value; },
  });
  assert.equal(done, 1);
  assert.equal(sideEffects, 0);
  return tile;
}

async function testTileRemainsReadOnly() {
  const cached = (...statuses) => ({official: {accounts: statuses.map(status => ({status})), network: 'cellular'}});
  for (const [state, extra, expected, icon] of [
    [{}, {}, /^等待首次检查$/, 'shield'],
    [{notice: '尚未配置账号'}, {'.channel-settings': {version: 1, officialAutoEnabled: false}}, /^尚未配置账号$/, 'shield'],
    [cached('ok', 'ok'), {}, /^2\/2 个账号已放行 · 蜂窝$/, 'checkmark.shield.fill'],
    [cached('ok', 'error'), {}, /^1\/2 个账号已放行 · 1 个检查失败/, 'exclamationmark.shield.fill'],
    [cached('ok', 'missing'), {}, /1\/2 个账号已放行 · 1 个未放行/, 'exclamationmark.shield.fill'],
    [cached('error', 'error'), {}, /^2 个账号检查失败/, 'xmark.shield.fill'],
    [cached('missing'), {}, /^1 个账号未放行/, 'exclamationmark.shield.fill'],
    [cached('slot-mismatch'), {}, /尚未确认放行 · 1 个槽位不匹配/, 'exclamationmark.shield.fill'],
    [cached('future-status'), {}, /尚未确认放行 · 1 个待确认/, 'exclamationmark.shield.fill'],
    [{...cached('ok'), notice: 'Wi-Fi 已跳过'}, {}, /^Wi-Fi 已跳过 · 上次 1\/1 个账号已放行 · 蜂窝/, 'clock.fill'],
    [{notice: '网络类型未知'}, {}, /网络未知，已跳过 · 尚无上次结果/, 'clock.fill'],
    [cached('ok'), {'.channel-settings': {version: 1, officialAutoEnabled: false}}, /自动上报已停用 · 上次 1\/1/, 'pause.circle.fill'],
    [{...cached('ok'), last_error: 'failed before official checks', last_error_at: 300}, {}, /本次检查失败 · 上次 1\/1/, 'xmark.shield.fill'],
    [{official: {last_error: 'cached error'}}, {}, /^检查失败$/, 'xmark.shield.fill'],
  ]) {
    const store = new Map([[STORE_KEY, JSON.stringify(state)], [STORE_KEY + '.worker-config', 'legacy data awaiting migration']]);
    for (const [suffix, value] of Object.entries(extra)) store.set(STORE_KEY + suffix, JSON.stringify(value));
    const before = Array.from(store.entries());
    const tile = inlineTile(store);
    const old = await execute({scriptType: 'tile', store, networkInfo: {}, writeError: true, argument: reportArgument('force')});
    assert.deepEqual(JSON.parse(JSON.stringify(old.value)), JSON.parse(JSON.stringify(tile)));
    assert.equal(tile.title, 'PO0 防火墙 · 本机');
    assert.equal(tile.url, 'http://po0-report.invalid/recent');
    assert.equal(tile.icon, icon);
    assert.match(tile.content, expected);
    assert.equal(old.writes, 0);
    assert.deepEqual([old.requests, old.diagnostics, old.notifications], [[], [], []]);
    assert.deepEqual(Array.from(store.entries()), before);
  }
}

async function testCollapsedTileAccountDetails() {
  const official = { network: 'cellular', last_checked_at: 1700000000, accounts: [
    { name: '<公司>', status: 'ok', fixed_slot: 2, covered_slot: 1, used: 2, limit: 5, current: '192.0.2.3/24',
      whitelist: [{slot: 1, ip: '192.0.2.0/24'}, {slot: 3, ip: '203.0.113.0/24'}] },
    { name: '家里', status: 'ok', fixed_slot: 0, covered_slot: null, used: 1, limit: 10, current_ip: '198.51.100.0/24',
      whitelist: [{slot: null, ip: '198.51.100.0/24'}] },
    { name: '第三个', status: 'missing', fixed_slot: 0, used: 1, limit: 5, current: '203.0.113.0/24' },
    { name: '异常账号', status: 'error', used: 9, limit: 10, current: '192.0.2.250/24', last_error: 'HTTP 503 pgnfw_private_sample' },
    { status: 'slot-mismatch', fixed_slot: 1 },
    { name: '旧缓存', status: 'ok', fixed_slot: 1, used: 3, limit: 5 },
    { name: '本次添加', status: 'ok', fixed_slot: 0, added: true, current_exit: '203.0.113.1/24',
      used: 1, limit: 5, whitelist: [{slot: 0, ip: '203.0.113.0/24'}] },
  ] };
  const store = new Map([[STORE_KEY, JSON.stringify({ official, notice: 'Wi-Fi 已跳过' })],
    [STORE_KEY + '.worker-config', 'legacy data pending migration']]);
  const before = Array.from(store.entries());
  for (const mode of ['settings', 'recent']) {
    const result = await execute({store, scriptType: 'request', argument: JSON.stringify({mode}), networkInfo: {}});
    assert.deepEqual([result.requests, result.diagnostics, result.notifications], [[], [], []]);
    assert.equal(result.writes, 0, 'opening or refreshing must not migrate the legacy store');
    assert.deepEqual(Array.from(store.entries()), before);
    const html = result.value.response.body.split('<body>')[1];
    assert.match(html, /Wi-Fi 已跳过.*上次检查.*蜂窝 2023\/11\/\d+ \d\d:\d\d/);
    assert.match(html, /部分放行.*4\/7 个账号已放行/);
    const cards = html.match(/<article\b.*?<\/article>/g);
    assert.equal(cards.length, official.accounts.length);
    assert.match(cards[0], /&lt;公司&gt;.*共用 #2.*指定 #3.*2\/5.*官方出口.*192\.0\.2\.3\/24/);
    assert.match(cards[0], /class="cell hit" title="#2 本机命中">2</);
    assert.match(cards[0], /class="cell used" title="#4 已占用">4</);
    assert.match(cards[1], /共用自动槽位.*1\/10.*meter unnumbered.*198\.51\.100\.0\/24/);
    assert.doesNotMatch(cards[1], /class="cell [^"]+" title="#/);
    assert.match(cards[2], /未放行.*指定 #1.*203\.0\.113\.0\/24/);
    assert.match(cards[3], /检查失败.*HTTP 503/);
    assert.doesNotMatch(cards[3], /槽位占用|官方出口|9\/10/);
    assert.match(cards[4], /官方账号 5.*槽位不匹配.*指定 #2/);
    assert.match(cards[5], /旧缓存.*指定 #2.*meter unnumbered/);
    assert.doesNotMatch(cards[5], /命中 #2/);
    assert.match(cards[6], /新增放行.*命中 #1.*203\.0\.113\.1\/24/);
    assert.doesNotMatch(html, /<公司>|192\.0\.2\.250|pgnfw_private_sample/);
  }
  store.set(STORE_KEY + '.channel-settings', 'broken JSON');
  const invalidSettings = await execute({store, scriptType: 'request', argument: reportArgument('settings')});
  assert.equal(invalidSettings.value.response.status, 502);
  assert.equal(invalidSettings.writes, 0, 'an error in a read-only view cannot change cached results');
}


async function testExpandedOfficialSlots() {
 const token='pgnfw_stash_expanded_fixture';
 for(const limit of [1,5,6,7,8,9,10]) {
  const slot=limit-1, body={enabled:true,currentIp:'8.8.8.8/24',limit,whitelist:[{ip:'8.8.8.8/24',slot}]};
  const store=new Map();
  const saved=await execute({store,argument:reportArgument('save-official',{PO0_FIREWALL_TOKENS:token+'@'+slot})});
  assert.equal(saved.requests.length,0);
  const hit=await execute({store,argument:reportArgument('force',{PO0_FIREWALL_TOKENS:token+'@0'}),officialGets:[{body}]});
  assert.deepEqual(hit.requests.map(r=>r.method),['get']);
  assert.equal(JSON.parse(store.get(STORE_KEY)).official.accounts[0].fixed_slot,slot);
  const updated=await execute({argument:reportArgument('force',{PO0_FIREWALL_TOKENS:token+'@'+slot}),officialGets:[{body:{...body,whitelist:[]}}],officialPosts:[{body}]});
  assert.deepEqual(updated.requests.map(r=>r.method),['get','post']);
  assert(updated.requests[1].request.url.endsWith('?slot='+slot));
  assert.equal(JSON.parse(updated.store.get(STORE_KEY)).official.accounts[0].status,'ok');
  const readonly=await execute({argument:reportArgument('status',{PO0_FIREWALL_TOKENS:token+'@'+slot}),officialGets:[{body:{...body,whitelist:[]}}]});
  assert.deepEqual(readonly.requests.map(r=>r.method),['get']);
  assert.equal(JSON.parse(readonly.store.get(STORE_KEY)).official.last_attempt_at,0);
 }
 for(const [limit,slot] of [[5,5],[6,9]]) {
  const run=await execute({argument:reportArgument('force',{PO0_FIREWALL_TOKENS:token+'@'+slot}),officialGets:[{body:{enabled:true,currentIp:'8.8.8.8/24',limit,whitelist:[]}}]});
  assert.deepEqual(run.requests.map(r=>r.method),['get']);
  assert.match(JSON.parse(run.store.get(STORE_KEY)).official.accounts[0].last_error,/指定槽位超出账号额度/);
 }
 for(const limit of [6,10]) {
  const body={enabled:true,currentIp:'8.8.8.8/24',limit,whitelist:Array.from({length:limit},(_,slot)=>({ip:slot===limit-1?'8.8.8.8/24':'192.0.2.'+slot+'/24',slot}))};
  const run=await execute({argument:reportArgument('force',{PO0_FIREWALL_TOKENS:token+'@'+(limit-1)}),officialGets:[{body}]});
  assert.deepEqual(run.requests.map(r=>r.method),['get']);
  assert.equal(JSON.parse(run.store.get(STORE_KEY)).official.accounts[0].used,limit);
 }
 const valid={enabled:true,currentIp:'8.8.8.8/24',limit:6,whitelist:[]};
 const invalid=[...[0,11,5.5,'6',null,undefined].map(limit=>({...valid,limit})),...[6,10,-1,0.5,'5',true].map(slot=>({...valid,whitelist:[{ip:'8.8.8.8/24',slot}]})),{...valid,limit:1,whitelist:[{ip:'8.8.8.8/24'},{ip:'1.1.1.1/24'}]}];
 for(const body of invalid) {
  const run=await execute({argument:reportArgument('force',{PO0_FIREWALL_TOKENS:token}),officialGets:[{body}]});
  assert.deepEqual(run.requests.map(r=>r.method),['get']);
  assert.equal(JSON.parse(run.store.get(STORE_KEY)).official.accounts[0].status,'error');
 }
}

(async () => {
  await testNativeNetworkAndSsid();
  await testSavedNotificationOptions();
  await testSharedSubnetAndRejectedWrite();
  await testExpandedOfficialSlots();
  await testStandardEntrypointsAndLegacyRoutes();
  await testNetworkEvent();
  await testTileRemainsReadOnly();
  await testCollapsedTileAccountDetails();
  await testOfficialNetworkTargets();
  await testFlexibleOfficialSeparators();
  await testLocalSlotSurvivesSync();
  await testOfficialGetFirstAndFixedSlot();
  await testSameTokenDifferentSlotsFailClosed();
  await testPersistentLockWriteFailureFailsClosed();
  await testHitAndGetFailureNeverPost();
  await testStatusMissingIsSuccessAndReadOnly();
  await testStrictDuplicateSlotsAndTokenPersistence();
  await testPartialOfficialAccountsContinue();
  await testRetirementMigration();
  console.log('PASS: stash official-only API, network and migration checks');
})().catch(error => { console.error(error); process.exitCode = 1; });
