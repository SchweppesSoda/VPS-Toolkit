import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { releasePlan } from './release-components.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8').replace(/\r\n/g, '\n');
const bashSource = read('tools/po0/check-po0-assets.sh');
const psSource = read('tools/po0/check-po0-assets.ps1');
const canonical = /PO0_EXPECTED_RELEASE_TAG:-([^}]+)/.exec(bashSource)[1];
const plan = releasePlan(canonical);
const scriptsTag = canonical.replace('po0-v', 'po0-scripts-v');
const tmpRoot = path.join(root, '.tmp');
fs.mkdirSync(tmpRoot, { recursive: true });
const directory = fs.mkdtempSync(path.join(tmpRoot, 'po0-version-tags-'));
const assets = path.join(directory, 'assets');
fs.mkdirSync(assets);
const names = ['nftables-relay-manager.sh', 'po0-lan-client.sh', 'po0-outbound-ip-report.sh', 'po0-outbound-ip-report-macos.sh', 'po0-outbound-ip-report.ps1'];
function writeAsset(name, version = plan.version) {
  const header = name.endsWith('.ps1')
    ? '$ScriptVersion = "' + version + '"\n$ScriptReleaseDate = "' + plan.date + '"\n'
    : 'SCRIPT_VERSION="' + version + '"\nSCRIPT_RELEASE_DATE="' + plan.date + '"\n';
  fs.writeFileSync(path.join(assets, name), header + '# CHANGELOG_BEGIN\n# Version fixture\n# CHANGELOG_END\n');
}
for (const name of names) writeAsset(name);
const bashHarness = path.join(directory, 'versions.sh');
const psHarness = path.join(directory, 'versions.ps1');
fs.writeFileSync(bashHarness, bashSource.slice(0, bashSource.indexOf('\ncheck_manifest_coverage "manager"')) + '\ncheck_versions_consistent\ncheck_versions_match_tag\n');
fs.writeFileSync(psHarness, '\ufeff' + psSource.replace(/^\ufeff/, '').slice(0, psSource.replace(/^\ufeff/, '').indexOf('\nTest-RawReferences\n')) + '\nTest-VersionsConsistent\nTest-VersionsMatchTag\n');
const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';
const powershell = process.platform === 'win32' ? 'powershell.exe' : 'pwsh';
const engines = [
  [bash, [path.relative(root, bashHarness).replaceAll('\\', '/'), path.relative(root, assets).replaceAll('\\', '/')]],
  [powershell, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', psHarness, '-OutputDir', assets]],
];
try {
  for (const [engine, args] of engines) {
    for (const [tag, valid] of [[scriptsTag, true], [canonical, true], [scriptsTag + '0', false], [canonical.replace('po0-v', 'po0-apk-v'), false]]) {
      const env = { ...process.env, GITHUB_REF_NAME: tag, GITHUB_REF_TYPE: 'tag', GITHUB_REF: 'refs/tags/' + tag };
      for (const key of ['PO0_EXPECTED_ASSET_VERSION', 'PO0_EXPECTED_RELEASE_DATE', 'PO0_EXPECTED_RELEASE_TAG']) delete env[key];
      const result = spawnSync(engine, args, { cwd: root, env, encoding: 'utf8' });
      if (result.error) throw result.error;
      assert.equal(result.status === 0, valid, path.basename(engine) + ': unexpected acceptance for ' + tag + '\n' + result.stderr);
    }
    writeAsset(names[0], '2000.01.01+build.1');
    const result = spawnSync(engine, args, { cwd: root, env: { ...process.env, GITHUB_REF_NAME: scriptsTag, GITHUB_REF_TYPE: 'tag', GITHUB_REF: 'refs/tags/' + scriptsTag }, encoding: 'utf8' });
    assert.notEqual(result.status, 0, 'A component tag must still reject a mismatched script version.');
    writeAsset(names[0]);
  }
  console.log('Bash / PowerShell real tag checks: scripts/full accepted; wrong tags, APK tags and mismatched assets rejected.');
} finally {
  assert(path.resolve(directory).startsWith(path.resolve(tmpRoot) + path.sep));
  fs.rmSync(directory, { recursive: true, force: true });
}
