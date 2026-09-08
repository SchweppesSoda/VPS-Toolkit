import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const scriptPath = resolve(repoRoot, 'scripts/po0/nftables/clients/egern/po0-ssh-ip-report.js');
const compatibilityScriptPath = resolve(repoRoot, 'scripts/po0/relay/egern/po0-ssh-ip-report.js');
const yamlPath = resolve(repoRoot, 'scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml');
const source = await readFile(scriptPath, 'utf8');
const compatibilitySource = await readFile(compatibilityScriptPath, 'utf8');
const yamlSource = await readFile(yamlPath, 'utf8');
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;
const { default: runEgernReport } = await import(moduleUrl);

const CONFIG_STORAGE_KEY = 'po0-ssh-ip-report:config:v1';
const STATE_STORAGE_KEY = 'po0-ssh-ip-report:last';
const OFFICIAL_STORAGE_KEY = 'po0-ssh-ip-report:official:v1';
const REPORT_LOCK_KEY = 'po0-ssh-ip-report:run-lock:v1';
const API_BASE = 'https://124.221.69.228/api/firewall';

function createStorage(initial = {}) {
  const values = new Map(Object.entries(initial));
  return {
    values,
    async get(key) { return values.get(key) ?? null; },
    async set(key, value) { values.set(key, value); },
    async delete(key) { values.delete(key); },
  };
}

function response(payload, status = 200) {
  return {
    status,
    async json() { return payload; },
    async text() { return JSON.stringify(payload); },
  };
}

function envWith(overrides = {}) {
  return {
    PO0_FIREWALL_TOKENS: 'pgnfw_egern_alpha_not_real',
    ...overrides,
  };
}

function createContext({
  env = {},
  trigger = 'generic manual now',
  storage = createStorage(),
  ssid = '',
  widgetFamily = '',
  request = null,
  httpGet,
  httpPost,
  sshConnect,
} = {}) {
  const calls = {
    get: [],
    post: [],
    ssh: 0,
    order: [],
    notifications: [],
    logs: [],
  };
  const ctx = {
    name: trigger,
    trigger,
    widgetFamily,
    env: envWith(env),
    request,
    device: {
      wifi: ssid ? { ssid } : {},
      ipv4: { address: '192.168.1.20', gateway: '192.168.1.1' },
    },
    storage,
    http: {
      async get(url, options) {
        calls.get.push({ url, options });
        calls.order.push(`GET ${url}`);
        if (httpGet) return await httpGet(url, options, calls);
        return response({ enabled: true, currentIp: '203.0.113.10/24', limit: 5, whitelist: [] });
      },
      async post(url, options) {
        calls.post.push({ url, options });
        calls.order.push(`POST ${url}`);
        if (httpPost) return await httpPost(url, options, calls);
        return response({
          enabled: true,
          currentIp: '203.0.113.10/24',
          limit: 5,
          whitelist: [{ ip: '203.0.113.10/24', slot: 0 }],
        });
      },
    },
    ssh: {
      async connect(config) {
        calls.ssh += 1;
        calls.order.push('SSH');
        calls.sshConfig = config;
        if (sshConnect) return await sshConnect(config, calls);
        return {
          async exec() { return { code: 0, stdout: 'SSH OK' }; },
          async close() {},
        };
      },
    },
    notify(message) { calls.notifications.push(message); },
    log(message) { calls.logs.push(message); },
  };
  return { ctx, calls, storage };
}

function officialPayload({ currentIp = '203.0.113.10/24', whitelist = [], limit = 5, enabled = true } = {}) {
  return { enabled, currentIp, limit, whitelist };
}

async function stateOf(storage) {
  const raw = await storage.get(STATE_STORAGE_KEY);
  return raw ? JSON.parse(raw) : null;
}

async function officialStateOf(storage) {
  const raw = await storage.get(OFFICIAL_STORAGE_KEY);
  return raw ? JSON.parse(raw) : null;
}

function visibleText(value) {
  return JSON.stringify(value);
}

function deferred() {
  let resolve;
  const promise = new Promise((nextResolve) => {
    resolve = nextResolve;
  });
  return { promise, resolve };
}

async function testHitUsesDirectGetOnlyAndStaysQuiet() {
  const token = 'pgnfw_egern_hit_not_real';
  const { ctx, calls, storage } = createContext({
    trigger: 'schedule',
    env: { PO0_FIREWALL_TOKENS: `${token}@0` },
    httpGet(url, options) {
      assert.equal(options.policy, 'DIRECT');
      assert.equal(options.credentials, 'omit');
      assert.equal(options.redirect, 'error');
      assert.equal(options.insecureTls, false);
      assert.equal(url, `${API_BASE}/${token}`);
      return response(officialPayload({ whitelist: [{ ip: '203.0.113.10/24', slot: 0 }] }));
    },
    httpPost() { throw new Error('hit must not POST'); },
  });

  const result = await runEgernReport(ctx);
  const official = await officialStateOf(storage);
  assert.equal(result.ok, true);
  assert.equal(result.ip, '203.0.113.10');
  assert.equal(result.official.currentIp, '203.0.113.10/24');
  assert.equal(calls.get.length, 1);
  assert.equal(calls.post.length, 0);
  assert.equal(calls.ssh, 0);
  assert.equal(calls.notifications.length, 0);
  assert.equal(official.status, 'success');
  assert.equal(official.entries[0].status, 'hit');
  assert.equal(official.entries[0].currentInWhitelist, true);
  assert.equal(official.entries[0].used, 1);
  assert.equal(official.entries[0].limit, 5);
  assert.equal(visibleText(result).includes(token), false);
  assert.equal(visibleText(official).includes(token), false);
}

async function testOfficialOnlyIgnoresSshSchemaDefaults() {
  const token = 'pgnfw_egern_defaults_not_real';
  const { ctx, calls } = createContext({
    env: {
      PO0_FIREWALL_TOKENS: token,
      PO0_PORT: '22',
      PO0_USER: 'root',
      PO0_SCRIPT: '/root/nftables-relay-manager.sh',
      SSH_REPORT_SOURCE: 'egern',
      REPORT_IDENTITY: 'egern',
      TTL_SECONDS: '43200',
      AUTO_REPORT_INTERVAL_SECONDS: '3600',
    },
    httpGet() { return response(officialPayload()); },
    sshConnect() { throw new Error('schema defaults must not enable SSH'); },
  });
  const result = await runEgernReport(ctx);
  assert.equal(result.ok, true);
  assert.equal(calls.get.length, 1);
  assert.equal(calls.ssh, 0);
}

async function testMissingReportsWithFixedSlotAndNotifiesUpdate() {
  const token = 'pgnfw_egern_missing_not_real';
  const { ctx, calls, storage } = createContext({
    env: { PO0_FIREWALL_TOKENS: `${token}@3` },
    httpGet(url) {
      assert.equal(url, `${API_BASE}/${token}`);
      return response(officialPayload({ whitelist: [{ ip: '198.51.100.1/24', slot: 1 }] }));
    },
    httpPost(url, options) {
      assert.equal(url, `${API_BASE}/${token}/add?slot=3`);
      assert.equal(options.policy, 'DIRECT');
      return response(officialPayload({
        currentIp: '203.0.113.10/24',
        whitelist: [{ ip: '203.0.113.10/24', slot: 3 }],
      }));
    },
  });

  const result = await runEgernReport(ctx);
  assert.equal(result.ok, true);
  assert.equal(calls.get.length, 1);
  assert.equal(calls.post.length, 1);
  assert.equal(calls.notifications.length, 1);
  assert.match(calls.notifications[0].body, /账号 #1/);
  assert.match(calls.notifications[0].body, /槽位 4/);
  const official = await officialStateOf(storage);
  assert.equal(official.entries[0].status, 'updated');
  assert.equal(official.entries[0].fixedSlot, 3);
  assert.equal(official.entries[0].currentIp, '203.0.113.10/24');
  assert.equal(visibleText(result).includes(token), false);
  assert.equal(visibleText(calls.notifications).includes(token), false);
}

async function testSharedNetworkDoesNotClaimAnotherSlot() {
  const token = 'pgnfw_shared_network_not_real';
  for (const trigger of ['PO0 官方防火墙状态（只读）', '仅官方防火墙强制上报', 'PO0 防火墙上报状态', 'schedule', 'network']) {
    for (const existingSlot of [1, null]) {
      const run = createContext({
        trigger, env: { PO0_FIREWALL_TOKENS: token + '@0|新设备|600' },
        httpGet() { return response(officialPayload({ whitelist: [{ ip: '203.0.113.0/24', slot: existingSlot }] })); },
        httpPost() { return response({ error: 'slot conflict' }, 403); },
      });
      const result = await runEgernReport(run.ctx);
      const official = await officialStateOf(run.storage);
      assert.equal(run.calls.get.length, 1);
      assert.equal(run.calls.post.length, 0, trigger + ' must reuse the already authorized network');
      assert.equal(official.ok, true);
      assert.equal(official.successCount, 1);
      assert.equal(official.entries[0].status, 'shared');
      assert.equal(official.entries[0].currentInWhitelist, true);
      assert.equal(official.entries[0].fixedSlot, 0, 'retain configured slot for the next network');
      assert.equal(official.entries[0].coveredSlot, existingSlot);
      if (result?.type === 'widget') assert.match(visibleText(result), /共用/);
      assert.equal(visibleText({ official, result, logs: run.calls.logs, notifications: run.calls.notifications }).includes(token), false);
      assert.equal(run.calls.notifications.length, 0, 'sharing an existing network is not a new write');
      const saved = JSON.parse(await run.storage.get(CONFIG_STORAGE_KEY));
      assert.match(saved.values.PO0_FIREWALL_TOKENS, /@0/);
      const switched = createContext({
        trigger: 'network', storage: run.storage,
        httpGet() { return response(officialPayload({ currentIp: '198.51.100.27/24', whitelist: [{ ip: '203.0.113.0/24', slot: existingSlot }] })); },
        httpPost(url) {
          assert.equal(url, API_BASE + '/' + token + '/add?slot=0');
          return response(officialPayload({ currentIp: '198.51.100.27/24', whitelist: [{ ip: '198.51.100.0/24', slot: 0 }] }));
        },
      });
      await runEgernReport(switched.ctx);
      assert.equal(switched.calls.post.length, 1);
      assert.equal((await officialStateOf(run.storage)).entries[0].status, 'updated');
    }
  }
  const sameSlot = createContext({
    env: { PO0_FIREWALL_TOKENS: token + '@0' },
    httpGet() { return response(officialPayload({ whitelist: [{ ip: '203.0.113.0/24', slot: 0 }] })); },
  });
  await runEgernReport(sameSlot.ctx);
  assert.equal(sameSlot.calls.post.length, 0, 'compare /24 networks, not the last IPv4 octet');
  assert.equal((await officialStateOf(sameSlot.storage)).entries[0].status, 'hit');
}

async function testPost403RechecksOnceWithoutRepeatingWrite() {
  const token = 'pgnfw_post_403_not_real';
  for (const confirmed of [true, false]) {
    for (const thrown of [true, false]) {
      const run = createContext({
        env: { PO0_FIREWALL_TOKENS: token + '@0' },
        httpGet(url, options, calls) {
          assert.equal(options.policy, 'DIRECT');
          return response(officialPayload({ whitelist: confirmed && calls.get.length > 1 ? [{ ip: '203.0.113.0/24', slot: 1 }] : [] }));
        },
        httpPost(url, options) {
          assert.equal(options.policy, 'DIRECT');
          if (thrown) throw new Error('status: 403, body: secret ' + token + ' Bearer private-value');
          return response({ error: token + ' Bearer private-value' }, 403);
        },
      });
      const result = await runEgernReport(run.ctx);
      const state = await officialStateOf(run.storage);
      assert.deepEqual(run.calls.order, ['GET ' + API_BASE + '/' + token, 'POST ' + API_BASE + '/' + token + '/add?slot=0', 'GET ' + API_BASE + '/' + token]);
      assert.equal(state.ok, confirmed);
      assert.equal(state.entries[0].status, confirmed ? 'shared' : 'error');
      if (!confirmed) assert.match(state.entries[0].error, /加白失败（HTTP 403）/);
      const visible = visibleText({ state, result, logs: run.calls.logs, notifications: run.calls.notifications });
      assert(!visible.includes(token));
      assert(!visible.includes('private-value'));
    }
  }
  const failedRecheck = createContext({
    httpGet(url, options, calls) {
      if (calls.get.length > 1) throw new Error('verification unavailable');
      return response(officialPayload());
    },
    httpPost() { return response({}, 403); },
  });
  await runEgernReport(failedRecheck.ctx);
  assert.equal(failedRecheck.calls.post.length, 1);
  assert.match((await officialStateOf(failedRecheck.storage)).entries[0].error, /加白失败（HTTP 403）/);
}

async function testGet403DoesNotPostOrAssumeSlotConflict() {
  const token = 'pgnfw_get_403_not_real';
  const run = createContext({
    env: { PO0_FIREWALL_TOKENS: token },
    httpGet() { return response({ error: token }, 403); },
  });
  await runEgernReport(run.ctx);
  const state = await officialStateOf(run.storage);
  assert.equal(run.calls.get.length, 1);
  assert.equal(run.calls.post.length, 0);
  assert.match(state.entries[0].error, /查询失败（HTTP 403）/);
  assert.doesNotMatch(state.entries[0].error, /槽位冲突|pgnfw_/);
}

async function testWidgetAndReportStatusInitializeSavedToken() {
  const token = 'pgnfw_egern_widget_initialize_not_real';
  const now = 1000000000;
  globalThis.__PO0_EGERN_TEST_NOW = now;
  for (const scenario of [
    { trigger: 'PO0 防火墙上报状态', widgetFamily: 'systemMedium', ssid: 'CafeWiFi' },
    { trigger: 'PO0 防火墙上报状态', widgetFamily: 'systemMedium', ssid: 'HomeWiFi' },
    { trigger: 'PO0 防火墙上报状态', ssid: 'HomeWiFi' },
    { trigger: 'PO0 SSH 上报状态', widgetFamily: 'systemMedium', ssid: 'CafeWiFi' },
    { trigger: 'PO0 SSH 上报状态', widgetFamily: 'systemMedium', ssid: 'HomeWiFi' },
    { trigger: 'PO0 SSH 上报状态', ssid: 'CafeWiFi' },
    { trigger: 'schedule', widgetFamily: 'systemMedium', ssid: 'HomeWiFi' },
  ]) {
    const storage = createStorage({
      [CONFIG_STORAGE_KEY]: JSON.stringify({ version: 1, values: {
        PO0_FIREWALL_TOKENS: token + '@2', SKIP_WIFI_SSIDS: 'HomeWiFi',
      } }),
      [OFFICIAL_STORAGE_KEY]: JSON.stringify({
        version: 1, ok: true, status: 'success', entries: [],
        lastAttemptAt: new Date(now - 1000).toISOString(),
      }),
    });
    const readOnly = createContext({
      trigger: 'PO0 官方防火墙状态（只读）', storage, ssid: scenario.ssid,
    });
    const before = await runEgernReport(readOnly.ctx);
    assert.equal(readOnly.calls.get.length, 1);
    assert.equal(readOnly.calls.post.length, 0);
    assert.match(visibleText(before), /当前出口未加白（只读）/);

    let whitelist = [];
    const refresh = createContext({
      ...scenario, storage,
      env: { PO0_FIREWALL_TOKENS: 'pgnfw_synced_other_device_not_real@4' },
      httpGet(url, options) {
        assert.equal(url, API_BASE + '/' + token);
        assert.equal(options.policy, 'DIRECT');
        return response(officialPayload({ whitelist }));
      },
      httpPost(url, options) {
        assert.equal(url, API_BASE + '/' + token + '/add?slot=2');
        assert.equal(options.policy, 'DIRECT');
        whitelist = [{ ip: '203.0.113.10/24', slot: 2 }];
        return response(officialPayload({ whitelist }));
      },
    });
    const widget = await runEgernReport(refresh.ctx);
    assert.equal(widget.type, 'widget');
    assert.deepEqual(refresh.calls.order, ['GET ' + API_BASE + '/' + token, 'POST ' + API_BASE + '/' + token + '/add?slot=2']);
    const official = await officialStateOf(storage);
    assert.equal(official.status, 'success');
    assert.equal(official.entries[0].status, 'updated');
    assert.equal(official.lastAttemptAt, new Date(now).toISOString());
    assert.equal(official.lastSuccessAt, new Date(now).toISOString());
    assert.match(visibleText(widget), /已加白/);
    assert.doesNotMatch(visibleText(widget), /当前出口未加白/);

    await runEgernReport(refresh.ctx);
    assert.equal(refresh.calls.get.length, 2, 'each refresh must check even within the automatic interval');
    assert.equal(refresh.calls.post.length, 1, 'a matching slot must not be written again');
    assert.equal((await officialStateOf(storage)).entries[0].status, 'hit');
    assert.equal(visibleText({ widget, official, logs: refresh.calls.logs, notifications: refresh.calls.notifications }).includes(token), false);
  }
}

async function testValidMissingStatusReturnsSuccessWithoutPost() {
  const token = 'pgnfw_egern_status_not_real';
  const { ctx, calls, storage } = createContext({
    trigger: 'PO0 官方防火墙状态（只读）',
    env: { PO0_FIREWALL_TOKENS: token },
    httpGet() {
      return response(officialPayload({ whitelist: [{ ip: '198.51.100.1/24', slot: null }] }));
    },
    httpPost() { throw new Error('status must not POST'); },
  });
  const result = await runEgernReport(ctx);
  const official = await officialStateOf(storage);
  assert.equal(official.ok, true);
  assert.equal(official.status, 'status');
  assert.equal(official.entries[0].status, 'missing');
  assert.equal(result.type, 'widget');
  assert.equal(calls.post.length, 0);
}

async function testGetFailureNeverPostsAndDoesNotLeakToken() {
  const token = 'pgnfw_egern_get_failure_not_real';
  const { ctx, calls, storage } = createContext({
    env: { PO0_FIREWALL_TOKENS: token },
    httpGet() { throw new Error(`transport included ${token}`); },
    httpPost() { throw new Error('GET failure must not POST'); },
  });
  const result = await runEgernReport(ctx);
  assert.equal(result.ok, false);
  assert.equal(calls.get.length, 1);
  assert.equal(calls.post.length, 0);
  assert.equal((await officialStateOf(storage)).entries[0].status, 'error');
  assert.equal(visibleText(result).includes(token), false);
  assert.equal(visibleText(calls.notifications).includes(token), false);
  assert.equal(visibleText(calls.logs).includes(token), false);
}

async function testHttpGetFailureNeverPosts() {
  const token = 'pgnfw_egern_http_failure_not_real';
  const { ctx, calls } = createContext({
    env: { PO0_FIREWALL_TOKENS: token },
    httpGet() { return response({ error: 'not exposed' }, 503); },
    httpPost() { throw new Error('HTTP GET failure must not POST'); },
  });
  const result = await runEgernReport(ctx);
  assert.equal(result.ok, false);
  assert.equal(calls.get.length, 1);
  assert.equal(calls.post.length, 0);
  assert.equal(visibleText(result).includes(token), false);
}

async function testUnexpectedErrorRedactsTokensAndBearer() {
  const token = 'pgnfw_egern_outer_exception_not_real';
  const bearer = 'egern-bearer-secret-not-real';
  const storage = createStorage();
  const originalSet = storage.set.bind(storage);
  storage.set = async (key, value) => {
    if (key === CONFIG_STORAGE_KEY) {
      throw new Error('unexpected ' + token + ' Authorization: Bearer ' + bearer);
    }
    return originalSet(key, value);
  };
  const { ctx, calls } = createContext({
    trigger: 'status',
    storage,
    env: { PO0_FIREWALL_TOKENS: token },
  });
  const result = await runEgernReport(ctx);
  const state = await storage.get(STATE_STORAGE_KEY);
  const lastError = await storage.get('po0-ssh-ip-report:last-error');
  const visible = visibleText({
    result,
    notifications: calls.notifications,
    logs: calls.logs,
    state,
    lastError,
  });
  assert.equal(visible.includes(token), false);
  assert.equal(visible.includes(bearer), false);
  assert.match(visible, /Bearer \[REDACTED\]/);
  assert.match(visible, /\[REDACTED\]/);
}

async function testMalformedAndDuplicateTokensFailClosed() {
  for (const value of [
    'pgnfw_egern_bad,pgnfw_egern_bad',
    'pgnfw_egern_bad@0,pgnfw_egern_bad@0',
    'pgnfw_egern_bad@0,pgnfw_egern_bad@1',
    'pgnfw_egern_bad@5',
  ]) {
    const { ctx, calls } = createContext({
      env: { PO0_FIREWALL_TOKENS: value },
      httpGet() { throw new Error('malformed token reached network'); },
    });
    const result = await runEgernReport(ctx);
    assert.equal(result.ok, false, value);
    assert.equal(calls.get.length, 0, value);
    assert.equal(calls.post.length, 0, value);
    assert.equal(visibleText(result).includes(value), false, value);
  }
}

async function testDuplicateNumericResponseSlotIsRejectedWithoutPost() {
  const token = 'pgnfw_egern_duplicate_slot_not_real';
  const { ctx, calls } = createContext({
    env: { PO0_FIREWALL_TOKENS: token },
    httpGet() {
      return response(officialPayload({ whitelist: [
        { ip: '203.0.113.10/24', slot: 0 },
        { ip: '198.51.100.20/24', slot: 0 },
      ] }));
    },
    httpPost() { throw new Error('invalid response must not POST'); },
  });
  const result = await runEgernReport(ctx);
  assert.equal(result.ok, false);
  assert.equal(calls.post.length, 0);
  assert.equal(visibleText(result).includes(token), false);
}

async function testMalformedOfficialPayloadFailsClosedWithoutPost() {
  const token = 'pgnfw_egern_bad_payload_not_real';
  for (const payload of [
    officialPayload({ currentIp: '203.0.113.10/32' }),
    officialPayload({ limit: 6 }),
    officialPayload({ whitelist: [{ ip: '203.0.113.10/24', slot: 7 }] }),
    { enabled: false, currentIp: '203.0.113.10/24', limit: 5, whitelist: [] },
  ]) {
    const { ctx, calls } = createContext({
      env: { PO0_FIREWALL_TOKENS: token },
      httpGet() { return response(payload); },
      httpPost() { throw new Error('malformed GET must not POST'); },
    });
    const result = await runEgernReport(ctx);
    assert.equal(result.ok, false);
    assert.equal(calls.get.length, 1);
    assert.equal(calls.post.length, 0);
    assert.equal(visibleText(result).includes(token), false);
  }
}

async function testSharedRunLockAcrossModesAndContexts() {
  const token = 'pgnfw_egern_shared_lock_not_real';
  const now = Date.now();
  globalThis.__PO0_EGERN_TEST_NOW = now;
  const gate = deferred();
  const entered = deferred();
  const storage = createStorage();
  let held = false;
  const statusRun = createContext({
    trigger: 'official firewall status',
    storage,
    env: { PO0_FIREWALL_TOKENS: token + '@0' },
    httpGet: async () => {
      if (!held) {
        held = true;
        entered.resolve();
        await gate.promise;
      }
      return response(officialPayload({
        whitelist: [{ ip: '203.0.113.10/24', slot: 0 }],
      }));
    },
    httpPost() {
      throw new Error('status must not POST');
    },
  });
  const runningStatus = runEgernReport(statusRun.ctx);
  await entered.promise;

  const runningForce = createContext({
    trigger: 'force',
    storage,
    env: { PO0_FIREWALL_TOKENS: token + '@0' },
    httpGet() {
      throw new Error('busy force must not GET');
    },
    httpPost() {
      throw new Error('busy force must not POST');
    },
  });
  const runningSchedule = createContext({
    trigger: 'schedule',
    storage,
    env: { PO0_FIREWALL_TOKENS: token + '@0' },
    httpGet() {
      throw new Error('busy schedule must not GET');
    },
    httpPost() {
      throw new Error('busy schedule must not POST');
    },
  });
  const [forceBusy, scheduleBusy] = await Promise.all([
    runEgernReport(runningForce.ctx),
    runEgernReport(runningSchedule.ctx),
  ]);
  assert.equal(forceBusy.status, 'busy', 'active status lock must block manual force');
  assert.equal(scheduleBusy.status, 'busy', 'active status lock must block scheduled run');
  assert.equal(runningForce.calls.get.length + runningForce.calls.post.length, 0);
  assert.equal(runningSchedule.calls.get.length + runningSchedule.calls.post.length, 0);

  gate.resolve();
  await runningStatus;
  assert.equal(await storage.get(REPORT_LOCK_KEY), null, 'completed status must release its owner lock');

  const forceAfterStatus = createContext({
    trigger: 'force',
    storage,
    env: { PO0_FIREWALL_TOKENS: token + '@0' },
    httpGet: async () => response(officialPayload({
      whitelist: [{ ip: '203.0.113.10/24', slot: 0 }],
    })),
    httpPost() {
      throw new Error('matching force must not POST');
    },
  });
  const forceResult = await runEgernReport(forceAfterStatus.ctx);
  assert.notEqual(forceResult.status, 'busy', 'force may run immediately after status completion');
  assert.equal(forceAfterStatus.calls.get.length, 1);

  const autoGate = deferred();
  const autoEntered = deferred();
  const autoStorage = createStorage();
  let autoHeld = false;
  const automaticRun = createContext({
    trigger: 'schedule',
    storage: autoStorage,
    env: { PO0_FIREWALL_TOKENS: token + '@0' },
    httpGet: async () => {
      if (!autoHeld) {
        autoHeld = true;
        autoEntered.resolve();
        await autoGate.promise;
      }
      return response(officialPayload({ whitelist: [] }));
    },
    httpPost: async () => response(officialPayload({
      whitelist: [{ ip: '203.0.113.10/24', slot: 0 }],
    })),
  });
  const runningAutomatic = runEgernReport(automaticRun.ctx);
  await autoEntered.promise;

  const runningStatusAfterAuto = createContext({
    trigger: 'status',
    storage: autoStorage,
    env: { PO0_FIREWALL_TOKENS: token + '@0' },
    httpGet() {
      throw new Error('busy status must not GET');
    },
    httpPost() {
      throw new Error('busy status must not POST');
    },
  });
  const statusBusy = await runEgernReport(runningStatusAfterAuto.ctx);
  assert.equal(statusBusy.type, 'widget', 'busy status must render a Widget DSL root');
  assert.match(visibleText(statusBusy), /正在上报/);
  assert.equal(runningStatusAfterAuto.calls.get.length + runningStatusAfterAuto.calls.post.length, 0);

  autoGate.resolve();
  await runningAutomatic;
  assert.equal(await autoStorage.get(REPORT_LOCK_KEY), null, 'completed scheduled run must release its owner lock');

  const statusAfterAutomatic = createContext({
    trigger: 'status',
    storage: autoStorage,
    env: { PO0_FIREWALL_TOKENS: token + '@0' },
    httpGet: async () => response(officialPayload({
      whitelist: [{ ip: '203.0.113.10/24', slot: 0 }],
    })),
    httpPost() {
      throw new Error('status must not POST');
    },
  });
  const statusResult = await runEgernReport(statusAfterAutomatic.ctx);
  assert.notEqual(statusResult.status, 'busy', 'status may run immediately after scheduled completion');
  assert.equal(statusAfterAutomatic.calls.get.length, 1);
}

async function testEgernLockExpiryAndOwnerReplacement() {
  const token = 'pgnfw_egern_lock_expiry_not_real';
  const now = Date.now();
  globalThis.__PO0_EGERN_TEST_NOW = now;
  const expiredStorage = createStorage({
    [REPORT_LOCK_KEY]: JSON.stringify({
      version: 1,
      owner: 'expired-owner',
      expiresAt: now - 1,
    }),
  });
  const expiredRun = createContext({
    trigger: 'force',
    storage: expiredStorage,
    env: { PO0_FIREWALL_TOKENS: token + '@0' },
    httpGet: async () => response(officialPayload({
      whitelist: [{ ip: '203.0.113.10/24', slot: 0 }],
    })),
    httpPost() {
      throw new Error('expired-lock run must not POST');
    },
  });
  const expiredResult = await runEgernReport(expiredRun.ctx);
  assert.notEqual(expiredResult.status, 'busy', 'expired lock must be recoverable');
  assert.equal(expiredRun.calls.get.length, 1);
  assert.equal(await expiredStorage.get(REPORT_LOCK_KEY), null, 'recovered expired lock must release after completion');

  let replaced = false;
  const raceStorage = createStorage();
  const originalSet = raceStorage.set;
  raceStorage.set = async (key, value) => {
    await originalSet(key, value);
    if (key === STATE_STORAGE_KEY && !replaced) {
      replaced = true;
      await originalSet(REPORT_LOCK_KEY, JSON.stringify({
        version: 1,
        owner: 'replacement-owner',
        expiresAt: now + 120000,
      }));
    }
  };
  const raceRun = createContext({
    trigger: 'official firewall status',
    storage: raceStorage,
    env: { PO0_FIREWALL_TOKENS: token + '@0' },
    httpGet: async () => response(officialPayload({
      whitelist: [{ ip: '203.0.113.10/24', slot: 0 }],
    })),
    httpPost() {
      throw new Error('status must not POST');
    },
  });
  await runEgernReport(raceRun.ctx);
  const replacement = JSON.parse(await raceStorage.get(REPORT_LOCK_KEY));
  assert.equal(replacement.owner, 'replacement-owner', 'old owner must not release a replacement lock');

  const blockedByReplacement = createContext({
    trigger: 'force',
    storage: raceStorage,
    env: { PO0_FIREWALL_TOKENS: token + '@0' },
    httpGet() {
      throw new Error('replacement lock must block GET');
    },
    httpPost() {
      throw new Error('replacement lock must block POST');
    },
  });
  const blockedResult = await runEgernReport(blockedByReplacement.ctx);
  assert.equal(blockedResult.status, 'busy', 'replacement owner lock must remain active');
  assert.equal(blockedByReplacement.calls.get.length + blockedByReplacement.calls.post.length, 0);
}


async function testIndependentOfficialDueUsesLastAttemptAndManualBypassesDue() {
  const token = 'pgnfw_egern_due_not_real';
  const storage = createStorage();
  let getCount = 0;
  const get = () => {
    getCount += 1;
    return response(officialPayload({ whitelist: [{ ip: '203.0.113.10/24', slot: null }] }));
  };

  globalThis.__PO0_EGERN_TEST_NOW = 1000000000;
  await runEgernReport(createContext({ trigger: 'generic manual now', env: { PO0_FIREWALL_TOKENS: token }, storage, httpGet: get }).ctx);
  assert.equal(getCount, 1);
  const first = await officialStateOf(storage);
  assert.equal(first.lastAttemptAt, new Date(1000000000).toISOString());

  globalThis.__PO0_EGERN_TEST_NOW = 1000100000;
  const scheduled = createContext({ trigger: 'schedule', env: { PO0_FIREWALL_TOKENS: token }, storage, httpGet: get });
  await runEgernReport(scheduled.ctx);
  assert.equal(getCount, 1);

  globalThis.__PO0_EGERN_TEST_NOW = 1000600000;
  await runEgernReport(createContext({ trigger: 'schedule', env: { PO0_FIREWALL_TOKENS: token }, storage, httpGet: get }).ctx);
  assert.equal(getCount, 2);

  globalThis.__PO0_EGERN_TEST_NOW = 1000600001;
  await runEgernReport(createContext({ trigger: 'generic manual now', env: { PO0_FIREWALL_TOKENS: token }, storage, httpGet: get }).ctx);
  assert.equal(getCount, 3);
  await runEgernReport(createContext({ trigger: 'force', env: { PO0_FIREWALL_TOKENS: token }, storage, httpGet: get }).ctx);
  assert.equal(getCount, 4);
  delete globalThis.__PO0_EGERN_TEST_NOW;
}

async function testSsidSkipsOfficialAndExistingSshTogether() {
  const token = 'pgnfw_egern_ssid_not_real';
  const { ctx, calls, storage } = createContext({
    trigger: 'schedule',
    ssid: 'HomeWiFi',
    env: {
      PO0_FIREWALL_TOKENS: token,
      PO0_HOST: 'po0.example.com',
      SSH_REPORT_TOKEN: 'ssh-token-not-real',
      PO0_PASSWORD: 'password-not-real',
      SKIP_WIFI_SSIDS: 'HomeWiFi',
      IP_CHECK_URLS: 'https://example.com/ip',
    },
    httpGet() { throw new Error('SSID skip must not HTTP'); },
    sshConnect() { throw new Error('SSID skip must not SSH'); },
  });
  const result = await runEgernReport(ctx);
  assert.equal(result.skipped, true);
  assert.equal(result.skipType, 'wifi-ssid');
  assert.equal(calls.get.length, 0);
  assert.equal(calls.post.length, 0);
  assert.equal(calls.ssh, 0);
  assert.equal((await storage.get(OFFICIAL_STORAGE_KEY)), null);
}

function testEgernTimeoutBudget() {
  assert.equal((yamlSource.match(/timeout: 90/g) || []).length, 8);
  assert.equal((yamlSource.match(/timeout: 30/g) || []).length, 0);
}

function testEgernWidgetBindingsStayCompatible() {
  const widgets = yamlSource.slice(yamlSource.indexOf('\nwidgets:'));
  assert(widgets.includes('name: PO0 防火墙上报状态'));
  assert(widgets.includes('script_name: PO0 防火墙上报状态'));
  assert(yamlSource.includes('      name: PO0 防火墙上报状态'));
  for (const removed of ['PO0 SSH 上报状态', '强制上报 PO0 防火墙', 'PO0 防火墙本机设备 ID']) {
    assert(!yamlSource.includes('      name: ' + removed), 'redundant entries must not be republished');
  }
  assert(!yamlSource.includes('  - http_request:'));
  assert.equal((widgets.match(/  - name:/g) || []).length, 1, 'the module must publish exactly one widget');
  assert(!yamlSource.includes('name: 切换'), 'published UI must use explicit enable/disable actions');
}

function testEgernScriptCopiesStaySynchronized() {
  assert.equal(compatibilitySource, source);
}


async function testSavedSlotSurvivesSyncedEnvironment() {
  const token = 'pgnfw_device_local_mock';
  const storage = createStorage({
    [CONFIG_STORAGE_KEY]: JSON.stringify({ version: 1, values: { PO0_FIREWALL_TOKENS: token + '@0' } }),
    'po0-ssh-ip-report:device-id': 'this-iphone',
  });
  const run = createContext({ storage, env: { PO0_FIREWALL_TOKENS: 'pgnfw_other_device_mock@4', DEVICE_ID_SETUP: 'other-ipad' } });
  await runEgernReport(run.ctx);
  assert.equal(run.calls.get[0].url, API_BASE + '/' + token);
  assert.equal(run.calls.post[0].url, API_BASE + '/' + token + '/add?slot=0');
  assert.equal(await storage.get('po0-ssh-ip-report:device-id'), 'this-iphone');
  assert.equal(JSON.parse(await storage.get(CONFIG_STORAGE_KEY)).values.PO0_FIREWALL_TOKENS, token + '@0');
}


async function testFlexibleOfficialSeparators() {
  const { ctx, calls, storage } = createContext({
    env: { PO0_FIREWALL_TOKENS: ' ,pgnfw_a@0 pgnfw_b@1\npgnfw_c@2; pgnfw_d@3，pgnfw_e@4；pgnfw_f, ' },
    trigger: '保存本机 PO0 官方防火墙配置',
  });
  const result = await runEgernReport(ctx);
  assert.ok(JSON.parse(await storage.get(CONFIG_STORAGE_KEY)).values.PO0_FIREWALL_TOKENS.includes('pgnfw_f'));
  assert.equal(calls.get.length, 0);
  assert.equal(calls.post.length, 0);
}

async function checkIndependentChannelControlsAndNames(actionNames) {
  const values = { PO0_HOST: 'po0.example.com', SSH_REPORT_TOKEN: 'ssh-fixture', PO0_PASSWORD: 'password-fixture', IP_CHECK_URLS: 'https://example.com/ip', SKIP_WIFI_SSIDS: 'HomeWiFi', PO0_FIREWALL_TOKENS: 'pgnfw_first,pgnfw_second', PO0_FIREWALL_NAMES: '家庭;办公室', TTL_SECONDS: '7200' };
  const storage = createStorage({ [CONFIG_STORAGE_KEY]: JSON.stringify({ version: 1, values }) });
  const commands = [];
  const call = async (trigger, overrides = {}, ssid = '') => {
    const env = { IP_CHECK_URLS: 'https://example.com/ip', SKIP_WIFI_SSIDS: 'HomeWiFi', ...overrides };
    const fixture = createContext({ storage, trigger: actionNames[trigger] || trigger, env, ssid,
      httpGet(url) { return url.includes('/api/firewall/') ? response(officialPayload({ whitelist: [{ ip: '203.0.113.10/24', slot: 0 }] })) : response({ ip: '203.0.113.50' }); },
      sshConnect() { return { async exec(command) { commands.push(command); return { code: 0, stdout: 'SSH OK' }; }, async close() {} }; },
    });
    const result = await runEgernReport(fixture.ctx);
    return { ...fixture, result };
  };
  let action = await call('保存本机 PO0 官方防火墙配置', { PO0_FIREWALL_TOKENS: 'pgnfw_second,pgnfw_first@0' });
  assert.equal(action.calls.get.length, 0);
  assert.equal(JSON.parse(await storage.get(CONFIG_STORAGE_KEY)).values.PO0_FIREWALL_NAMES, '办公室;家庭');
  assert.equal(JSON.parse(await storage.get(CONFIG_STORAGE_KEY)).values.TTL_SECONDS, '7200');
  action = await call('切换自建 PO0 自动上报');
  assert.equal(action.calls.get.length, 0);
  let report = await call('schedule');
  assert.equal(report.calls.ssh, 0);
  assert.equal(report.calls.get.length, 2);
  assert.deepEqual((await officialStateOf(storage)).entries.map(x => x.name), ['办公室', '家庭']);
  await call('切换官方防火墙自动上报');
  report = await call('schedule');
  assert.equal(report.calls.get.length, 0);
  assert.equal(report.calls.ssh, 0);
  report = await call('仅自建 PO0 立即上报');
  assert.equal(report.calls.ssh, 1);
  assert(!report.calls.get.some(x => x.url.includes('/api/firewall/')));
  assert(commands[0].includes("'7200'"), 'existing custom SSH TTL must still enter the original command');
  report = await call('仅官方防火墙立即上报', {}, 'HomeWiFi');
  assert.equal(report.calls.ssh, 0);
  assert.equal(report.calls.get.length, 2, 'official-only force must bypass disabled automatic flags and SSID');
  await call('切换自建 PO0 自动上报');
  report = await call('schedule', {}, 'HomeWiFi');
  assert.equal(report.calls.get.length, 0, 'SSID must still guard the active Worker lane');
  await call('清除本机自建 PO0 配置');
  let saved = JSON.parse(await storage.get(CONFIG_STORAGE_KEY)).values;
  assert.equal(saved.PO0_HOST, undefined);
  assert.equal(saved.PO0_FIREWALL_TOKENS, 'pgnfw_second,pgnfw_first@0');
  assert.equal(saved.SKIP_WIFI_SSIDS, undefined, 'SSID comes from module parameters');
  report = await call('schedule', values);
  assert.equal(report.calls.ssh, 0, 'synced env must not restore cleared SSH credentials');
  await call('清除本机全部 PO0 上报配置');
  report = await call('schedule', values);
  assert.equal(report.calls.get.length, 0, 'clear-all must not bootstrap again from synced env');
  const view = await call('查看本机上报设置');
  assert.equal(view.calls.get.length, 0);
  assert.equal(view.calls.ssh, 0);
}

function publishedActions() {
  return [...yamlSource.matchAll(/^  - (generic|schedule|network):\r?\n      name: ([^\r\n]+)/gm)]
    .map(match => ({ type: match[1], name: match[2] }));
}

function nativeActionFixture(action, overrides = {}) {
  const fixture = createContext(overrides);
  // Use the documented native context, not invented trigger/type properties.
  delete fixture.ctx.name;
  delete fixture.ctx.trigger;
  fixture.ctx.script = { name: action.name };
  if (action.type === 'schedule') fixture.ctx.cron = '*/10 * * * *';
  return fixture;
}

const actionValues = {
  PO0_FIREWALL_TOKENS: 'pgnfw_action_fixture@0', PO0_FIREWALL_NAMES: '官方测试目标',
  SSH_REPORT_TARGETS: 'phone-source|po0.example.com||||ssh-action-fixture|audit-note|7200',
  PO0_PASSWORD: 'mock-password', IP_CHECK_URLS: 'https://example.com/ip',
  SKIP_WIFI_SSIDS: 'HomeWiFi', WORKER_AUTO_ENABLED: 'false', OFFICIAL_AUTO_ENABLED: 'false',
};

function actionHttpGet(url) {
  return url.includes('/api/firewall/')
    ? response(officialPayload({ whitelist: [{ ip: '203.0.113.10/24', slot: 0 }] }))
    : response({ ip: '203.0.113.50' });
}

async function testNetworkChangesBypassOptionalTimer() {
  for (const enabled of ['true', 'false']) {
    const storage = createStorage();
    const env = { OFFICIAL_INTERVAL_SECONDS: '900', OFFICIAL_TIMER_ENABLED: enabled };
    const get = () => response(officialPayload({ whitelist: [{ ip: '203.0.113.10/24', slot: null }] }));
    globalThis.__PO0_EGERN_TEST_NOW = 1000000000;
    await runEgernReport(createContext({ storage, env, httpGet: get }).ctx);
    globalThis.__PO0_EGERN_TEST_NOW += 600000;
    const early = createContext({ storage, env, trigger: 'schedule', httpGet: get });
    await runEgernReport(early.ctx);
    assert.equal(early.calls.get.length, 0, 'custom 900s timer must not fire at 600s');
    globalThis.__PO0_EGERN_TEST_NOW += 400000;
    const due = createContext({ storage, env, trigger: 'schedule', httpGet: get });
    await runEgernReport(due.ctx);
    assert.equal(due.calls.get.length, enabled === 'true' ? 1 : 0, 'timer can be disabled');
    globalThis.__PO0_EGERN_TEST_NOW += 1;
    const network = createContext({ storage, env, trigger: 'network', httpGet: get });
    await runEgernReport(network.ctx);
    assert.equal(network.calls.get.length, 1, 'network event must bypass timer interval and timer disable');
  }
  delete globalThis.__PO0_EGERN_TEST_NOW;
}


async function testInlineOfficialTargetsPersistAndMatchNames() {
  const storage = createStorage();
  const env = { PO0_FIREWALL_TOKENS: 'pgnfw_inline_one@0 | 手机 | 600\npgnfw_inline_two@2|Office Firewall|0' };
  const save = createContext({ storage, env, trigger: '保存本机 PO0 官方防火墙配置' });
  const result = await runEgernReport(save.ctx);
  assert.match(visibleText(result), /手机/);
  assert.match(visibleText(result), /Office Firewall/);
  assert.match(visibleText(result), /上报间隔 600 秒/);
  assert.equal(save.calls.get.length + save.calls.post.length, 0);
  let values = JSON.parse(await storage.get(CONFIG_STORAGE_KEY)).values;
  assert.equal(values.PO0_FIREWALL_NAMES, '手机;Office Firewall');
  assert.equal(values.PO0_FIREWALL_TOKENS, 'pgnfw_inline_one@0||600\npgnfw_inline_two@2||0');
  const synced = createContext({ storage, trigger: 'PO0 防火墙上报状态', widgetFamily: 'systemLarge',
    env: { PO0_FIREWALL_TOKENS: 'pgnfw_inline_two@4|Office New|60\npgnfw_inline_one@3|手机新名|0' },
    httpGet(url) { return response(officialPayload({ whitelist: [{ ip: '203.0.113.10/24', slot: url.endsWith('one') ? 0 : 2 }] })); },
  });
  const widget = await runEgernReport(synced.ctx);
  assert.match(visibleText(widget), /手机新名/); assert.match(visibleText(widget), /Office New/);
  assert.equal(synced.calls.get.length, 2); assert.equal(synced.calls.post.length, 0);
  assert.deepEqual(JSON.parse(await storage.get(CONFIG_STORAGE_KEY)).values, values, 'sync only changes display, never saved credentials/slots/timers');
  for (const entry of await officialStateOf(storage).then(state => state.entries)) assert(!visibleText(entry).includes('pgnfw_'));
  const clear = createContext({ storage, trigger: '保存本机 PO0 官方防火墙配置', env: { PO0_FIREWALL_TOKENS: '', PO0_FIREWALL_NAMES: '-' } });
  await runEgernReport(clear.ctx);
  assert.equal(JSON.parse(await storage.get(CONFIG_STORAGE_KEY)).values.PO0_FIREWALL_NAMES, undefined);
  assert.equal(JSON.parse(await storage.get(CONFIG_STORAGE_KEY)).values.PO0_FIREWALL_TOKENS, values.PO0_FIREWALL_TOKENS);
  const rename = createContext({ storage, trigger: '保存本机 PO0 官方防火墙配置', env: { PO0_FIREWALL_TOKENS: '', PO0_FIREWALL_NAMES: '甲;乙' } });
  await runEgernReport(rename.ctx);
  const reorder = createContext({ storage, trigger: '保存本机 PO0 官方防火墙配置', env: { PO0_FIREWALL_TOKENS: 'pgnfw_inline_two@3||1200;pgnfw_inline_one@0||0' } });
  await runEgernReport(reorder.ctx);
  values = JSON.parse(await storage.get(CONFIG_STORAGE_KEY)).values;
  assert.equal(values.PO0_FIREWALL_NAMES, '乙;甲', 'blank inline names follow account identity');
}

async function testInlineOfficialTargetValidation() {
  for (const [row, expected] of [
    ['pgnfw_invalid@0|名称|59', /60\.\.86400/],
    ['pgnfw_invalid@0|名称|86401', /60\.\.86400/],
    ['pgnfw_invalid@0|名称|ttl=abc', /格式/],
    ['pgnfw_invalid@0|家庭|interval=59', /60\.\.86400/],
    ['pgnfw_invalid@0|家庭|interval=86401', /60\.\.86400/],
    ['pgnfw_invalid@0|家庭|timer=maybe', /timer=true 或 timer=false/],
    ['pgnfw_invalid@0|家庭|interval=600|interval=900', /不能重复/],
    ['pgnfw_invalid@0|名称|foo=bar', /格式/],
    ['pgnfw_invalid@0|家庭\npgnfw_invalid@2|重复', /重复/],
  ]) {
    const fixture = createContext({ env: { PO0_FIREWALL_TOKENS: row }, trigger: '保存本机 PO0 官方防火墙配置' });
    const result = await runEgernReport(fixture.ctx);
    assert.match(visibleText(result), expected);
    assert.doesNotMatch(visibleText(result), /pgnfw_invalid/);
    assert.equal(fixture.calls.get.length + fixture.calls.post.length, 0);
    assert.equal(await fixture.storage.get(CONFIG_STORAGE_KEY), null);
  }
  const run = createContext({ env: { PO0_FIREWALL_TOKENS: 'pgnfw_invalid|名称|59' } });
  assert.match(visibleText(await runEgernReport(run.ctx)), /上报间隔/);
  assert.equal(run.calls.get.length + run.calls.post.length, 0);
}

async function testPerAccountOfficialTimersAndReadonlyState() {
  const storage = createStorage();
  // Old inline interval/disabled flags cannot override the live channel setting.
  const env = { PO0_FIREWALL_TOKENS: 'pgnfw_fast|快|600\npgnfw_slow|慢|900\npgnfw_network|切网|0', OFFICIAL_INTERVAL_SECONDS: '900' };
  const accounts = ['pgnfw_fast', 'pgnfw_slow', 'pgnfw_network'];
  const hit = () => response(officialPayload({ whitelist: [{ ip: '203.0.113.10/24', slot: null }] }));
  async function runAt(seconds, trigger = 'schedule', overrides = {}) {
    globalThis.__PO0_EGERN_TEST_NOW = 1000000000 + seconds * 1000;
    const run = createContext({ storage, env: { ...env, ...overrides }, trigger, httpGet: hit });
    await runEgernReport(run.ctx);
    return run.calls.get.map(call => call.url.slice(API_BASE.length + 1));
  }
  assert.deepEqual(await runAt(0), accounts);
  assert.deepEqual(await runAt(600), []);
  const before = (await officialStateOf(storage)).entries.map(entry => entry.lastAttemptAt);
  assert.deepEqual(await runAt(700, 'PO0 官方防火墙状态（只读）'), accounts);
  assert.deepEqual((await officialStateOf(storage)).entries.map(entry => entry.lastAttemptAt), before);
  assert.deepEqual(await runAt(900), accounts);
  assert.deepEqual(await runAt(1500, 'schedule', {OFFICIAL_INTERVAL_SECONDS:'600'}), accounts, 'live interval change applies without save');
  assert.deepEqual(await runAt(2500, 'schedule', {OFFICIAL_TIMER_ENABLED:'false'}), []);
  assert.deepEqual(await runAt(2501, 'network', {OFFICIAL_TIMER_ENABLED:'false'}), accounts);
  const values = JSON.parse(await storage.get(CONFIG_STORAGE_KEY)).values;
  assert.equal(values.OFFICIAL_INTERVAL_SECONDS, undefined);
  assert.equal(values.OFFICIAL_TIMER_ENABLED, undefined);
}


async function testLegacyAccountTimesAndNewTarget() {
  const storage = createStorage();
  const env = { PO0_FIREWALL_TOKENS: 'pgnfw_existing@0|已有|interval=900', OFFICIAL_INTERVAL_SECONDS: '900' };
  globalThis.__PO0_EGERN_TEST_NOW = 1000000000;
  await runEgernReport(createContext({ storage, env }).ctx);
  const legacy = await officialStateOf(storage);
  for (const entry of legacy.entries) delete entry.lastAttemptAt;
  await storage.set(OFFICIAL_STORAGE_KEY, JSON.stringify(legacy));
  globalThis.__PO0_EGERN_TEST_NOW += 600000;
  const early = createContext({ storage, env, trigger: 'schedule' });
  await runEgernReport(early.ctx);
  assert.equal(early.calls.get.length, 0, 'legacy entries inherit the previous channel attempt time');
  const save = createContext({ storage, trigger: '保存本机 PO0 官方防火墙配置', env: { PO0_FIREWALL_TOKENS: env.PO0_FIREWALL_TOKENS + '\npgnfw_added@2|新增|interval=900' } });
  await runEgernReport(save.ctx);
  const added = createContext({ storage, env: {OFFICIAL_INTERVAL_SECONDS: '900'}, trigger: 'schedule', httpPost(url, options) {
    assert.equal(url, API_BASE + '/pgnfw_added/add?slot=2');
    assert.equal(options.body, undefined, 'local name/timer settings must not be sent to the API');
    return response(officialPayload({ whitelist: [{ ip: '203.0.113.10/24', slot: 2 }] }));
  } });
  await runEgernReport(added.ctx);
  assert.deepEqual(added.calls.get.map(call => call.url), [API_BASE + '/pgnfw_added'], 'new target must not wait for another account timer');
  globalThis.__PO0_EGERN_TEST_NOW += 300000;
  const existing = createContext({ storage, env: {OFFICIAL_INTERVAL_SECONDS: '900'}, trigger: 'schedule' });
  await runEgernReport(existing.ctx);
  assert.deepEqual(existing.calls.get.map(call => call.url), [API_BASE + '/pgnfw_existing']);
}


async function testOfficialIntervalDefaultsAndLegacyAlias() {
  for (const [row, normalized] of [
    ['pgnfw_simple@0|显示名称|600', 'pgnfw_simple@0||600'],
    ['pgnfw_simple@0|显示名称|ttl=600', 'pgnfw_simple@0||600'],
    ['pgnfw_simple@0|显示名称|0', 'pgnfw_simple@0||0'],
    ['pgnfw_simple@0|显示名称', 'pgnfw_simple@0'],
    ['pgnfw_simple@0|显示名称|', 'pgnfw_simple@0'],
    ['pgnfw_simple@0|显示名称|interval=900|timer=true', 'pgnfw_simple@0||900'],
    ['pgnfw_simple@0|显示名称|interval=900|timer=false', 'pgnfw_simple@0||0'],
  ]) {
    const save = createContext({ trigger: '保存本机 PO0 官方防火墙配置', env: { PO0_FIREWALL_TOKENS: row } });
    const result = await runEgernReport(save.ctx);
    const values = JSON.parse(await save.storage.get(CONFIG_STORAGE_KEY)).values;
    assert.equal(values.PO0_FIREWALL_TOKENS, normalized);
    assert.equal(values.PO0_FIREWALL_NAMES, '显示名称');
    assert.doesNotMatch(visibleText(result), /interval=|timer=/);
    if (!normalized.includes('||')) assert.match(visibleText(result), /上报间隔 600 秒/);
    assert.equal(save.calls.get.length + save.calls.post.length, 0);
  }
  const env = { PO0_FIREWALL_TOKENS: 'pgnfw_period|显示名称|43200', OFFICIAL_INTERVAL_SECONDS: '43200' };
  const storage = createStorage();
  globalThis.__PO0_EGERN_TEST_NOW = 1000000000;
  const first = createContext({ env, storage, trigger: 'schedule' });
  await runEgernReport(first.ctx);
  assert.equal(first.calls.get.length, 1);
  assert.equal(first.calls.post[0].url, API_BASE + '/pgnfw_period/add');
  assert.equal(first.calls.post[0].options.body, undefined, 'TTL controls only the client period');
  globalThis.__PO0_EGERN_TEST_NOW += 600000;
  const early = createContext({ env, storage, trigger: 'schedule' });
  await runEgernReport(early.ctx);
  assert.equal(early.calls.get.length, 0);
  globalThis.__PO0_EGERN_TEST_NOW += 42600000;
  const due = createContext({ env, storage, trigger: 'schedule' });
  await runEgernReport(due.ctx);
  assert.equal(due.calls.get.length, 1, 'plain TTL seconds must actually control the report interval');
}


async function testOfficialNetworkTargets() {
  const token='pgnfw_network_fixture';
  const env={PO0_FIREWALL_TOKENS:token+'@1|蜂窝标签|600', PO0_FIREWALL_WIFI_TOKENS:token+'|Wi-Fi 标签|900', OFFICIAL_NETWORK_TARGETS_ENABLED:'true'};
  const store=createStorage();
  const invoke=async (name, network='wifi', overrides={})=>{
    const input={OFFICIAL_NETWORK_TARGETS_ENABLED:'true', OFFICIAL_INTERVAL_SECONDS:'900', ...overrides};
    const run=createContext({trigger:name,env:input,storage:store,ssid:network==='wifi'?'Cafe':'',httpPost(url){
      const slot=new URL(url).searchParams.get('slot');
      return response(officialPayload({whitelist:[{ip:'203.0.113.10/24',slot:slot===null?null:Number(slot)}]}));
    }});
    run.ctx.env=input;
    if(network==='cellular')run.ctx.device.cellular={carrier:'Test',radio:'NR'};
    run.result=await runEgernReport(run.ctx);
    return run;
  };
  let run=await invoke('官方防火墙 · 保存配置','wifi',env);
  assert.equal(run.calls.get.length+run.calls.post.length,0);
  const snapshot=await store.get(CONFIG_STORAGE_KEY);
  const values=JSON.parse(snapshot).values;
  assert.equal(values.PO0_FIREWALL_WIFI_TOKENS,token+'||900');
  assert.equal(values.PO0_FIREWALL_WIFI_NAMES,'Wi-Fi 标签');
  run=await invoke('schedule','cellular');
  assert(run.calls.post[0].url.endsWith('?slot=1'));
  run=await invoke('schedule','wifi',{PO0_FIREWALL_WIFI_TOKENS:'pgnfw_other@4'});
  assert(run.calls.post[0].url.endsWith('/add'));
  assert.equal(run.result.official.entries[0].name,'Wi-Fi 标签');
  assert.equal(await store.get(CONFIG_STORAGE_KEY),snapshot);
  run=await invoke('schedule');
  assert.equal(run.calls.get.length,0,'same network uses interval');
  run=await invoke('schedule','cellular');
  assert(run.calls.post[0].url.endsWith('?slot=1'));
  run=await invoke('查询官方白名单');
  assert.equal(run.calls.post.length,0);
  run=await invoke('schedule');
  assert.equal(run.calls.post.length,1,'read-only after switching cannot advance due');
  run=await invoke('强制上报 PO0 防火墙','unknown');
  assert.equal(run.calls.get.length+run.calls.post.length,0);
  assert.match(JSON.stringify(run.result),/无法识别当前网络/);
  await invoke('官方防火墙 · 保存配置','wifi',{PO0_FIREWALL_WIFI_TOKENS:token+'@4|Wi-Fi 固定|120'});
  run=await invoke('schedule');
  assert(run.calls.post[0].url.endsWith('?slot=4'),'preserve explicit Wi-Fi fixed slot');
  const valid=await store.get(CONFIG_STORAGE_KEY);
  await invoke('官方防火墙 · 保存配置','wifi',{PO0_FIREWALL_WIFI_TOKENS:token+'@0,'+token+'@1'});
  assert.equal(await store.get(CONFIG_STORAGE_KEY),valid,'reject duplicates within Wi-Fi list');
  await invoke('官方防火墙 · 保存配置','wifi',{OFFICIAL_NETWORK_TARGETS_ENABLED:'false'});
  run=await invoke('强制上报 PO0 防火墙','wifi',{OFFICIAL_NETWORK_TARGETS_ENABLED:'false'});
  assert(run.calls.post[0].url.endsWith('?slot=1'));
  assert.equal(JSON.parse(await store.get(CONFIG_STORAGE_KEY)).values.PO0_FIREWALL_WIFI_TOKENS,token+'@4||120');
}

async function testRetirementMigrationAndWidget() {
  const values = { PO0_FIREWALL_TOKENS:'pgnfw_retirement_fixture@0',PO0_FIREWALL_NAMES:'保留名称',OFFICIAL_AUTO_ENABLED:'false',SSH_REPORT_TARGETS:'invalid-old',PO0_PASSWORD:'retired-secret',TTL_SECONDS:'7200' };
  const raw=JSON.stringify({version:1,values});
  const storage=createStorage({[CONFIG_STORAGE_KEY]:raw});
  const {ctx,calls}=createContext({storage,widgetFamily:'medium',trigger:'PO0 防火墙上报状态',env:{OFFICIAL_INTERVAL_SECONDS:'1200'}});
  const widget=await runEgernReport(ctx);
  assert.equal(widget.type,'widget'); assert(calls.get.length>0); assert.equal(calls.ssh,0);
  const saved=JSON.parse(await storage.get(CONFIG_STORAGE_KEY)).values;
  assert.equal(saved.PO0_FIREWALL_TOKENS,values.PO0_FIREWALL_TOKENS); assert.equal(saved.OFFICIAL_AUTO_ENABLED,'false'); assert.equal(saved.SSH_REPORT_TARGETS,undefined);
  assert.equal(JSON.parse(await storage.get(CONFIG_STORAGE_KEY+':pre-retirement-v1')).config,raw);
  const visible=JSON.stringify(widget); assert(visible.includes('保留名称')); assert(!visible.includes('自建')); assert(!visible.includes('retired-secret')); assert(!visible.includes('pgnfw_'));
  const originalBackup=await storage.get(CONFIG_STORAGE_KEY+':pre-retirement-v1');
  const again=createContext({storage,trigger:'network',env:{OFFICIAL_INTERVAL_SECONDS:'1200'}});
  await runEgernReport(again.ctx); assert.equal(again.calls.get.length,0,'disabled automatic choice persists');
  assert.equal(await storage.get(CONFIG_STORAGE_KEY+':pre-retirement-v1'),originalBackup);
  const retired=createContext({storage,trigger:'仅自建防火墙强制上报'}); await runEgernReport(retired.ctx); assert.equal(retired.calls.get.length,0); assert.equal(retired.calls.ssh,0);
  const clear=createContext({storage,trigger:'清除本机 PO0 官方防火墙 Token'}); await runEgernReport(clear.ctx);
  const synced=createContext({storage,widgetFamily:'medium',env:values}); await runEgernReport(synced.ctx); assert.equal(synced.calls.get.length,0,'clear cannot be undone by sync');
}

async function testWidgetAccountDetailsAcrossSizes() {
  for (const [family, count, shown] of [['systemSmall', 3, 2], ['systemMedium', 4, 3], ['systemLarge', 7, 6]]) {
    const tokens = Array.from({ length: count }, (_, index) => `pgnfw_widget_detail_${index}_not_real@0|账号${index + 1}`);
    const { ctx, calls } = createContext({
      widgetFamily: family, ssid: 'CafeWiFi',
      env: { PO0_FIREWALL_TOKENS: tokens.join(';') },
      httpGet: () => response(officialPayload({ whitelist: [{ ip: '203.0.113.10/24', slot: 2 }] })),
    });
    const widget = await runEgernReport(ctx);
    const text = visibleText(widget);
    for (let index = 1; index <= shown; index++) assert(text.includes(`账号${index}`));
    assert(!text.includes(`账号${shown + 1}`));
    assert.match(text, /共用 #3/);
    assert.match(text, /占用 1\/5/);
    assert.match(text, /共用放行/);
    assert.match(text, /CafeWiFi/);
    assert.match(text, /203\.0\.113\.10/);
    assert.match(text, /\+1 个账号/);
    assert.doesNotMatch(text, /pgnfw_|自建|Worker|SSH|TTL/);
    assert.equal(calls.get.length, count);
    assert.equal(calls.post.length, 0, 'layout must preserve GET-first shared coverage');
  }
}

async function testWidgetExpandedDetailsAndUnknownQuota() {
  const success = createContext({
    widgetFamily: 'systemLarge',
    httpGet: () => response(officialPayload({ whitelist: [{ ip: '203.0.113.10/24', slot: 3 }] })),
  });
  const text = visibleText(await runEgernReport(success.ctx));
  assert.match(text, /槽位 #4/, 'automatic accounts show the actual assigned slot');
  assert.match(text, /白名单/);
  assert.match(text, /未占用/);
  assert.match(text, /当前网段/);
  assert.match(text, /上报 \d{2}:\d{2}/);
  const failure = createContext({
    widgetFamily: 'systemLarge',
    httpGet: () => response({}, 503),
  });
  const failed = visibleText(await runEgernReport(failure.ctx));
  assert.match(failed, /1 个异常/);
  assert.match(failed, /检查失败/);
  assert.match(failed, /HTTP 503/);
  assert.match(failed, /占用 \?\/5/);
  assert.doesNotMatch(failed, /占用 0\/0|pgnfw_/);
  assert.equal(failure.calls.post.length, 0);

  const empty = createContext({ widgetFamily: 'systemSmall', env: { PO0_FIREWALL_TOKENS: '' } });
  const emptyText = visibleText(await runEgernReport(empty.ctx));
  assert.match(emptyText, /尚未设置官方目标/);
  assert.match(emptyText, /保存配置/);
  assert.equal(empty.calls.get.length + empty.calls.post.length, 0);
}

async function testWidgetLatestCheckAndDifferentExits() {
  const storage = createStorage();
  globalThis.__PO0_EGERN_TEST_NOW = Date.parse('2026-09-08T01:00:00Z');
  await runEgernReport(createContext({ storage }).ctx);
  globalThis.__PO0_EGERN_TEST_NOW += 3600000;
  const failure = createContext({ storage, widgetFamily: 'systemMedium', httpGet: () => response({}, 503) });
  const widget = await runEgernReport(failure.ctx);
  const expectedTime = new Date(globalThis.__PO0_EGERN_TEST_NOW).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit', hour12: false });
  assert.equal(widget.children.at(-1).children.at(-1).text, expectedTime, 'latest failed check must not display the older success time');
  const mixed = createContext({
    widgetFamily: 'systemLarge',
    env: { PO0_FIREWALL_TOKENS: 'pgnfw_exit_a_not_real@0|出口甲;pgnfw_exit_b_not_real@0|出口乙' },
    httpGet(url) {
      const currentIp = url.includes('exit_a') ? '203.0.113.10/24' : '198.51.100.20/24';
      return response(officialPayload({ currentIp, whitelist: [{ ip: currentIp, slot: 0 }] }));
    },
  });
  const text = visibleText(await runEgernReport(mixed.ctx));
  assert.match(text, /多个出口/);
  assert.match(text, /203\.0\.113\.10/);
  assert.match(text, /198\.51\.100\.20/);
}

async function testWidgetUsesSpaceAndSeparatesWhitelistRows() {
  const nodesOf = node => [node, ...(node.children || []).flatMap(nodesOf)];
  const whitelist = [
    { slot: 0, ip: '203.0.113.10/24' }, { slot: 1, ip: '198.51.100.20/24' },
    { slot: 2, ip: '192.0.2.30/24' }, { slot: 3, ip: '192.0.2.40/24' }, { slot: 4, ip: '192.0.2.50/24' },
  ];
  for (const family of ['systemSmall', 'systemMedium', 'systemLarge']) {
    for (const count of [1, 2]) {
      const { ctx, calls } = createContext({
        widgetFamily: family,
        env: { PO0_FIREWALL_TOKENS: Array.from({ length: count }, (_, index) => `pgnfw_layout_${index}_not_real@0`).join(';') },
        httpGet: () => response(officialPayload({ whitelist })),
      });
      const widget = await runEgernReport(ctx);
      const nodes = nodesOf(widget);
      const texts = nodes.filter(node => node.type === 'text');
      assert(!widget.children.some(node => node.type === 'spacer'), 'remaining height must go to content instead of a blank footer spacer');
      assert(widget.children.some(node => node.type === 'stack' && node.flex > 0), 'account content must receive the available height');
      const accountName = texts.find(node => node.text === '官方账号 1');
      assert(accountName.font.size >= (count === 1 ? 16 : 13), 'sparse widgets must use readable account text');
      for (const node of texts) {
        assert((node.text.match(/\d+\.\d+\.\d+\.\d+\/24/g) || []).length <= 1, 'each whitelist address must have its own row');
      }
      if (family === 'systemLarge') {
        for (const row of whitelist) assert.equal(texts.filter(node => node.text === `#${row.slot + 1}  ${row.ip}`).length, count, 'every slot must be visible for both expanded accounts');
      }
      assert.equal(calls.post.length, 0, 'layout changes must not alter a covered account');
    }
  }
  const unknownSlot = createContext({ widgetFamily: 'systemLarge',
    httpGet: () => response(officialPayload({ whitelist: [{ ip: '203.0.113.10/24' }] })),
  });
  const unknownWidget = visibleText(await runEgernReport(unknownSlot.ctx));
  assert.doesNotMatch(unknownWidget, /未占用/, 'an unknown slot must not make all numbered slots appear empty');
}

async function testWhitelistSortsNumberedSlotsBeforeAutomatic() {
  const whitelist = [
    { slot: 3, ip: '203.0.113.10/24' },
    { slot: null, ip: '192.0.2.20/24' },
    { slot: 1, ip: '198.51.100.30/24' },
    { slot: 0, ip: '192.0.2.40/24' },
    { slot: null, ip: '192.0.2.50/24' },
  ];
  const expected = ['#1  192.0.2.40/24', '#2  198.51.100.30/24', '#4  203.0.113.10/24', '自动  192.0.2.20/24', '自动  192.0.2.50/24'];
  const nodesOf = node => [node, ...(node.children || []).flatMap(nodesOf)];
  for (const [trigger, widgetFamily, count, visibleCount] of [
    ['PO0 防火墙上报状态', 'systemLarge', 1, 5],
    ['PO0 防火墙上报状态', 'systemLarge', 3, 2],
    ['PO0 防火墙上报状态', 'systemMedium', 1, 2],
    ['查询官方白名单', '', 1, 5],
  ]) {
    const { ctx, calls, storage } = createContext({ trigger, widgetFamily,
      env: { PO0_FIREWALL_TOKENS: Array.from({ length: count }, (_, index) => `pgnfw_sort_${index}_not_real@0`).join(';') },
      httpGet: () => response(officialPayload({ whitelist })),
    });
    const widget = await runEgernReport(ctx);
    const rows = nodesOf(widget).filter(node => node.type === 'text' && /^(?:#\d|自动)  /.test(node.text));
    assert.deepEqual(rows.map(row => row.text), Array.from({ length: count }, () => expected.slice(0, visibleCount)).flat());
    const covered = rows.find(row => row.text === expected[2]);
    if (covered && widgetFamily) assert.equal(covered.textColor, '#30D158', 'covered slot stays green without jumping ahead of lower slots');
    const saved = await officialStateOf(storage);
    assert.deepEqual(saved.entries[0].whitelist, whitelist, 'display sorting must not reorder stored API data');
    assert.equal(calls.post.length, 0);
  }
}

const tests = [
  testWhitelistSortsNumberedSlotsBeforeAutomatic,
  testWidgetUsesSpaceAndSeparatesWhitelistRows,
  testWidgetLatestCheckAndDifferentExits,
  testWidgetAccountDetailsAcrossSizes,
  testWidgetExpandedDetailsAndUnknownQuota,
  testOfficialNetworkTargets,
  testOfficialIntervalDefaultsAndLegacyAlias,
  testLegacyAccountTimesAndNewTarget,
  testInlineOfficialTargetsPersistAndMatchNames,
  testInlineOfficialTargetValidation,
  testPerAccountOfficialTimersAndReadonlyState,
  testNetworkChangesBypassOptionalTimer,
  testFlexibleOfficialSeparators,
  testSavedSlotSurvivesSyncedEnvironment,
  testHitUsesDirectGetOnlyAndStaysQuiet,
  testOfficialOnlyIgnoresSshSchemaDefaults,
  testMissingReportsWithFixedSlotAndNotifiesUpdate,
  testWidgetAndReportStatusInitializeSavedToken,
  testSharedNetworkDoesNotClaimAnotherSlot,
  testPost403RechecksOnceWithoutRepeatingWrite,
  testGet403DoesNotPostOrAssumeSlotConflict,
  testValidMissingStatusReturnsSuccessWithoutPost,
  testGetFailureNeverPostsAndDoesNotLeakToken,
  testHttpGetFailureNeverPosts,
  testUnexpectedErrorRedactsTokensAndBearer,
  testMalformedAndDuplicateTokensFailClosed,
  testDuplicateNumericResponseSlotIsRejectedWithoutPost,
  testMalformedOfficialPayloadFailsClosedWithoutPost,
  testSharedRunLockAcrossModesAndContexts,
  testEgernLockExpiryAndOwnerReplacement,
  testIndependentOfficialDueUsesLastAttemptAndManualBypassesDue,
  testSsidSkipsOfficialAndExistingSshTogether,
  testEgernTimeoutBudget,
  testEgernScriptCopiesStaySynchronized,
  testEgernWidgetBindingsStayCompatible,
  testRetirementMigrationAndWidget,
];

for (const test of tests) {
  try {
    await test();
    console.log(`ok - ${test.name}`);
  } catch (error) {
    console.error(`FAIL - ${test.name}: ${error.message}`);
    process.exitCode = 1;
  } finally {
    delete globalThis.__PO0_EGERN_TEST_NOW;
  }
}

if (!process.exitCode) console.log('PASS: Egern official-only firewall mock checks passed.');
