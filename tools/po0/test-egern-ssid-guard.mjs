import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const egernScriptPath = resolve(repoRoot, 'scripts/po0/nftables/clients/egern/po0-ssh-ip-report.js');
const source = await readFile(egernScriptPath, 'utf8');
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;
const { default: runEgernReport } = await import(moduleUrl);

const STORAGE_KEY = 'po0-ssh-ip-report:last';
const ERROR_STORAGE_KEY = 'po0-ssh-ip-report:last-error';
const DEVICE_ID_KEY = 'po0-ssh-ip-report:device-id';
const CONFIG_STORAGE_KEY = 'po0-ssh-ip-report:config:v1';

function createStorage(initial = {}) {
  const values = new Map(Object.entries(initial));
  return {
    values,
    async get(key) {
      return values.get(key) ?? null;
    },
    async set(key, value) {
      values.set(key, value);
    },
    async delete(key) {
      values.delete(key);
    },
  };
}

function ipResponse(ip = '8.8.8.8') {
  return {
    status: 200,
    async json() {
      return {
        ip,
        country: 'US',
        city: 'Mountain View',
        isp: 'Google',
      };
    },
    async text() {
      return ip;
    },
  };
}

function baseEnv(overrides = {}) {
  return {
    PO0_HOST: 'po0.example.com',
    PO0_PORT: '22',
    PO0_USER: 'root',
    PO0_PASSWORD: 'secret-password',
    PO0_SCRIPT: '/root/nftables-relay-manager.sh',
    SSH_REPORT_SOURCE: 'iphone',
    SSH_REPORT_TOKEN: 'secret-token',
    REPORT_IDENTITY: 'egern',
    TTL_SECONDS: '43200',
    IP_CHECK_URLS: 'https://example.com/ip',
    POLICY: 'DIRECT',
    ...overrides,
  };
}

function createContext({
  env = {},
  completeEnv = true,
  trigger = 'schedule',
  ssid = '',
  device = null,
  widgetFamily = '',
  storage = createStorage(),
  httpGet,
  sshConnect,
} = {}) {
  const calls = {
    http: 0,
    ssh: 0,
    notifications: [],
    logs: [],
  };
  return {
    ctx: {
      name: trigger,
      trigger,
      widgetFamily,
      env: completeEnv ? baseEnv(env) : { ...env },
      device: device || {
        wifi: ssid ? { ssid } : {},
        ipv4: { address: '192.168.1.20', gateway: '192.168.1.1' },
      },
      storage,
      http: {
        async get(url, options) {
          calls.http += 1;
          if (httpGet) return httpGet(url, options, calls);
          return ipResponse();
        },
      },
      ssh: {
        async connect(config) {
          calls.ssh += 1;
          calls.lastSshConfig = config;
          if (sshConnect) return sshConnect(config, calls);
          return {
            async exec(command) {
              calls.lastCommand = command;
              return { code: 0, stdout: 'OK' };
            },
            async close() {},
          };
        },
      },
      notify(message) {
        calls.notifications.push(message);
      },
      log(message) {
        calls.logs.push(message);
      },
    },
    calls,
    storage,
  };
}

async function readStoredState(storage) {
  const raw = await storage.get(STORAGE_KEY);
  return raw ? JSON.parse(raw) : null;
}

async function readStoredConfig(storage) {
  const raw = await storage.get(CONFIG_STORAGE_KEY);
  return raw ? JSON.parse(raw) : null;
}

function serializedResult(result) {
  return JSON.stringify(result);
}

async function testAutomaticMatchingSsidSkipsBeforeNetworkCalls() {
  const { ctx, calls, storage } = createContext({
    trigger: 'schedule',
    ssid: 'OfficeWiFi',
    env: { SKIP_WIFI_SSIDS: 'HomeWiFi; OfficeWiFi ' },
    httpGet() {
      throw new Error('HTTP IP detection must not run when SSID guard matches');
    },
    sshConnect() {
      throw new Error('SSH report must not run when SSID guard matches');
    },
  });

  const result = await runEgernReport(ctx);
  const stored = await readStoredState(storage);

  assert.equal(calls.http, 0);
  assert.equal(calls.ssh, 0);
  assert.equal(calls.notifications.length, 0);
  assert.equal(result.skipped, true);
  assert.equal(result.skipType, 'wifi-ssid');
  assert.equal(stored.skipped, true);
  assert.equal(stored.skipType, 'wifi-ssid');
  assert.equal(JSON.stringify(stored).includes('secret-token'), false);
  assert.equal(JSON.stringify(stored).includes('secret-password'), false);
}

async function testAutomaticMatchingSsidPreservesPreviousSuccessState() {
  const previousState = {
    ok: true,
    sourceId: 'iphone',
    ip: '8.8.4.4',
    reportedCidr: '8.8.4.4/32',
    cidrPrefix: 32,
    ipProfile: { location: 'US', isp: 'Google' },
    po0Host: 'po0.example.com',
    identity: 'egern',
    at: '2026-07-01T00:00:00.000Z',
    targetCount: 1,
    successCount: 1,
    failureCount: 0,
    targets: [{
      ok: true,
      sourceId: 'iphone',
      host: 'po0.example.com',
      port: 22,
      identity: 'egern',
      ttlSeconds: 43200,
      expiresAt: '2026-07-01T12:00:00.000Z',
      token: 'old-secret-token',
    }],
  };
  const storage = createStorage({ [STORAGE_KEY]: JSON.stringify(previousState) });
  const { ctx, storage: usedStorage } = createContext({
    trigger: 'network',
    ssid: 'OfficeWiFi',
    storage,
    env: { SKIP_WIFI_SSIDS: 'OfficeWiFi' },
    httpGet() {
      throw new Error('HTTP IP detection must not run when SSID guard matches');
    },
    sshConnect() {
      throw new Error('SSH report must not run when SSID guard matches');
    },
  });

  const result = await runEgernReport(ctx);
  const stored = await readStoredState(usedStorage);

  assert.equal(result.ip, '8.8.4.4');
  assert.equal(result.reportedCidr, '8.8.4.4/32');
  assert.equal(result.successCount, 1);
  assert.equal(stored.targets[0].ok, true);
  assert.equal(JSON.stringify(stored).includes('old-secret-token'), false);
}

async function testAutomaticUnmatchedWifiReports() {
  const { ctx, calls } = createContext({
    trigger: 'schedule',
    ssid: 'CafeWiFi',
    env: { SKIP_WIFI_SSIDS: 'OfficeWiFi' },
  });

  const result = await runEgernReport(ctx);

  assert.equal(calls.http, 1);
  assert.equal(calls.ssh, 1);
  assert.equal(result.ok, true);
  assert.equal(result.skipped, undefined);
}

async function testAutomaticMissingSsidFailsOpen() {
  const { ctx, calls } = createContext({
    trigger: 'network',
    env: { SKIP_WIFI_SSIDS: 'OfficeWiFi' },
  });

  const result = await runEgernReport(ctx);

  assert.equal(calls.http, 1);
  assert.equal(calls.ssh, 1);
  assert.equal(result.ok, true);
  assert.equal(result.skipped, undefined);
}

async function testAutomaticCellularReportsEvenWithSkipList() {
  const { ctx, calls } = createContext({
    trigger: 'schedule',
    env: { SKIP_WIFI_SSIDS: 'OfficeWiFi' },
    device: {
      wifi: {},
      cellular: { carrier: 'CMCC', radio: 'LTE' },
      ipv4: { address: '10.0.0.2', gateway: '' },
    },
  });

  const result = await runEgernReport(ctx);

  assert.equal(calls.http, 1);
  assert.equal(calls.ssh, 1);
  assert.equal(result.ok, true);
  assert.equal(result.skipped, undefined);
}

async function testManualMatchingSsidStillReports() {
  const { ctx, calls } = createContext({
    trigger: 'generic manual now',
    ssid: 'OfficeWiFi',
    env: { SKIP_WIFI_SSIDS: 'OfficeWiFi' },
  });

  const result = await runEgernReport(ctx);

  assert.equal(calls.http, 1);
  assert.equal(calls.ssh, 1);
  assert.equal(result.ok, true);
  assert.equal(result.skipped, undefined);
}

async function testStatusAndWidgetMatchingSsidStillReport() {
  const statusRun = createContext({
    trigger: 'PO0 SSH 上报状态',
    ssid: 'OfficeWiFi',
    env: { SKIP_WIFI_SSIDS: 'OfficeWiFi' },
  });
  await runEgernReport(statusRun.ctx);
  assert.equal(statusRun.calls.http, 1);
  assert.equal(statusRun.calls.ssh, 1);

  const widgetRun = createContext({
    trigger: 'schedule',
    ssid: 'OfficeWiFi',
    widgetFamily: 'medium',
    env: { SKIP_WIFI_SSIDS: 'OfficeWiFi' },
  });
  await runEgernReport(widgetRun.ctx);
  assert.equal(widgetRun.calls.http, 1);
  assert.equal(widgetRun.calls.ssh, 1);
}

async function testExplicitSavePersistsReportConfigWithoutNetworkCalls() {
  const { ctx, calls, storage } = createContext({
    trigger: '保存本机 PO0 上报配置',
  });

  const result = await runEgernReport(ctx);
  const stored = await readStoredConfig(storage);

  assert.equal(calls.http, 0);
  assert.equal(calls.ssh, 0);
  assert.equal(stored.version, 1);
  assert.equal(stored.values.PO0_HOST, 'po0.example.com');
  assert.equal(stored.values.PO0_PASSWORD, 'secret-password');
  assert.equal(stored.values.SSH_REPORT_TOKEN, 'secret-token');
  assert.equal(serializedResult(result).includes('secret-password'), false);
  assert.equal(serializedResult(result).includes('secret-token'), false);
  assert.equal(JSON.stringify(calls.notifications).includes('secret-password'), false);
  assert.equal(JSON.stringify(calls.notifications).includes('secret-token'), false);
  assert.equal(JSON.stringify(calls.logs).includes('secret-password'), false);
  assert.equal(JSON.stringify(calls.logs).includes('secret-token'), false);
}

async function testStoredConfigReportsAfterProfileReplacement() {
  const storage = createStorage();
  const saveRun = createContext({
    trigger: '保存本机 PO0 上报配置',
    storage,
  });
  await runEgernReport(saveRun.ctx);

  const replacementRun = createContext({
    trigger: 'schedule',
    completeEnv: false,
    env: {},
    storage,
  });
  const result = await runEgernReport(replacementRun.ctx);

  assert.equal(replacementRun.calls.http, 1);
  assert.equal(replacementRun.calls.ssh, 1);
  assert.equal(replacementRun.calls.lastSshConfig.host, 'po0.example.com');
  assert.equal(replacementRun.calls.lastSshConfig.password, 'secret-password');
  assert.equal(replacementRun.calls.lastCommand.includes("'iphone'"), true);
  assert.equal(replacementRun.calls.lastCommand.includes("'secret-token'"), true);
  assert.equal(result.ok, true);
}

async function testStoredConfigIsAuthoritativeUntilExplicitSave() {
  const storage = createStorage();
  const saveRun = createContext({
    trigger: '保存本机 PO0 上报配置',
    storage,
  });
  await runEgernReport(saveRun.ctx);

  const replacementRun = createContext({
    trigger: 'network',
    completeEnv: false,
    storage,
    env: baseEnv({
      PO0_HOST: 'replacement.example.com',
      PO0_PASSWORD: 'replacement-password',
      SSH_REPORT_SOURCE: 'replacement-source',
      SSH_REPORT_TOKEN: 'replacement-token',
    }),
  });
  await runEgernReport(replacementRun.ctx);

  assert.equal(replacementRun.calls.lastSshConfig.host, 'po0.example.com');
  assert.equal(replacementRun.calls.lastSshConfig.password, 'secret-password');
  assert.equal(replacementRun.calls.lastCommand.includes('replacement-source'), false);
  assert.equal(replacementRun.calls.lastCommand.includes('replacement-token'), false);
}

async function testExplicitSaveMergesPatchAndIgnoresReplacementDefaults() {
  const storage = createStorage();
  const initialSave = createContext({
    trigger: '保存本机 PO0 上报配置',
    storage,
  });
  await runEgernReport(initialSave.ctx);

  const patchSave = createContext({
    trigger: '保存本机 PO0 上报配置',
    completeEnv: false,
    env: { TTL_SECONDS: '50000' },
    storage,
  });
  await runEgernReport(patchSave.ctx);
  let stored = await readStoredConfig(storage);
  assert.equal(stored.values.TTL_SECONDS, '50000');
  assert.equal(stored.values.SSH_REPORT_SOURCE, 'iphone');

  const replacementDefaultsSave = createContext({
    trigger: '保存本机 PO0 上报配置',
    completeEnv: false,
    env: {
      TTL_SECONDS: '43200',
      SSH_REPORT_SOURCE: 'egern',
    },
    storage,
  });
  await runEgernReport(replacementDefaultsSave.ctx);
  stored = await readStoredConfig(storage);
  assert.equal(stored.values.TTL_SECONDS, '50000');
  assert.equal(stored.values.SSH_REPORT_SOURCE, 'iphone');
}

async function testMissingConfigIsSilentForAutomaticRunsAndGuidedForManualRuns() {
  const storage = createStorage();
  const automaticRun = createContext({
    trigger: 'schedule',
    completeEnv: false,
    env: {},
    storage,
  });
  const automaticResult = await runEgernReport(automaticRun.ctx);

  assert.equal(automaticRun.calls.http, 0);
  assert.equal(automaticRun.calls.ssh, 0);
  assert.equal(automaticRun.calls.notifications.length, 0);
  assert.equal(automaticRun.calls.logs.length, 0);
  assert.equal(automaticResult.skipped, true);
  assert.equal(automaticResult.skipType, 'missing-config');
  assert.equal(await storage.get(STORAGE_KEY), null);

  const manualRun = createContext({
    trigger: '立即上报 PO0 SSH IP',
    completeEnv: false,
    env: {},
    storage,
  });
  const manualResult = await runEgernReport(manualRun.ctx);
  assert.equal(manualRun.calls.http, 0);
  assert.equal(manualRun.calls.ssh, 0);
  assert.equal(manualRun.calls.notifications.length, 0);
  assert.equal(serializedResult(manualResult).includes('保存本机自建 PO0 / 通用设置'), true);
}

async function testCompleteLegacyEnvBootstrapsNativeStorage() {
  const { ctx, storage } = createContext({
    trigger: 'schedule',
  });

  await runEgernReport(ctx);
  const stored = await readStoredConfig(storage);

  assert.equal(stored.version, 1);
  assert.equal(stored.values.PO0_HOST, 'po0.example.com');
  assert.equal(stored.values.SSH_REPORT_TOKEN, 'secret-token');
}

async function testClearConfigKeepsDeviceId() {
  const storage = createStorage({
    [CONFIG_STORAGE_KEY]: JSON.stringify({
      version: 1,
      savedAt: '2026-07-26T00:00:00.000Z',
      values: baseEnv(),
    }),
    [STORAGE_KEY]: JSON.stringify({ ok: true }),
    [ERROR_STORAGE_KEY]: 'old error',
    [DEVICE_ID_KEY]: 'iphone15pm',
  });
  const clearRun = createContext({
    trigger: '清除本机 PO0 上报配置',
    completeEnv: false,
    env: {},
    storage,
  });

  await runEgernReport(clearRun.ctx);

  assert.deepEqual((await readStoredConfig(storage)).values, {
    WORKER_AUTO_ENABLED: 'false', OFFICIAL_AUTO_ENABLED: 'false',
  });
  assert.equal(await storage.get(STORAGE_KEY), null);
  assert.equal(await storage.get(ERROR_STORAGE_KEY), null);
  assert.equal(await storage.get(DEVICE_ID_KEY), 'iphone15pm');
  assert.equal(clearRun.calls.http, 0);
  assert.equal(clearRun.calls.ssh, 0);
  const nextRun = createContext({ trigger: 'schedule', storage });
  await runEgernReport(nextRun.ctx);
  assert.equal(nextRun.calls.http, 0);
  assert.equal(nextRun.calls.ssh, 0);
  assert.equal((await readStoredConfig(storage)).values.SSH_REPORT_TOKEN, undefined);
}

const tests = [
  testAutomaticMatchingSsidSkipsBeforeNetworkCalls,
  testAutomaticMatchingSsidPreservesPreviousSuccessState,
  testAutomaticUnmatchedWifiReports,
  testAutomaticMissingSsidFailsOpen,
  testAutomaticCellularReportsEvenWithSkipList,
  testManualMatchingSsidStillReports,
  testStatusAndWidgetMatchingSsidStillReport,
  testExplicitSavePersistsReportConfigWithoutNetworkCalls,
  testStoredConfigReportsAfterProfileReplacement,
  testStoredConfigIsAuthoritativeUntilExplicitSave,
  testExplicitSaveMergesPatchAndIgnoresReplacementDefaults,
  testMissingConfigIsSilentForAutomaticRunsAndGuidedForManualRuns,
  testCompleteLegacyEnvBootstrapsNativeStorage,
  testClearConfigKeepsDeviceId,
];

for (const test of tests) {
  await test();
  console.log(`ok - ${test.name}`);
}
