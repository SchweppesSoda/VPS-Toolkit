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
  assert.equal(result.reportedCidr, '203.0.113.10/24');
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

async function testSlotMismatchPostsOnWidgetButOfficialStatusRemainsReadOnly() {
  const token = 'pgnfw_egern_slot_not_real';
  const { ctx, calls, storage } = createContext({
    trigger: 'PO0 官方防火墙状态（只读）',
    env: { PO0_FIREWALL_TOKENS: `${token}@0` },
    httpGet() {
      return response(officialPayload({ whitelist: [{ ip: '203.0.113.10/24', slot: 1 }] }));
    },
    httpPost() { throw new Error('official status must not POST'); },
  });
  const result = await runEgernReport(ctx);
  const official = await officialStateOf(storage);
  assert.equal(official.ok, true);
  assert.equal(official.entries[0].status, 'missing');
  assert.equal(calls.post.length, 0);

  const widgetRun = createContext({
    trigger: 'generic manual now',
    widgetFamily: 'systemMedium',
    env: { PO0_FIREWALL_TOKENS: `${token}@0` },
    httpGet() { return response(officialPayload({ whitelist: [{ ip: '203.0.113.10/24', slot: 1 }] })); },
    httpPost() { return response(officialPayload({ whitelist: [{ ip: '203.0.113.10/24', slot: 0 }] })); },
  });
  const widget = await runEgernReport(widgetRun.ctx);
  assert.equal(widgetRun.calls.post.length, 1);
  assert.equal(widgetRun.calls.post[0].url, API_BASE + '/' + token + '/add?slot=0');
  assert.deepEqual(widgetRun.calls.order, ['GET ' + API_BASE + '/' + token, 'POST ' + API_BASE + '/' + token + '/add?slot=0']);
  assert.equal((await officialStateOf(widgetRun.storage)).entries[0].status, 'updated');
  assert.equal(widget.type, 'widget');
  assert.equal(visibleText(widget).includes('固定槽位'), true);
  assert.equal(visibleText(widget).includes('#1'), true);
  assert.equal(visibleText(widget).includes(token), false);
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
    assert.match(visibleText(widget), /已更新当前出口/);
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
  assert.equal(statusBusy.status, 'busy', 'active scheduled lock must block status');
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

async function testEgernDeviceActionsBypassLockWithoutNetwork() {
  const token = 'pgnfw_egern_device_action_not_real';
  const now = Date.now();
  globalThis.__PO0_EGERN_TEST_NOW = now;
  const activeLock = JSON.stringify({
    version: 1,
    owner: 'active-owner',
    expiresAt: now + 120000,
  });

  const deviceStorage = createStorage({ [REPORT_LOCK_KEY]: activeLock });
  const deviceRequest = createContext({
    trigger: 'device page',
    storage: deviceStorage,
    request: { url: 'http://po0-egern.local/device' },
    httpGet() {
      throw new Error('device HTTP action must not GET');
    },
    httpPost() {
      throw new Error('device HTTP action must not POST');
    },
  });
  const deviceResult = await runEgernReport(deviceRequest.ctx);
  assert.equal(deviceResult.status, 200);
  assert.equal(deviceRequest.calls.get.length + deviceRequest.calls.post.length, 0);
  assert.equal(await deviceStorage.get(REPORT_LOCK_KEY), activeLock, 'device HTTP action must not touch report lock');

  const configStorage = createStorage({ [REPORT_LOCK_KEY]: activeLock });
  const configAction = createContext({
    trigger: '保存本机 PO0 上报配置',
    storage: configStorage,
    env: { PO0_FIREWALL_TOKENS: token },
    httpGet() {
      throw new Error('config action must not GET');
    },
    httpPost() {
      throw new Error('config action must not POST');
    },
  });
  await runEgernReport(configAction.ctx);
  assert.equal(configAction.calls.get.length + configAction.calls.post.length, 0);
  assert.ok(await configStorage.get(CONFIG_STORAGE_KEY), 'config action must persist configuration');
  assert.equal(await configStorage.get(REPORT_LOCK_KEY), activeLock, 'config action must not touch report lock');
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

async function testOfficialFailureContinuesAndPrecedesExistingSsh() {
  const firstToken = 'pgnfw_egern_fail_not_real';
  const secondToken = 'pgnfw_egern_second_not_real';
  const { ctx, calls } = createContext({
    env: {
      PO0_FIREWALL_TOKENS: `${firstToken},${secondToken}@1`,
      PO0_HOST: 'po0.example.com',
      SSH_REPORT_TOKEN: 'ssh-token-not-real',
      PO0_PASSWORD: 'password-not-real',
      IP_CHECK_URLS: 'https://example.com/ip',
    },
    httpGet(url) {
      if (url === `${API_BASE}/${firstToken}`) throw new Error(`secret ${firstToken}`);
      if (url === `${API_BASE}/${secondToken}`) {
        return response(officialPayload({ whitelist: [{ ip: '198.51.100.1/24', slot: 0 }] }));
      }
      assert.equal(url, 'https://example.com/ip');
      return response({ ip: '203.0.113.50' });
    },
    httpPost(url) {
      assert.equal(url, `${API_BASE}/${secondToken}/add?slot=1`);
      return response(officialPayload({
        currentIp: '203.0.113.10/24',
        whitelist: [{ ip: '203.0.113.10/24', slot: 1 }],
      }));
    },
  });
  const result = await runEgernReport(ctx);
  assert.equal(result.ok, false);
  assert.equal(result.official.failureCount, 1);
  assert.equal(result.official.entries[1].status, 'updated');
  assert.equal(calls.ssh, 1);
  const firstReportIndex = calls.order.findIndex((value) => value === `GET ${API_BASE}/${firstToken}`);
  const sshIndex = calls.order.indexOf('SSH');
  assert.ok(firstReportIndex >= 0 && firstReportIndex < sshIndex);
  assert.ok(calls.order.indexOf(`POST ${API_BASE}/${secondToken}/add?slot=1`) < sshIndex);
  assert.equal(visibleText(result).includes(firstToken), false);
  assert.equal(visibleText(result).includes(secondToken), false);
  assert.equal(visibleText(calls.notifications).includes(firstToken), false);
  assert.equal(visibleText(calls.logs).includes(firstToken), false);
}

async function testParallelOfficialAccountsPreserveLaneOrder() {
  const firstToken = 'pgnfw_egern_parallel_one';
  const secondToken = 'pgnfw_egern_parallel_two';
  const wait = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
  const { ctx, calls, storage } = createContext({
    env: {
      PO0_FIREWALL_TOKENS: firstToken + '@1；\n ' + secondToken + '@2',
      PO0_HOST: 'po0.example.com',
      SSH_REPORT_TOKEN: 'ssh-token-not-real',
      PO0_PASSWORD: 'password-not-real',
      IP_CHECK_URLS: 'https://example.com/ip',
    },
    async httpGet(url) {
      if (url === API_BASE + '/' + firstToken) {
        await wait(35);
        return response(officialPayload({ whitelist: [{ ip: '198.51.100.1/24', slot: 0 }] }));
      }
      if (url === API_BASE + '/' + secondToken) {
        await wait(0);
        return response(officialPayload({ whitelist: [{ ip: '198.51.100.2/24', slot: 1 }] }));
      }
      assert.equal(url, 'https://example.com/ip');
      return response({ ip: '203.0.113.50' });
    },
    async httpPost(url) {
      await wait(10);
      assert.match(url, new RegExp('^' + API_BASE + '/(?:' + firstToken + '|' + secondToken + ')/add\\?slot=[12]$'));
      const slot = url.endsWith('slot=1') ? 1 : 2;
      return response(officialPayload({
        currentIp: '203.0.113.10/24',
        whitelist: [{ ip: '203.0.113.10/24', slot }],
      }));
    },
  });
  const result = await runEgernReport(ctx);
  const officialGetOne = calls.order.indexOf('GET ' + API_BASE + '/' + firstToken);
  const officialGetTwo = calls.order.indexOf('GET ' + API_BASE + '/' + secondToken);
  const officialPostOne = calls.order.indexOf('POST ' + API_BASE + '/' + firstToken + '/add?slot=1');
  const officialPostTwo = calls.order.indexOf('POST ' + API_BASE + '/' + secondToken + '/add?slot=2');
  const workerIp = calls.order.indexOf('GET https://example.com/ip');
  const ssh = calls.order.indexOf('SSH');
  assert.ok(officialGetOne >= 0 && officialGetTwo >= 0);
  assert.ok(Math.max(officialGetOne, officialGetTwo) < Math.min(officialPostOne, officialPostTwo), 'all official GETs must start before any POST');
  assert.ok(Math.max(officialPostOne, officialPostTwo) < workerIp, 'Worker must start after every official account finishes');
  assert.ok(workerIp < ssh);
  assert.equal(result.ok, true);
  const official = await officialStateOf(storage);
  assert.deepEqual(official.entries.map((entry) => entry.ordinal), [1, 2]);
  assert.deepEqual(official.entries.map((entry) => entry.status), ['updated', 'updated']);
  assert.equal(visibleText(result).includes(firstToken), false);
  assert.equal(visibleText(calls.notifications).includes(secondToken), false);
}

function testEgernTimeoutBudget() {
  assert.equal((yamlSource.match(/timeout: 90/g) || []).length, 7);
  assert.equal((yamlSource.match(/timeout: 30/g) || []).length, 0);
}

function testEgernScriptCopiesStaySynchronized() {
  assert.equal(compatibilitySource, source);
}

async function testOfficialTokenPersistsOnlyInConfigurationAndClearKeepsSsh() {
  const token = 'pgnfw_egern_persist_not_real';
  const storage = createStorage();
  const save = createContext({
    trigger: '保存本机 PO0 上报配置',
    storage,
    env: {
      PO0_FIREWALL_TOKENS: token,
      PO0_HOST: 'po0.example.com',
      SSH_REPORT_TOKEN: 'ssh-token-not-real',
      PO0_PASSWORD: 'password-not-real',
    },
  });
  await runEgernReport(save.ctx);
  const config = JSON.parse(await storage.get(CONFIG_STORAGE_KEY));
  assert.equal(config.values.PO0_FIREWALL_TOKENS, token);

  const clear = createContext({
    trigger: '清除本机 PO0 官方防火墙 Token',
    storage,
    env: {},
  });
  await runEgernReport(clear.ctx);
  const cleared = JSON.parse(await storage.get(CONFIG_STORAGE_KEY));
  assert.equal(cleared.values.PO0_FIREWALL_TOKENS, undefined);
  assert.equal(cleared.values.SSH_REPORT_TOKEN, 'ssh-token-not-real');
  assert.equal(await storage.get(OFFICIAL_STORAGE_KEY), null);
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

async function testScopedSavesDoNotOverwriteOtherChannel() {
  const storage = createStorage({
    [CONFIG_STORAGE_KEY]: JSON.stringify({ version: 1, values: {
      PO0_HOST: 'po0.example.com', SSH_REPORT_TOKEN: 'ssh-mock', PO0_PASSWORD: 'password-mock',
      PO0_FIREWALL_TOKENS: 'pgnfw_original_mock@0', SKIP_WIFI_SSIDS: 'Home',
    } }),
  });
  const worker = createContext({ storage, trigger: '保存本机自建 PO0 / 通用设置', env: {
    SSH_REPORT_TOKEN: 'ssh-new-mock', PO0_FIREWALL_TOKENS: 'invalid-synced-token', SKIP_WIFI_SSIDS: 'Home;Office',
  } });
  await runEgernReport(worker.ctx);
  let values = JSON.parse(await storage.get(CONFIG_STORAGE_KEY)).values;
  assert.equal(values.SSH_REPORT_TOKEN, 'ssh-new-mock');
  assert.equal(values.PO0_FIREWALL_TOKENS, 'pgnfw_original_mock@0');
  assert.equal(values.SKIP_WIFI_SSIDS, 'Home;Office');
  const official = createContext({ storage, trigger: '保存本机 PO0 官方防火墙配置', env: {
    PO0_FIREWALL_TOKENS: 'pgnfw_replacement_mock@4', SSH_REPORT_TOKEN: 'must-not-replace', SKIP_WIFI_SSIDS: 'must-not-replace',
  } });
  await runEgernReport(official.ctx);
  values = JSON.parse(await storage.get(CONFIG_STORAGE_KEY)).values;
  assert.equal(values.PO0_FIREWALL_TOKENS, 'pgnfw_replacement_mock@4');
  assert.equal(values.SSH_REPORT_TOKEN, 'ssh-new-mock');
  assert.equal(values.SKIP_WIFI_SSIDS, 'Home;Office');
  const before = await storage.get(CONFIG_STORAGE_KEY);
  const invalid = createContext({ storage, trigger: '保存本机 PO0 官方防火墙配置', env: { PO0_FIREWALL_TOKENS: 'invalid' } });
  await runEgernReport(invalid.ctx);
  assert.equal(await storage.get(CONFIG_STORAGE_KEY), before);
  for (const run of [worker, official, invalid]) {
    assert.equal(run.calls.get.length, 0);
    assert.equal(run.calls.post.length, 0);
    assert.equal(run.calls.ssh, 0);
  }
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
  const call = async (trigger, env = {}, ssid = '') => {
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
  assert.equal(saved.SKIP_WIFI_SSIDS, 'HomeWiFi');
  report = await call('schedule', values);
  assert.equal(report.calls.ssh, 0, 'synced env must not restore cleared SSH credentials');
  await call('清除本机全部 PO0 上报配置');
  report = await call('schedule', values);
  assert.equal(report.calls.get.length, 0, 'clear-all must not bootstrap again from synced env');
  const view = await call('查看本机上报设置');
  assert.equal(view.calls.get.length, 0);
  assert.equal(view.calls.ssh, 0);
}

async function testIndependentChannelControlsAndNames() {
  for (const actionNames of [{}, {"保存本机自建 PO0 / 通用设置":"保存本机 PO0 自建防火墙配置","切换自建 PO0 自动上报":"切换自建防火墙自动上报","仅自建 PO0 立即上报":"仅自建防火墙强制上报","清除本机自建 PO0 配置":"清除本机自建防火墙配置","仅官方防火墙立即上报":"仅官方防火墙强制上报"}]) {
    await checkIndependentChannelControlsAndNames(actionNames);
  }
}

async function testNamedForceActionRunsBothLanesDespiteSsidAndDue() {
  const token = 'pgnfw_force_both_lanes_not_real';
  const now = 1000000000;
  globalThis.__PO0_EGERN_TEST_NOW = now;
  const storage = createStorage({
    [OFFICIAL_STORAGE_KEY]: JSON.stringify({
      version: 1, ok: true, status: 'success', entries: [], lastAttemptAt: new Date(now - 1000).toISOString(),
    }),
  });
  const { ctx, calls } = createContext({
    trigger: '强制上报 PO0 防火墙', ssid: 'HomeWiFi', storage,
    env: {
      PO0_FIREWALL_TOKENS: token + '@0', SKIP_WIFI_SSIDS: 'HomeWiFi',
      SSH_REPORT_TARGETS: '{device}|po0.example.com||||ssh-force-token-not-real',
      PO0_PASSWORD: 'password-not-real', IP_CHECK_URLS: 'https://example.com/ip',
    },
    httpGet(url) {
      if (url === API_BASE + '/' + token) return response(officialPayload());
      assert.equal(url, 'https://example.com/ip');
      return response({ ip: '203.0.113.10', country: 'Test', isp: 'Test' });
    },
  });
  const result = await runEgernReport(ctx);
  assert.equal(result.ok, true);
  assert.deepEqual(calls.order, [
    'GET ' + API_BASE + '/' + token,
    'POST ' + API_BASE + '/' + token + '/add?slot=0',
    'GET https://example.com/ip', 'SSH',
  ]);
  assert.equal(result.official.entries[0].status, 'updated');
  assert.equal((await officialStateOf(storage)).lastSuccessAt, new Date(now).toISOString());
  assert.equal(visibleText(result).includes(token), false);
}

const tests = [
  testIndependentChannelControlsAndNames,
  testFlexibleOfficialSeparators,
  testNamedForceActionRunsBothLanesDespiteSsidAndDue,
  testScopedSavesDoNotOverwriteOtherChannel,
  testSavedSlotSurvivesSyncedEnvironment,
  testHitUsesDirectGetOnlyAndStaysQuiet,
  testOfficialOnlyIgnoresSshSchemaDefaults,
  testMissingReportsWithFixedSlotAndNotifiesUpdate,
  testWidgetAndReportStatusInitializeSavedToken,
  testSlotMismatchPostsOnWidgetButOfficialStatusRemainsReadOnly,
  testValidMissingStatusReturnsSuccessWithoutPost,
  testGetFailureNeverPostsAndDoesNotLeakToken,
  testHttpGetFailureNeverPosts,
  testUnexpectedErrorRedactsTokensAndBearer,
  testMalformedAndDuplicateTokensFailClosed,
  testDuplicateNumericResponseSlotIsRejectedWithoutPost,
  testMalformedOfficialPayloadFailsClosedWithoutPost,
  testSharedRunLockAcrossModesAndContexts,
  testEgernLockExpiryAndOwnerReplacement,
  testEgernDeviceActionsBypassLockWithoutNetwork,
  testIndependentOfficialDueUsesLastAttemptAndManualBypassesDue,
  testSsidSkipsOfficialAndExistingSshTogether,
  testOfficialFailureContinuesAndPrecedesExistingSsh,
  testParallelOfficialAccountsPreserveLaneOrder,
  testOfficialTokenPersistsOnlyInConfigurationAndClearKeepsSsh,
  testEgernTimeoutBudget,
  testEgernScriptCopiesStaySynchronized,
];

for (const test of tests) {
  try {
    await test();
    console.log(`ok - ${test.name}`);
  } finally {
    delete globalThis.__PO0_EGERN_TEST_NOW;
  }
}

console.log('PASS: Egern official firewall dual-channel mock checks passed.');
