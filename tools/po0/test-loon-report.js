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
    const store = new Map(Object.entries(options.store || {}));
    const requests = [];
    const notifications = [];
    const writes = [];
    const logs = [];
    let configCalls = 0;
    let doneCalls = 0;
    let postCallbackFinished = false;
    const timeout = setTimeout(() => reject(new Error("PO0 Loon script test timed out")), 2_000);

    const httpClient = {
      get: (request, callback) => {
        requests.push({ method: "get", request });
        const reply = () => callback(null, { status: 200 }, JSON.stringify({ ip: "8.8.8.8" }));
        if (options.asyncHttp) setTimeout(reply, 5);
        else reply();
      },
      post: (request, callback) => {
        requests.push({ method: "post", request });
        const reply = () => {
          postCallbackFinished = true;
          if (options.postError) callback(options.postError);
          else callback(null, { status: 200 }, JSON.stringify(options.workerResponse || futureWorkerResponse()));
        };
        if (options.asyncHttp) setTimeout(reply, 5);
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

  const forced = await execute({ ssid: "ZTE-47kTee", mode: "force" });
  assert.strictEqual(forced.requests.length, 0, "force must not bypass the home guard");
  assert.strictEqual(forced.notifications.length, 1);
  assert.match(forced.notifications[0].content, /家庭 Wi-Fi/);
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
  assert.strictEqual(result.postCallbackFinished, true);
}

function testPluginContract() {
  const plugin = fs.readFileSync(pluginPath, "utf8");
  const declarations = plugin.split(/\r?\n/).filter((line) => /^(?:cron|network-changed|generic)\b/.test(line));
  assert.strictEqual(declarations.length, 4);
  assert.strictEqual(declarations.filter((line) => /^network-changed\b/.test(line)).length, 1);
  assert.strictEqual(declarations.filter((line) => /^cron\b/.test(line) && /argument="auto"/.test(line)).length, 1);
  assert.strictEqual(declarations.filter((line) => /^network-changed\b/.test(line) && /argument="auto"/.test(line)).length, 1);
  assert.strictEqual(declarations.filter((line) => /^generic\b/.test(line) && /argument="status"/.test(line)).length, 1);
  assert.strictEqual(declarations.filter((line) => /^generic\b/.test(line) && /argument="force"/.test(line)).length, 1);
  assert.match(plugin, /#!input\s*=\s*po0_worker_url/);
  assert.match(plugin, /#!input\s*=\s*po0_worker_token/);
  assert.ok(declarations.every((line) => line.includes(`script-path=${scriptRawUrl}`)));
}

(async () => {
  await testSuccessfulAwayReport();
  await testPluginPersistentCredentials();
  await testHomeAndUnknownFailClosed();
  await testStatusIsReadOnly();
  await testTTLAndDebounceAvoidNetwork();
  await testErrorsAreRedacted();
  await testLocalSideEffectFailuresStillFinish();
  testPluginContract();
  console.log("po0-loon-report tests: OK");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
