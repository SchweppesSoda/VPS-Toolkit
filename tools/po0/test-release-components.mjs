import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { releasePlan, shouldBeLatest, prepareAssets, validateAssets, publishAssets } from './release-components.mjs';

const scripts = ['nftables-relay-manager.sh', 'po0-lan-client.sh', 'po0-outbound-ip-report.sh', 'po0-outbound-ip-report-macos.sh', 'po0-outbound-ip-report.ps1'];
function fixture(component = 'scripts') {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'po0-release-test-'));
  const names = component === 'scripts' ? scripts : ['po0-outbound-ip-report.apk'];
  for (const name of names) fs.writeFileSync(path.join(directory, name), component === 'apk' ? 'apk-fixture' : name.endsWith('.ps1') ? '$ScriptVersion = "2026.09.05+build.9"\n' : 'SCRIPT_VERSION="2026.09.05+build.9"\n');
  prepareAssets(component, directory);
  return directory;
}
function fakeGitHub({ draft = null, initial = {}, latest = 'po0-v2026.09.05.8', corruptDownload = false } = {}) {
  let isDraft = draft;
  const files = new Map(Object.entries(initial));
  const calls = [];
  return {
    calls, files,
    view: () => isDraft === null ? null : { isDraft, assets: [...files.keys()].map(name => ({ name })) },
    latest: () => latest,
    create: () => { calls.push('create'); isDraft = true; },
    upload: (_tag, file) => { calls.push('upload:' + path.basename(file)); files.set(path.basename(file), fs.readFileSync(file)); },
    download: (_tag, name, directory) => { calls.push('download:' + name); fs.writeFileSync(path.join(directory, name), corruptDownload ? 'corrupt' : files.get(name)); },
    publish: (_tag, makeLatest) => { calls.push('publish:' + makeLatest); isDraft = false; }
  };
}
function existing(directory) {
  return Object.fromEntries(fs.readdirSync(directory).map(name => [name, fs.readFileSync(path.join(directory, name))]));
}
test('component tags select independent publication and reject malformed tags', () => {
  assert.equal(releasePlan('po0-scripts-v2026.09.05.9').component, 'scripts');
  assert.equal(releasePlan('po0-apk-v2026.09.05.9').component, 'apk');
  assert.equal(releasePlan('po0-v2026.09.05.9').component, 'full');
  assert.equal(releasePlan('po0-scripts-v2026.09.05.9').canonical_tag, 'po0-v2026.09.05.9');
  for (const tag of ['po0-scripts-v2026.02.30.9', 'po0-apk-v2026.13.05.9', 'v2026.09.05.9', 'po0-v2026.09.05.9-other']) assert.throws(() => releasePlan(tag));
});
test('APK releases never become Latest and older releases cannot downgrade Latest', () => {
  assert.equal(shouldBeLatest('po0-apk-v2026.09.05.99', null), false);
  assert.equal(shouldBeLatest('po0-v2026.09.05.8', 'po0-scripts-v2026.09.05.9'), false);
  assert.equal(shouldBeLatest('po0-scripts-v2026.09.05.9', 'po0-v2026.09.05.8'), true);
  assert.equal(shouldBeLatest('po0-scripts-v2026.09.05.9', 'po0-v2026.09.05.9'), false);
});
test('scripts publish without APKs and only after every upload is downloaded and verified', t => {
  const directory = fixture(); t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const adapter = fakeGitHub();
  const release = publishAssets('po0-scripts-v2026.09.05.9', directory, adapter);
  assert.equal(release.isDraft, false);
  assert.equal(release.assets.length, 6);
  assert.equal(adapter.calls.at(-1), 'publish:true');
  for (const { name } of release.assets) assert(adapter.calls.indexOf('download:' + name) < adapter.calls.indexOf('publish:true'));
});
test('APK publication remains independent from script inventory and Latest', t => {
  const directory = fixture('apk'); t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const adapter = fakeGitHub();
  publishAssets('po0-apk-v2026.09.05.19', directory, adapter);
  assert.equal(adapter.calls.at(-1), 'publish:false');
  assert.equal(adapter.files.size, 2);
});
test('wrong versions, checksums, incomplete assets and extra files fail before publishing', t => {
  const directory = fixture(); t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  assert.throws(() => validateAssets('po0-scripts-v2026.09.05.10', directory), /version/);
  fs.appendFileSync(path.join(directory, scripts[0]), 'tampered');
  assert.throws(() => validateAssets('po0-scripts-v2026.09.05.9', directory), /checksum/);
  prepareAssets('scripts', directory);
  fs.writeFileSync(path.join(directory, 'po0-outbound-ip-report.apk'), 'unrequested-apk');
  assert.throws(() => prepareAssets('scripts', directory), /inventory/);
  fs.unlinkSync(path.join(directory, 'po0-outbound-ip-report.apk'));
  fs.writeFileSync(path.join(directory, 'po0-wan-probe.sh'), 'obsolete');
  assert.throws(() => prepareAssets('scripts', directory), /inventory/);
  fs.unlinkSync(path.join(directory, 'po0-wan-probe.sh'));
  fs.unlinkSync(path.join(directory, scripts[0]));
  assert.throws(() => prepareAssets('scripts', directory), /inventory/);
});
test('existing live releases are verified without mutation; incomplete live releases fail', t => {
  const directory = fixture(); t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const complete = fakeGitHub({ draft: false, initial: existing(directory) });
  publishAssets('po0-scripts-v2026.09.05.9', directory, complete);
  assert(complete.calls.every(call => call.startsWith('download:')));
  const incomplete = fakeGitHub({ draft: false });
  assert.throws(() => publishAssets('po0-scripts-v2026.09.05.9', directory, incomplete), /incomplete/);
  assert.deepEqual(incomplete.calls, []);
});
test('draft retries preserve existing assets and refuse checksum mismatches', t => {
  const directory = fixture(); t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const partial = fakeGitHub({ draft: true, initial: { [scripts[0]]: fs.readFileSync(path.join(directory, scripts[0])) } });
  publishAssets('po0-scripts-v2026.09.05.9', directory, partial);
  assert(!partial.calls.includes('upload:' + scripts[0]));
  assert.equal(partial.calls.at(-1), 'publish:true');
  const corrupt = fakeGitHub({ draft: true, initial: { [scripts[0]]: Buffer.from('wrong') } });
  assert.throws(() => publishAssets('po0-scripts-v2026.09.05.9', directory, corrupt), /checksum/);
  assert(corrupt.calls.every(call => call.startsWith('download:')));
});
test('failed download verification keeps a new release in draft', t => {
  const directory = fixture(); t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const adapter = fakeGitHub({ corruptDownload: true });
  assert.throws(() => publishAssets('po0-scripts-v2026.09.05.9', directory, adapter), /checksum/);
  assert.equal(adapter.view().isDraft, true);
  assert(!adapter.calls.some(call => call.startsWith('publish:')));
});