"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const clientDir = path.join(__dirname, "..", "..", "scripts", "po0", "nftables", "clients", "loon");
const scriptPath = path.join(clientDir, "po0-loon-report.js");
const pluginPath = path.join(clientDir, "PO0.LAN-Report.lpx");
const scriptRawUrl = "https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/loon/po0-loon-report.js";
const source = fs.readFileSync(scriptPath, "utf8");
const STORE_KEY = "proxyconfig.po0.loon-report.v1";
const RUN_LOCK_KEY = `${STORE_KEY}.run-lock`;
const FIREWALL_KEY = "PO0_FIREWALL_TOKENS";

function officialOnlyArgument(mode) {
  return JSON.stringify({ mode, worker_url: "", token: "" });
}

function officialBody(whitelist, currentIp = "8.8.8.8/24") {
  return { enabled: true, currentIp, limit: 5, whitelist };
}

function futureWorkerResponse(now = Date.now()) {
  return {
    ok: true,
    source_id: "loon-ios",
    accepted_cidr: "8.8.8.8/32",
    accepted_at: new Date(now - 1_000).toISOString(),
    expires_at: new Date(now + 12 * 60 * 60 * 1000).toISOString(),
    targets: [{ name: "po0", ok: true }],
  };
}

function execute(options = {}) {
  return new Promise((resolve, reject) => {
    const store = options.store instanceof Map
      ? options.store
      : new Map(Object.entries(options.store || {}));
    const requests = [];
    const notifications = [];
    const writes = [];
    const logs = [];
    const officialGets = (options.officialGets || []).slice();
    const officialPosts = (options.officialPosts || []).slice();
    let configCalls = 0;
    let doneCalls = 0;
    let postCallbackFinished = false;
    const timeout = setTimeout(() => reject(new Error("PO0 Loon script test timed out")), 2_000);

    const httpClient = {
      get: (request, callback) => {
        requests.push({ method: "get", request });
        const isOfficial = String(request.url || "").includes("/api/firewall/");
        const spec = isOfficial
          ? (officialGets.shift() || { status: 200, body: options.officialResponse })
          : null;
        const delayMs = isOfficial ? Math.max(0, Number(spec && spec.delayMs) || 0) : 0;
        const reply = () => {
          if (isOfficial) {
            if (spec.error) return callback(spec.error);
            const body = spec.body === undefined ? { enabled: true, currentIp: "8.8.8.8/24", limit: 5, whitelist: [] } : spec.body;
            return callback(null, { status: spec.status || 200 }, typeof body === "string" ? body : JSON.stringify(body));
          }
          return callback(null, { status: 200 }, JSON.stringify({ ip: "8.8.8.8" }));
        };
        if (options.asyncHttp || delayMs > 0) setTimeout(reply, delayMs + (options.asyncHttp ? 5 : 0));
        else reply();
      },
      post: (request, callback) => {
        requests.push({ method: "post", request });
        const isOfficial = String(request.url || "").includes("/api/firewall/");
        const spec = isOfficial
          ? (officialPosts.shift() || { status: 200, body: options.officialResponse })
          : null;
        const delayMs = isOfficial ? Math.max(0, Number(spec && spec.delayMs) || 0) : 0;
        const reply = () => {
          postCallbackFinished = true;
          if (options.postError) callback(options.postError);
          else if (isOfficial) {
            if (spec.error) return callback(spec.error);
            const body = spec.body === undefined ? { enabled: true, currentIp: "8.8.8.8/24", limit: 5, whitelist: [{ ip: "8.8.8.8/24", slot: null }] } : spec.body;
            return callback(null, { status: spec.status || 200 }, typeof body === "string" ? body : JSON.stringify(body));
          }
          else callback(null, { status: 200 }, JSON.stringify(options.workerResponse || futureWorkerResponse()));
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
      $script: { name: options.scriptName || "" },
      $argument: options.argument === undefined ? JSON.stringify({
        mode: options.mode || "auto",
        worker_url: "https://report.example.com/stash-report/v1",
        token: "test-token",
      }) : options.argument,
      $config: {
        getConfig: () => {
          configCalls += 1;
          if (options.forbidConfig) throw new Error("status must not read runtime config");
          return JSON.stringify({ ssid: options.ssid === undefined ? "Cafe-WiFi" : options.ssid });
        },
      },
      $persistentStore: {
        read: (key) => store.has(key) ? store.get(key) : null,
        write: (value, key) => {
          if (options.writeError) throw new Error("persistent store unavailable");
          writes.push({ key, value });
          store.set(key, value);
          return true;
        },
      },
      $notification: {
        post: (title, subtitle, content) => {
          if (options.notificationError) throw new Error("notifications disabled");
          notifications.push({ title, subtitle, content });
        },
      },
      $httpClient: httpClient,
      $done: () => {
        doneCalls += 1;
        if (doneCalls > 1) {
          clearTimeout(timeout);
          reject(new Error("$done called more than once"));
          return;
        }
        if (typeof options.onDone === "function") options.onDone(store);
        clearTimeout(timeout);
        resolve({ store, requests, notifications, writes, logs, configCalls, doneCalls, postCallbackFinished });
      },
    };

    try {
      vm.runInNewContext(source, context, { filename: "po0-loon-report.js" });
    } catch (error) {
      clearTimeout(timeout);
      reject(error);
    }
  });
}

async function testSuccessfulAwayReport() {
  const result = await execute({ asyncHttp: true });
  assert.strictEqual(result.doneCalls, 1);
  assert.strictEqual(result.postCallbackFinished, true, "$done must wait for the HTTP callback");
  assert.strictEqual(result.configCalls, 1, "runtime config must be read once");
  assert.strictEqual(result.requests.length, 2);

  const get = result.requests.find((entry) => entry.method === "get").request;
  const post = result.requests.find((entry) => entry.method === "post").request;
  assert.strictEqual(get.node, "DIRECT");
  assert.strictEqual(get.timeout, 5_000, "Loon timeout must be milliseconds");
  assert.strictEqual(post.timeout, 12_000, "Loon timeout must be milliseconds");
  assert.strictEqual(post.headers.Authorization, "Bearer test-token");
  assert.strictEqual(post.headers["User-Agent"], "AutoLoon-Loon/1");

  const payload = JSON.parse(post.body);
  assert.strictEqual(payload.source_id, "loon-ios");
  assert.strictEqual(payload.ip, "8.8.8.8");
  assert.strictEqual(payload.network, "wifi");
  const state = JSON.parse(result.store.get(STORE_KEY));
  assert.strictEqual(state.accepted_cidr, "8.8.8.8/32");
  assert.strictEqual(state.context, "wifi:Cafe-WiFi");
}

async function testPluginPersistentCredentials() {
  const result = await execute({
    argument: "force",
    store: {
      po0_worker_url: "https://report.example.com/stash-report/v1",
      po0_worker_token: "plugin-token",
    },
  });
  const post = result.requests.find((entry) => entry.method === "post").request;
  assert.strictEqual(post.headers.Authorization, "Bearer plugin-token");
  assert.strictEqual(JSON.parse(post.body).source_id, "loon-ios");
}

async function testHomeAndUnknownFailClosed() {
  for (const ssid of ["ZTE-47kTee", "", "unknown", "<unknown ssid>"]) {
    const result = await execute({ ssid });
    assert.strictEqual(result.requests.length, 0, `${JSON.stringify(ssid)} must perform no HTTP`);
  }

  const forced = await execute({
    ssid: "ZTE-47kTee",
    mode: "force",
    argument: JSON.stringify({ mode: "force", worker_url: "", token: "" }),
  });
  assert.strictEqual(forced.requests.length, 0, "force without configured routes should remain network-free");
  assert.strictEqual(forced.notifications.length, 1);
  assert.match(forced.notifications[0].content, /没有启用/);
}

async function testStatusIsReadOnly() {
  const storedState = JSON.stringify({
    accepted_cidr: "8.8.8.8/32",
    accepted_at: Math.floor(Date.now() / 1000),
    expires_at: Math.floor(Date.now() / 1000) + 3600,
    network: "wifi",
  });
  const result = await execute({
    mode: "status",
    argument: "status",
    store: { [STORE_KEY]: storedState },
    forbidConfig: true,
  });
  assert.strictEqual(result.configCalls, 0);
  assert.strictEqual(result.requests.length, 0);
  assert.strictEqual(result.writes.length, 0);
  assert.strictEqual(result.notifications.length, 1);
}

async function testTTLAndDebounceAvoidNetwork() {
  const now = Math.floor(Date.now() / 1000);
  const cached = JSON.stringify({
    context: "wifi:Cafe-WiFi",
    accepted_at: now - 30,
    expires_at: now + 7200,
    next_refresh_at: now + 1200,
  });
  const ttlResult = await execute({ store: { [STORE_KEY]: cached } });
  assert.strictEqual(ttlResult.requests.length, 0, "valid TTL must avoid all HTTP");

  const lock = JSON.stringify({ at: Date.now(), context: "wifi:Cafe-WiFi" });
  const debounceResult = await execute({ store: { [RUN_LOCK_KEY]: lock } });
  assert.strictEqual(debounceResult.requests.length, 0, "debounce must avoid all HTTP");
}

async function testSharedRunLockAcrossModesAndContexts() {
  const token = "pgnfw_loon_shared_lock";
  const statusStore = new Map([[FIREWALL_KEY, token]]);
  const statusPromise = execute({
    argument: officialOnlyArgument("status"),
    store: statusStore,
    officialGets: [{ body: officialBody([]) }],
    asyncHttp: true,
  });
  await Promise.resolve();
  const runningForce = await execute({
    argument: officialOnlyArgument("force"),
    store: statusStore,
    officialGets: [{ body: officialBody([]) }],
  });
  assert.deepStrictEqual(runningForce.requests, [], "status lock must block force while running");
  await statusPromise;
  await Promise.resolve();
  const statusLock = JSON.parse(statusStore.get(RUN_LOCK_KEY) || "{}");
  assert.deepStrictEqual(statusLock, {}, "completed status must release its owner lock");

  const forceAfterStatus = await execute({
    argument: officialOnlyArgument("force"),
    store: statusStore,
    officialGets: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: null }]) }],
  });
  assert.deepStrictEqual(forceAfterStatus.requests.map((entry) => entry.method), ["get"], "force may run immediately after status completion");

  const autoStore = new Map([[FIREWALL_KEY, token]]);
  const autoPromise = execute({
    argument: officialOnlyArgument("auto"),
    store: autoStore,
    officialGets: [{ body: officialBody([]) }],
    officialPosts: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: null }]) }],
    asyncHttp: true,
  });
  await Promise.resolve();
  const runningStatus = await execute({
    argument: officialOnlyArgument("status"),
    store: autoStore,
    officialGets: [{ body: officialBody([]) }],
  });
  assert.deepStrictEqual(runningStatus.requests, [], "auto lock must block status while running");
  await autoPromise;
  await Promise.resolve();

  const statusAfterAuto = await execute({
    argument: officialOnlyArgument("status"),
    store: autoStore,
    officialGets: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: null }]) }],
  });
  assert.deepStrictEqual(statusAfterAuto.requests.map((entry) => entry.method), ["get"], "status may run immediately after auto completion");

  const raceStore = new Map([[FIREWALL_KEY, token]]);
  await execute({
    argument: officialOnlyArgument("status"),
    store: raceStore,
    officialGets: [{ body: officialBody([]) }],
    onDone(store) {
      store.set(RUN_LOCK_KEY, JSON.stringify({
        version: 1,
        owner: "replacement-owner",
        at: Date.now(),
        expires_at: Date.now() + 120_000,
        context: "replacement",
        mode: "force",
      }));
    },
  });
  const replacement = JSON.parse(raceStore.get(RUN_LOCK_KEY));
  assert.strictEqual(replacement.owner, "replacement-owner", "old owner must not release a replacement lock");
  const blockedByReplacement = await execute({
    argument: officialOnlyArgument("force"),
    store: raceStore,
    officialGets: [{ body: officialBody([]) }],
  });
  assert.deepStrictEqual(blockedByReplacement.requests, [], "replacement owner lock must remain active");

  /*
   * The assertions above deliberately use a shared persistent map.  A
   * completed run releases only its owner, while a concurrent run sees the
   * same lock regardless of mode or network context.
   */
  return;
}

async function testErrorsAreRedacted() {
  const result = await execute({
    mode: "force",
    postError: "upstream rejected Authorization: Bearer test-token",
  });
  const state = result.store.get(STORE_KEY);
  assert.ok(state, "failed report should retain a diagnostic state");
  assert.ok(!state.includes("test-token"), "state must not contain the token");
  assert.ok(!result.logs.join("\n").includes("test-token"), "logs must not contain the token");
  assert.ok(!result.notifications.map((item) => item.content).join("\n").includes("test-token"));
}

async function testLocalSideEffectFailuresStillFinish() {
  const result = await execute({ mode: "force", writeError: true, notificationError: true });
  assert.strictEqual(result.doneCalls, 1);
  assert.strictEqual(result.postCallbackFinished, false, "failed lock persistence must fail closed before network");
}

async function testOfficialGetFirstAndFixedSlot() {
  const token = "pgnfw_loon_fixture";
  const result = await execute({
    argument: officialOnlyArgument("force"),
    store: { [FIREWALL_KEY]: token + "@2" },
    officialGets: [{ body: officialBody([{ ip: "1.1.1.1/24", slot: 0 }]) }],
    officialPosts: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: 2 }]) }],
  });
  assert.deepStrictEqual(result.requests.map((entry) => entry.method), ["get", "post"]);
  assert.ok(result.requests[0].request.url.endsWith("/" + token));
  assert.strictEqual(result.requests[0].request.node, "DIRECT");
  assert.ok(result.requests[1].request.url.endsWith("/add?slot=2"));
  assert.strictEqual(result.requests[1].request.node, "DIRECT");
  const state = JSON.parse(result.store.get(STORE_KEY));
  assert.strictEqual(state.official.accounts[0].current, "8.8.8.8/24");
  assert.strictEqual(state.official.accounts[0].fixed_slot, 2);
  assert.strictEqual(state.official.accounts[0].used, 1);
  assert.ok(!JSON.stringify(state).includes(token));
  assert.ok(!result.logs.join("\n").includes(token));
  assert.ok(!result.notifications.map((item) => item.content).join("\n").includes(token));
}

async function testOfficialHitAndGetFailureNeverPost() {
  const token = "pgnfw_loon_readonly";
  const hit = await execute({
    argument: officialOnlyArgument("force"),
    store: { [FIREWALL_KEY]: token + "@2" },
    officialGets: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: 2 }]) }],
  });
  assert.deepStrictEqual(hit.requests.map((entry) => entry.method), ["get"]);
  assert.strictEqual(hit.notifications.length, 1);

  const failed = await execute({
    argument: officialOnlyArgument("force"),
    store: { [FIREWALL_KEY]: token },
    officialGets: [{ status: 503, body: "upstream unavailable" }],
  });
  assert.deepStrictEqual(failed.requests.map((entry) => entry.method), ["get"]);
  assert.ok(!failed.requests.some((entry) => entry.method === "post"));
  assert.ok(!failed.logs.join("\n").includes(token));
  assert.ok(!failed.notifications.map((item) => item.content).join("\n").includes(token));
}

async function testOfficialStatusMissingIsReadable() {
  const token = "pgnfw_loon_status";
  const result = await execute({
    mode: "status",
    argument: officialOnlyArgument("status"),
    store: { [FIREWALL_KEY]: token },
    officialGets: [{ body: officialBody([{ ip: "1.1.1.1/24", slot: null }]) }],
    forbidConfig: true,
  });
  assert.strictEqual(result.configCalls, 0);
  assert.deepStrictEqual(result.requests.map((entry) => entry.method), ["get"]);
  assert.strictEqual(result.notifications.length, 1);
  assert.strictEqual(result.notifications[0].subtitle, "可用");
  const state = JSON.parse(result.store.get(STORE_KEY));
  assert.strictEqual(state.official.accounts[0].status, "missing");
  assert.strictEqual(state.official.accounts[0].current, "8.8.8.8/24");
}

async function testOfficialRunsBeforeCachedWorker() {
  const now = Math.floor(Date.now() / 1000);
  const token = "pgnfw_loon_due";
  const cached = JSON.stringify({
    context: "wifi:Cafe-WiFi",
    ip: "8.8.8.8",
    network: "wifi",
    accepted_at: now - 30,
    expires_at: now + 7200,
    next_refresh_at: now + 1200,
    official: { last_attempt_at: now - 601 },
  });
  const result = await execute({
    store: { [STORE_KEY]: cached, [FIREWALL_KEY]: token },
    officialGets: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: null }]) }],
  });
  assert.deepStrictEqual(result.requests.map((entry) => entry.method), ["get"]);
  assert.ok(result.requests[0].request.url.includes("/api/firewall/"));
}

async function testOfficialDuplicateSlotsFailClosed() {
  const token = "pgnfw_loon_bad_slots";
  const result = await execute({
    argument: officialOnlyArgument("force"),
    store: { [FIREWALL_KEY]: token },
    officialGets: [{ body: officialBody([{ ip: "1.1.1.1/24", slot: 0 }, { ip: "2.2.2.2/24", slot: 0 }]) }],
  });
  assert.deepStrictEqual(result.requests.map((entry) => entry.method), ["get"]);
  assert.ok(!result.requests.some((entry) => entry.method === "post"));
  const state = JSON.parse(result.store.get(STORE_KEY));
  assert.strictEqual(state.official.accounts[0].status, "error");
  assert.ok(!JSON.stringify(state).includes(token));
}

async function testSameTokenDifferentSlotsFailClosed() {
  const token = "pgnfw_loon_same_account";
  const result = await execute({
    argument: officialOnlyArgument("force"),
    store: { [FIREWALL_KEY]: token + "@0," + token + "@1" },
  });
  assert.deepStrictEqual(result.requests, [], "the same official account must not run concurrently through different slots");
  assert.ok(!result.logs.join("\n").includes(token));
  assert.ok(!result.notifications.map((item) => item.content).join("\n").includes(token));
}

async function testPersistentLockWriteFailureFailsClosed() {
  const token = "pgnfw_loon_lock_store_failure";
  const result = await execute({
    argument: officialOnlyArgument("force"),
    store: { [FIREWALL_KEY]: token },
    writeError: true,
    officialGets: [{ body: officialBody([]) }],
    officialPosts: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: null }]) }],
  });
  assert.deepStrictEqual(result.requests, [], "a failed lock write must block all network reports");
}

async function testParallelOfficialAccountsPreserveLaneOrder() {
  const first = "pgnfw_loon_parallel_one";
  const second = "pgnfw_loon_parallel_two";
  const result = await execute({
    store: { [FIREWALL_KEY]: first + "," + second },
    officialGets: [
      { delayMs: 35, body: officialBody([]) },
      { delayMs: 0, body: officialBody([]) },
    ],
    officialPosts: [
      { delayMs: 15, body: officialBody([{ ip: "8.8.8.8/24", slot: null }]) },
      { delayMs: 15, body: officialBody([{ ip: "8.8.8.8/24", slot: null }]) },
    ],
  });
  const officialRequests = result.requests.filter((entry) => String(entry.request.url || "").includes("/api/firewall/"));
  assert.deepStrictEqual(officialRequests.slice(0, 2).map((entry) => entry.method), ["get", "get"]);
  assert.deepStrictEqual(officialRequests.map((entry) => entry.method), ["get", "get", "post", "post"]);
  const workerIndex = result.requests.findIndex((entry) => entry.request.url === "https://api.ipify.org?format=json");
  assert.ok(workerIndex >= 4, "Worker must start only after every official account finishes");
  assert.strictEqual(JSON.parse(result.store.get(STORE_KEY)).official.accounts[0].account, 1);
  assert.strictEqual(JSON.parse(result.store.get(STORE_KEY)).official.accounts[1].account, 2);
}

function testPluginContract() {
  const plugin = fs.readFileSync(pluginPath, "utf8");
  const declarations = plugin.split(/\r?\n/).filter((line) => /^(?:cron|network-changed|generic)\b/.test(line));
  assert.strictEqual(declarations.length, 6);
  assert.strictEqual(declarations.filter((line) => /timeout=300/.test(line)).length, 4);
  assert.match(plugin, /\[Argument\]/);
  assert.match(plugin, /po0_worker_url = input,tag=【自建 PO0】/);
  assert.match(plugin, /po0_worker_token = input,tag=【自建 PO0】/);
  assert.match(plugin, /PO0_FIREWALL_TOKENS = input,tag=【官方防火墙】/);
  assert.strictEqual(declarations.filter((line) => line.includes('argument=[{PO0_FIREWALL_TOKENS}]')).length, 1);
  assert.ok(declarations.every((line) => line.includes('script-path=' + scriptRawUrl)));
}

async function testNamedPluginArguments() {
  const saved = await execute({ scriptName: '官方防火墙 · 保存本机设置',
    argument: { PO0_FIREWALL_TOKENS: 'pgnfw_named_mock@2' }, forbidConfig: true });
  assert.deepStrictEqual(saved.requests, []);
  assert.equal(JSON.parse(saved.store.get(STORE_KEY + '.official-config')).tokens, 'pgnfw_named_mock@2');
  const status = await execute({ scriptName: '通用 · 查看上报状态',
    argument: { po0_worker_url: 'https://report.example.com/stash-report/v1', po0_worker_token: 'mock' }, forbidConfig: true });
  assert.deepStrictEqual(status.requests, []);
  const forced = await execute({ scriptName: '通用 · 立即上报',
    argument: { po0_worker_url: 'https://report.example.com/stash-report/v1', po0_worker_token: 'mock' } });
  assert.ok(forced.requests.some((entry) => entry.method === 'post' && entry.request.url === 'https://report.example.com/stash-report/v1'));
}

function testLocalSlotSurvivesSync() {
  const store = new Map();
  const sandbox = {
    $persistentStore: { read: key => store.has(key) ? store.get(key) : null, write: (value, key) => { store.set(key, value); return true; } },
  };
  vm.createContext(sandbox);
  const start = source.indexOf('function firewallInput(');
  const end = source.indexOf('function parseFirewallTokens(');
  const parseEnd = source.indexOf('\nfunction ', end + 10);
  const functions = source.slice(start, parseEnd);
  const prefix = `const STORE_ID = 'device-test'; const LEGACY_ID = 'PO0_FIREWALL_TOKENS'; const MAX_ID = 16;`;
  const renamed = functions.replaceAll('PO0_STORE_KEY', 'STORE_ID').replaceAll('PO0_FIREWALL_TOKENS_KEY', 'LEGACY_ID').replaceAll('PO0_MAX_FIREWALL_TOKENS', 'MAX_ID');
  vm.runInContext(prefix + `
    function readStore(k) { return $persistentStore.read(k); }
    function writeJSON(k,v) { return $persistentStore.write(JSON.stringify(v),k); }
    function firstNonEmpty(v) { return v.find(x => x !== null && x !== undefined && String(x).trim()) || ''; }
  ` + renamed, sandbox);
  vm.runInContext("saveLocalFirewall({PO0_FIREWALL_TOKENS:'pgnfw_this_device@0'}, false)", sandbox);
  assert.equal(vm.runInContext("firewallRawValue({PO0_FIREWALL_TOKENS:'pgnfw_synced_device@4'})", sandbox), 'pgnfw_this_device@0');
  vm.runInContext("saveLocalFirewall({}, true)", sandbox);
  assert.equal(vm.runInContext("firewallRawValue({PO0_FIREWALL_TOKENS:'pgnfw_synced_device@4'})", sandbox), '');
}

(async () => {
  testLocalSlotSurvivesSync();
  await testNamedPluginArguments();
  await testSuccessfulAwayReport();
  await testPluginPersistentCredentials();
  await testHomeAndUnknownFailClosed();
  await testStatusIsReadOnly();
  await testTTLAndDebounceAvoidNetwork();
  await testSharedRunLockAcrossModesAndContexts();
  await testErrorsAreRedacted();
  await testLocalSideEffectFailuresStillFinish();
  await testOfficialGetFirstAndFixedSlot();
  await testOfficialHitAndGetFailureNeverPost();
  await testOfficialStatusMissingIsReadable();
  await testOfficialRunsBeforeCachedWorker();
  await testOfficialDuplicateSlotsFailClosed();
  await testSameTokenDifferentSlotsFailClosed();
  await testPersistentLockWriteFailureFailsClosed();
  await testParallelOfficialAccountsPreserveLaneOrder();
  testPluginContract();
  console.log("po0-loon-report tests: OK");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
