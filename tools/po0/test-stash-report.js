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
const sshOverride = fs.readFileSync(sshOverridePath, "utf8");
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
            result = { response: { status: 204 }, data: "" };
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
  assert.deepStrictEqual(result.requests.map((entry) => entry.method), ["get", "get", "post"]);
  const officialGet = result.requests[1].request;
  const officialPost = result.requests[2].request;
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
  assert.deepStrictEqual(hit.requests.map((entry) => entry.method), ["get", "get"]);
  assert.ok(!hit.requests.some((entry) => entry.method === "post"));

  const failed = await execute({
    argument: reportArgument("force"),
    store: { [FIREWALL_KEY]: token },
    officialGets: [{ status: 503, body: "upstream unavailable" }],
  });
  assert.deepStrictEqual(failed.requests.map((entry) => entry.method), ["get", "get"]);
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

async function testSharedRunLockAcrossModesAndContexts() {
  const token = "pgnfw_stash_shared_lock";
  const statusStore = new Map([[FIREWALL_KEY, token]]);
  const statusPromise = execute({
    argument: reportArgument("status"),
    scriptType: "request",
    store: statusStore,
    officialGets: [{ body: officialBody([]) }],
    asyncHttp: true,
  });
  await Promise.resolve();
  const runningForce = await execute({
    argument: reportArgument("force"),
    scriptType: "request",
    store: statusStore,
    officialGets: [{ body: officialBody([]) }],
  });
  assert.deepStrictEqual(runningForce.requests, [], "status lock must block force while running");
  await statusPromise;
  await Promise.resolve();
  const statusLock = JSON.parse(statusStore.get(RUN_LOCK_KEY) || "{}");
  assert.deepStrictEqual(statusLock, {}, "completed status must release its owner lock");

  const forceAfterStatus = await execute({
    argument: reportArgument("force"),
    scriptType: "request",
    store: statusStore,
    officialGets: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: null }]) }],
  });
  assert.deepStrictEqual(forceAfterStatus.requests.map((entry) => entry.method), ["get", "get"], "force may run immediately after status completion");

  const autoStore = new Map([[FIREWALL_KEY, token]]);
  const autoPromise = execute({
    argument: reportArgument("auto"),
    store: autoStore,
    officialGets: [{ body: officialBody([]) }],
    officialPosts: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: null }]) }],
    asyncHttp: true,
  });
  await Promise.resolve();
  const runningStatus = await execute({
    argument: reportArgument("status"),
    scriptType: "request",
    store: autoStore,
    officialGets: [{ body: officialBody([]) }],
  });
  assert.deepStrictEqual(runningStatus.requests, [], "auto lock must block status while running");
  await autoPromise;
  await Promise.resolve();

  const statusAfterAuto = await execute({
    argument: reportArgument("status"),
    scriptType: "request",
    store: autoStore,
    officialGets: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: null }]) }],
  });
  assert.deepStrictEqual(statusAfterAuto.requests.map((entry) => entry.method), ["get"], "status may run immediately after auto completion");

  const raceStore = new Map([[FIREWALL_KEY, token]]);
  await execute({
    argument: reportArgument("status"),
    scriptType: "request",
    store: raceStore,
    officialGets: [{ body: officialBody([]) }],
    onDone(store) {
      store.set(RUN_LOCK_KEY, JSON.stringify({
        version: 1,
        owner: "replacement-owner",
        at: Date.now(),
        expires_at: Date.now() + 120000,
        context: "replacement",
        mode: "force",
      }));
    },
  });
  const replacement = JSON.parse(raceStore.get(RUN_LOCK_KEY));
  assert.strictEqual(replacement.owner, "replacement-owner", "old owner must not release a replacement lock");
  const blockedByReplacement = await execute({
    argument: reportArgument("force"),
    scriptType: "request",
    store: raceStore,
    officialGets: [{ body: officialBody([]) }],
  });
  assert.deepStrictEqual(blockedByReplacement.requests, [], "replacement owner lock must remain active");

  return;
}

async function testDualOrderAndIndependentWorkerTTL() {
  const token = "pgnfw_stash_due";
  const dual = await execute({
    store: { [FIREWALL_KEY]: token },
    officialGets: [{ body: officialBody([{ ip: "1.1.1.1/24", slot: null }]) }],
    officialPosts: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: null }]) }],
  });
  assert.deepStrictEqual(dual.requests.map((entry) => entry.method), ["get", "get", "post", "get", "post"]);
  assert.strictEqual(dual.requests[1].request.url, OFFICIAL_URL + "/" + token);
  assert.strictEqual(dual.requests[2].request.url, OFFICIAL_URL + "/" + token + "/add");
  assert.strictEqual(dual.notifications.length, 1, "automatic new official slot should notify");

  const now = Math.floor(Date.now() / 1000);
  const cached = JSON.stringify({
    ip: "8.8.8.8",
    network: "wifi",
    accepted_at: now - 30,
    official: { last_attempt_at: now - 601 },
  });
  const due = await execute({
    store: { [STORE_KEY]: cached, [FIREWALL_KEY]: token },
    officialGets: [{ body: officialBody([{ ip: "8.8.8.8/24", slot: null }]) }],
  });
  assert.deepStrictEqual(due.requests.map((entry) => entry.method), ["get", "get", "get"]);
  assert.ok(due.requests[1].request.url.startsWith(OFFICIAL_URL));
}

async function testStrictDuplicateSlotsAndTokenPersistence() {
  const token = "pgnfw_stash_bad_slots";
  const result = await execute({
    argument: reportArgument("force", { PO0_FIREWALL_TOKENS: token }),
    officialGets: [{ body: officialBody([{ ip: "1.1.1.1/24", slot: 0 }, { ip: "2.2.2.2/24", slot: 0 }]) }],
  });
  assert.strictEqual(JSON.parse(result.store.get(STORE_KEY + ".official-config")).tokens, token);
  assert.deepStrictEqual(result.requests.map((entry) => entry.method), ["get", "get"]);
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
  assert.deepStrictEqual(result.requests.map((entry) => entry.method), ["get", "get", "get", "post"]);
  assert.strictEqual(result.requests[1].request.url, OFFICIAL_URL + "/" + first);
  assert.strictEqual(result.requests[2].request.url, OFFICIAL_URL + "/" + second);
  assert.strictEqual(result.requests[3].request.url, OFFICIAL_URL + "/" + second + "/add");
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

async function testParallelOfficialAccountsPreserveLaneOrder() {
  const first = "pgnfw_stash_parallel_one";
  const second = "pgnfw_stash_parallel_two";
  const result = await execute({
    argument: reportArgument("force", {
      worker_url: "https://report.example.com/stash-report/v1",
      source_id: "iphone-stash",
      secret: "worker-secret",
    }),
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
  const workerNetworkIndex = result.requests.findIndex((entry) => String(entry.request.url || "").includes("api.ipify.org"));
  assert.ok(workerNetworkIndex > 3, "Worker IPv4 detection must start only after every official account finishes");
  const state = JSON.parse(result.store.get(STORE_KEY));
  assert.strictEqual(state.official.accounts[0].account, 1);
  assert.strictEqual(state.official.accounts[1].account, 2);
}

function testOverrideContract() {
  assert.match(override, /PO0_FIREWALL_TOKENS/);
  assert.ok(override.includes("cron: '*/10 * * * *'"));
  assert.match(override, /20260905-v6/);
  assert.match(override, /官方先、Worker 后/);
  assert.match(override, /直连加白/);
  assert.match(override, /"PO0_FIREWALL_TOKENS":""/);
  assert.ok(override.includes("match: ^http://po0-report\\.invalid/status"));
  assert.ok(override.includes("argument: '{\"mode\":\"status\""));
  assert.ok(override.includes("match: ^http://po0-report\\.invalid/report-now"));
  assert.strictEqual((override.match(/timeout: 90/g) || []).length, 3);
  assert.strictEqual((sshOverride.match(/timeout: 90/g) || []).length, 3);
  assert.ok(override.includes("pgnfw_xxxx"));
  assert.ok(sshOverride.includes("match: ^http://po0-ssh-report\\.invalid/status"));
  assert.ok(sshOverride.includes("argument: '{\"mode\":\"status\""));
  assert.ok(sshOverride.includes("match: ^http://po0-ssh-report\\.invalid/report-now"));
  assert.match(sshOverride, /20260905-v5/);
  assert.doesNotMatch(sshOverride, /pgnfw_[A-Za-z0-9._~-]+/);
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
  const renamed = functions.replaceAll('STORE_KEY', 'STORE_ID').replaceAll('FIREWALL_TOKENS_KEY', 'LEGACY_ID').replaceAll('MAX_FIREWALL_TOKENS', 'MAX_ID');
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
  await testOfficialGetFirstAndFixedSlot();
  await testHitAndGetFailureNeverPost();
  await testStatusMissingIsSuccessAndReadOnly();
  await testSharedRunLockAcrossModesAndContexts();
  await testDualOrderAndIndependentWorkerTTL();
  await testStrictDuplicateSlotsAndTokenPersistence();
  await testSameTokenDifferentSlotsFailClosed();
  await testPartialOfficialAccountsContinue();
  await testPersistentLockWriteFailureFailsClosed();
  await testParallelOfficialAccountsPreserveLaneOrder();
  testOverrideContract();
  console.log("po0-stash-report tests: OK");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
