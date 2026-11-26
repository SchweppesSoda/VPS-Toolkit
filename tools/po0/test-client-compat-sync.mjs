import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { syncClientCompatibility } from './sync-po0-client-compat.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const tmpRoot = path.join(root, '.tmp');
fs.mkdirSync(tmpRoot, { recursive: true });
const directory = fs.mkdtempSync(path.join(tmpRoot, 'po0-client-compat-'));
const source = 'scripts/po0/nftables/clients/stash/po0-firewall.js';
const copy = 'scripts/po0/nftables/clients/stash/po0-stash-report.js';
const manifest = path.join(directory, 'tools/po0/manifests/client-compat.txt');
const write = (name, text) => { const target = path.join(directory, name); fs.mkdirSync(path.dirname(target), { recursive: true }); fs.writeFileSync(target, text); };
try {
  write(source, 'canonical\n');
  write(copy, 'old copy\n');
  write('tools/po0/manifests/client-compat.txt', source + '|' + copy + '\n');
  assert.throws(() => syncClientCompatibility(directory), /differs/);
  assert.equal(fs.readFileSync(path.join(directory, copy), 'utf8'), 'old copy\n');
  fs.appendFileSync(manifest, 'scripts/po0/nftables/clients/stash/missing.js|scripts/po0/nftables/clients/stash/other.js\n');
  assert.throws(() => syncClientCompatibility(directory, '--write'), /ENOENT/);
  assert.equal(fs.readFileSync(path.join(directory, copy), 'utf8'), 'old copy\n', 'a later invalid source must not partially write earlier copies');
  fs.writeFileSync(manifest, source + '|' + copy + '\n');
  syncClientCompatibility(directory, '--write');
  const target = path.join(directory, copy);
  fs.utimesSync(target, new Date('2000-01-01T00:00:00Z'), new Date('2000-01-01T00:00:00Z'));
  const bytes = fs.readFileSync(target);
  const modified = fs.statSync(target).mtimeMs;
  syncClientCompatibility(directory, '--write');
  syncClientCompatibility(directory, '--check');
  assert.deepEqual(fs.readFileSync(target), bytes);
  assert.equal(fs.statSync(target).mtimeMs, modified, 'an already synchronized copy must retain its mtime');
  assert.equal(fs.readFileSync(path.join(directory, source), 'utf8'), 'canonical\n');
  fs.writeFileSync(target, 'canonical destination fixture\n');
  fs.appendFileSync(manifest, copy + '|scripts/po0/nftables/clients/stash/other.js\n');
  assert.throws(() => syncClientCompatibility(directory, '--write'), /destination cannot be a canonical source/);
  assert.equal(fs.readFileSync(target, 'utf8'), 'canonical destination fixture\n', 'a destination/source chain must fail before overwriting the standard source');
  fs.writeFileSync(manifest, source + '|' + copy + '\n' + copy + '|' + source + '\n');
  assert.throws(() => syncClientCompatibility(directory, '--write'), /destination cannot be a canonical source/);
  assert.equal(fs.readFileSync(path.join(directory, source), 'utf8'), 'canonical\n', 'cycles must not overwrite either source');
  fs.writeFileSync(manifest, source + '|' + copy + '\n');
  fs.appendFileSync(manifest, source + '|scripts/po0/relay/manager/other.js\n');
  assert.throws(() => syncClientCompatibility(directory, '--write'), /outside client scope/);
  const panel = 'scripts/po0/nftables/clients/stash/PO0-Firewall.stoverride';
  const oldPanel = 'scripts/po0/nftables/clients/stash/PO0.LAN-Report.stoverride';
  const overview = 'function panelOverview(state, settings, saved) {\n  return state;\n}';
  const begin = '      // BEGIN GENERATED PO0 PANEL', end = '      // END GENERATED PO0 PANEL';
  write(source, overview + '\n');
  write('tools/po0/manifests/client-compat.txt', source + '|' + copy + '\n' + panel + '|' + oldPanel + '\n');
  for (const invalid of [begin, end + '\n' + begin, begin + '\n' + begin + '\n' + end]) {
    write(panel, invalid);
    assert.throws(() => syncClientCompatibility(directory, '--write'), /ordered marker pair/);
    assert.equal(fs.readFileSync(target, 'utf8'), 'canonical destination fixture\n');
  }
  write(panel, 'prefix\n' + begin + '\nold\n' + end + '\nsuffix\n');
  syncClientCompatibility(directory, '--write');
  const rendered = 'prefix\n' + begin + '\n' + overview.split('\n').map(line => '      ' + line).join('\n') + '\n' + end + '\nsuffix\n';
  assert.equal(fs.readFileSync(path.join(directory, panel), 'utf8'), rendered);
  assert.equal(fs.readFileSync(path.join(directory, oldPanel), 'utf8'), rendered);
  fs.utimesSync(path.join(directory, panel), 1000000, 1000000);
  syncClientCompatibility(directory, '--write');
  assert.equal(fs.statSync(path.join(directory, panel)).mtimeMs, 1000000000);
  syncClientCompatibility(root, '--check');
  console.log('PASS: client compatibility preflight, read-only checks and repeat-write no-op.');
} finally {
  assert(path.resolve(directory).startsWith(path.resolve(tmpRoot) + path.sep));
  fs.rmSync(directory, { recursive: true, force: true });
}
