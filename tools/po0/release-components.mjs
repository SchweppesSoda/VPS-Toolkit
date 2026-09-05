import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const scriptNames = ['nftables-relay-manager.sh', 'po0-lan-client.sh', 'po0-outbound-ip-report.sh', 'po0-outbound-ip-report-macos.sh', 'po0-outbound-ip-report.ps1'];
const packageNames = ['po0-outbound-ip-report.apk'];
export function releasePlan(tag) {
  const match = /^po0-(?:(scripts|apk)-)?v(\d{4})\.(\d{2})\.(\d{2})\.([1-9]\d*|0)$/.exec(tag);
  if (!match) throw new Error('Expected po0-[scripts-|apk-]vYYYY.MM.DD.N tag');
  const [, component = 'full', year, month, day, build] = match;
  const date = year + '-' + month + '-' + day;
  if (new Date(date + 'T00:00:00Z').toISOString().slice(0, 10) !== date) throw new Error('Invalid release date');
  return { component, tag, version: year + '.' + month + '.' + day + '+build.' + build,
    date, canonical_tag: 'po0-v' + year + '.' + month + '.' + day + '.' + build,
    order: [year, month, day, build].map(Number) };
}
export function shouldBeLatest(tag, currentTag) {
  const plan = releasePlan(tag);
  if (plan.component === 'apk') return false;
  if (!currentTag) return true;
  const current = releasePlan(currentTag);
  if (current.component === 'apk') return true;
  for (let i = 0; i < plan.order.length; i++) {
    if (plan.order[i] !== current.order[i]) return plan.order[i] > current.order[i];
  }
  return plan.component === 'full' || current.component !== 'full';
}
function sha(file) { return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'); }
export function inventory(component, directory) {
  if (!['scripts', 'apk', 'full'].includes(component)) throw new Error('Invalid component');
  const required = component === 'scripts' ? scriptNames : component === 'apk' ? packageNames : [...scriptNames, ...packageNames];
  const entries = fs.readdirSync(directory).filter(name => name !== 'checksums.txt').sort();
  if (required.some(name => !entries.includes(name)) || entries.some(name => !required.includes(name))) throw new Error('Unexpected or incomplete release asset inventory');
  for (const name of entries) {
    const stat = fs.lstatSync(path.join(directory, name));
    if (!stat.isFile() || !stat.size) throw new Error('Release assets must be nonempty regular files: ' + name);
  }
  return entries;
}
export function prepareAssets(component, directory) {
  const names = inventory(component, directory);
  fs.writeFileSync(path.join(directory, 'checksums.txt'), names.map(name => sha(path.join(directory, name)) + '  ' + name).join('\n') + '\n', 'utf8');
  return names;
}
export function validateAssets(tag, directory) {
  const plan = releasePlan(tag), names = inventory(plan.component, directory);
  const checksum = fs.readFileSync(path.join(directory, 'checksums.txt'), 'utf8').trim().split(/\r?\n/);
  const expected = new Map();
  for (const line of checksum) {
    const match = /^([a-f0-9]{64})  ([^/\\]+)$/.exec(line);
    if (!match || expected.has(match[2])) throw new Error('Malformed or duplicate checksum entry');
    expected.set(match[2], match[1]);
  }
  if (expected.size !== names.length || names.some(name => expected.get(name) !== sha(path.join(directory, name)))) throw new Error('Asset checksum mismatch');
  for (const name of names.filter(name => /\.(sh|ps1)$/.test(name))) {
    const source = fs.readFileSync(path.join(directory, name), 'utf8');
    const version = /^(?:SCRIPT_VERSION=|\$ScriptVersion\s*=\s*)"([^"]+)"/m.exec(source)?.[1];
    if (version !== plan.version) throw new Error('Script version does not match release tag: ' + name);
  }
  expected.set('checksums.txt', sha(path.join(directory, 'checksums.txt')));
  return { plan, names: [...names, 'checksums.txt'], expected };
}
function gh(args, allowMissing = false) {
  const result = spawnSync('gh', args, { encoding: 'utf8' });
  if (result.status !== 0) {
    if (allowMissing && /HTTP 404|Not Found|release not found/i.test(result.stderr || '')) return null;
    throw new Error('GitHub CLI failed: ' + args.slice(0, 2).join(' '));
  }
  return result.stdout;
}
export function githubAdapter(repo) {
  return {
    view: tag => { const value = gh(['release', 'view', tag, '--repo', repo, '--json', 'isDraft,assets,url'], true); return value === null ? null : JSON.parse(value); },
    latest: () => { const value = gh(['api', 'repos/' + repo + '/releases/latest'], true); return value === null ? null : JSON.parse(value).tag_name; },
    create: (tag, notes) => gh(['release', 'create', tag, '--repo', repo, '--verify-tag', '--draft', '--latest=false', '--title', tag, '--notes-file', notes]),
    upload: (tag, file) => gh(['release', 'upload', tag, '--repo', repo, file]),
    download: (tag, name, directory) => gh(['release', 'download', tag, '--repo', repo, '--pattern', name, '--dir', directory]),
    publish: (tag, latest) => gh(['release', 'edit', tag, '--repo', repo, '--draft=false', '--latest=' + latest])
  };
}
export function publishAssets(tag, directory, adapter) {
  const { plan, names, expected } = validateAssets(tag, directory);
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'po0-release-'));
  function checkInventory(release) {
    const remote = release.assets.map(asset => asset.name);
    if (new Set(remote).size !== remote.length || remote.some(name => !names.includes(name))) throw new Error('Unexpected remote release assets');
    return remote;
  }
  function verify(name) {
    const destination = fs.mkdtempSync(path.join(temp, 'verify-'));
    adapter.download(tag, name, destination);
    if (sha(path.join(destination, name)) !== expected.get(name)) throw new Error('Remote asset checksum mismatch: ' + name);
  }
  try {
    let release = adapter.view(tag);
    if (!release) {
      const notesFile = path.join(temp, 'notes.txt');
      const notes = plan.component === 'scripts'
        ? 'PO0 scripts ' + plan.version + '. APKs are published separately under po0-apk-v tags. Egern, Stash and Loon continue to use their documented raw URLs.'
        : plan.component === 'apk'
          ? 'PO0 OpenWrt APK release. Download APKs from this versioned release; the script Latest release remains unchanged.'
          : 'PO0 scripts and APK release.';
      fs.writeFileSync(notesFile, notes + '\n', 'utf8');
      adapter.create(tag, notesFile);
      release = adapter.view(tag);
      if (!release?.isDraft) throw new Error('New release is not a draft');
    }
    const remote = checkInventory(release);
    // Verify every existing asset before uploading anything; never replace an asset.
    for (const name of remote) verify(name);
    const missing = names.filter(name => !remote.includes(name));
    if (!release.isDraft && missing.length) throw new Error('Published release is incomplete; use a new tag');
    for (const name of missing) adapter.upload(tag, path.join(directory, name));
    release = adapter.view(tag);
    const complete = checkInventory(release);
    if (complete.length !== names.length) throw new Error('Release asset set is incomplete');
    for (const name of names) verify(name);
    if (release.isDraft) adapter.publish(tag, shouldBeLatest(tag, adapter.latest()));
    const published = adapter.view(tag);
    if (!published || published.isDraft) throw new Error('Release did not become public');
    return published;
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    const [command, first, second] = process.argv.slice(2);
    const repo = process.env.GH_REPO || process.env.GITHUB_REPOSITORY;
    if (command === 'plan') console.log(JSON.stringify(releasePlan(first)));
    else if (command === 'prepare') console.log(prepareAssets(first, path.resolve(second)).join('\n'));
    else if (command === 'publish') {
      if (!repo) throw new Error('GH_REPO or GITHUB_REPOSITORY is required');
      console.log(JSON.stringify(publishAssets(first, path.resolve(second), githubAdapter(repo))));
    } else if (command === 'latest-flag') {
      if (!repo) throw new Error('GH_REPO or GITHUB_REPOSITORY is required');
      console.log(shouldBeLatest(first, githubAdapter(repo).latest()) ? 'true' : 'false');
    } else throw new Error('Usage: release-components.mjs plan TAG | prepare scripts|apk|full DIR | publish TAG DIR | latest-flag TAG');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}