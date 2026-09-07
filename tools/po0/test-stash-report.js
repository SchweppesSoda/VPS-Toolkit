"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const clientDir = path.join(__dirname, "..", "..", "scripts", "po0", "nftables", "clients", "stash");
const scriptPath = path.join(clientDir, "po0-stash-report.js");
const overridePath = path.join(clientDir, "PO0.LAN-Report.stoverride");
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
    const officialGets = (options.officialGets || []).slice();
    const officialPosts = (options.officialPosts || []).slice();
    let doneCalls = 0;
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
            const blocked = group === '📡 PO0 Wi-Fi 探测' ? network !== 'wifi' : group === '📡 PO0 蜂窝探测' ? network !== 'cellular' : false;
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
        resolve({ store, requests, notifications, logs, doneCalls, value });
      },
    };

    try {
      vm.runInNewContext(source, context, { filename: "po0-stash-report.js" });
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
  assert.strictEqual(officialGet.node, "DIRECT");
  assert.ok(officialPost.url.endsWith("/add?slot=3"));
  assert.strictEqual(officialPost.node, "DIRECT");
  assert.strictEqual(officialGet.headers["X-Stash-Selected-Proxy"], undefined);
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
  assert.match(result.value.response.body, /未命中/);
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
  result = await call({mode:'auto', channel:'official'}, 'cellular', {officialPosts:[{body:officialBody([{ip:'8.8.8.8/24',slot:1}])}]});
  assert(posts(result)[0].request.url.endsWith('/add?slot=1'), 'cellular must use the original user slot');
  result = await call({mode:'auto', channel:'official', PO0_FIREWALL_WIFI_TOKENS:'pgnfw_synced_other@4'});
  assert(posts(result)[0].request.url.endsWith('/add'), 'Wi-Fi uses the saved unslotted target exactly');
  assert.equal(JSON.parse(store.get(STORE_KEY)).official.accounts[0].name, 'Wi-Fi 自填名称');
  assert.equal(store.get(STORE_KEY + '.official-config'), snapshot, 'sync cannot change saved network settings');
  result = await call({mode:'auto', channel:'official'});
  assert.equal(officialRequests(result).length, 0, 'same network respects report interval');
  result = await call({mode:'auto', channel:'official'}, 'cellular', {officialPosts:[{body:officialBody([{ip:'8.8.8.8/24',slot:1}])}]});
  assert(posts(result)[0].request.url.endsWith('/add?slot=1'), 'switching back must not reuse Wi-Fi due cache');
  result = await call({mode:'status'});
  assert.equal(posts(result).length, 0, 'network-selected status stays read-only');
  result = await call({mode:'auto', channel:'official'});
  assert(posts(result).length, 'read-only on a new network cannot suppress its next report');
  result = await call({mode:'force', channel:'official'}, 'unknown');
  assert.equal(officialRequests(result).length, 0, 'unknown network must not select either official list');
  result = await call({mode:'force', channel:'official'}, 'both');
  assert.equal(officialRequests(result).length, 0, 'ambiguous complementary probes must not select a target');
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
  result = await call({mode:'auto', worker_url:'https://report.example.com/stash-report/v1', secret:'worker-fixture', token:'worker-fixture', source_id:'phone'});
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

(async () => {
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
