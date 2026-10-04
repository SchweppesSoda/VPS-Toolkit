import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const normalize = text => text.replace(/^\ufeff/, '').replace(/\r\n?/g, '\n');

export function syncClientCompatibility(root, mode = '--check') {
  if (!['--check', '--write'].includes(mode)) throw new Error('Unknown compatibility sync mode: ' + mode);
  root = path.resolve(root);
  const manifest = fs.readFileSync(path.join(root, 'tools/po0/manifests/client-compat.txt'), 'utf8');
  const copies = new Set();
  const sources = new Set();
  const plan = [];
  const clientPath = /^scripts\/po0\/nftables\/clients\/(?:egern|stash)\/[^/]+\.(?:yaml|js|stoverride)$/;
  const egernLegacyPath = /^scripts\/po0\/relay\/egern\/(?:PO0-SSH-IP-Report\.yaml|po0-ssh-ip-report\.js)$/;
  // Preflight the complete manifest and all sources before changing any copy.
  for (const line of manifest.split(/\r?\n/)) {
    if (!line.trim() || line.trim().startsWith('#')) continue;
    const entries = line.split('|');
    if (entries.length !== 2) throw new Error('Invalid compatibility mapping: ' + line);
    const [canonical, legacy] = entries.map(entry => entry.trim());
    if (!clientPath.test(canonical) || (!clientPath.test(legacy) && !egernLegacyPath.test(legacy))) {
      throw new Error('Compatibility mapping outside client scope: ' + line);
    }
    for (const entry of [canonical, legacy]) {
      if (!path.resolve(root, entry).startsWith(root + path.sep)) throw new Error('Compatibility path outside repository: ' + entry);
    }
    if (canonical === legacy || copies.has(legacy)) throw new Error('Duplicate compatibility destination: ' + legacy);
    copies.add(legacy);
    sources.add(canonical);
    const text = normalize(fs.readFileSync(path.join(root, canonical), 'utf8'));
    const destination = path.join(root, legacy);
    const matches = fs.existsSync(destination) && normalize(fs.readFileSync(destination, 'utf8')) === text;
    plan.push({ text, destination, legacy, matches });
  }
  if (!plan.length) throw new Error('Client compatibility manifest is empty.');
  for (const legacy of copies) {
    if (sources.has(legacy)) throw new Error('A compatibility destination cannot be a canonical source: ' + legacy);
  }
  for (const item of plan) {
    if (item.matches) continue;
    if (mode === '--write') fs.writeFileSync(item.destination, item.text, 'utf8');
    else throw new Error('Compatibility copy differs from canonical source: ' + item.legacy + '. Run the asset builder with its client compatibility sync option.');
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const mode = process.argv[2] || '--check';
  if (process.argv.length > 3) throw new Error('Usage: node tools/po0/sync-po0-client-compat.mjs [--check|--write]');
  syncClientCompatibility(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..'), mode);
  console.log('PO0 client compatibility copies ' + (mode === '--write' ? 'synchronized.' : 'verified.'));
}
