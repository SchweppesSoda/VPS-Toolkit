const STORAGE_KEY = 'po0-client-ip-report:last';

async function storageGet(ctx, key) {
  const storage = ctx?.storage;
  if (!storage) return null;
  if (typeof storage.get === 'function') return await storage.get(key);
  if (typeof storage.getItem === 'function') return await storage.getItem(key);
  if (typeof storage.read === 'function') return await storage.read(key);
  return null;
}

function parseState(raw) {
  if (!raw) return null;
  if (typeof raw === 'object') return raw;
  try {
    return JSON.parse(raw);
  } catch (_) {
    return null;
  }
}

function formatTime(value) {
  if (!value) return 'never';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return date.toLocaleString();
}

function ttlRemaining(expiresAt) {
  if (!expiresAt) return 'unknown';
  const ms = new Date(expiresAt).getTime() - Date.now();
  if (!Number.isFinite(ms)) return 'unknown';
  if (ms <= 0) return 'expired';
  const minutes = Math.floor(ms / 60000);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return `${hours}h ${rest}m`;
}

function panel(title, content, ok) {
  return {
    title,
    content,
    icon: ok ? 'checkmark.shield' : 'exclamationmark.triangle',
    'icon-color': ok ? '#2aa876' : '#d46a6a',
  };
}

function targetSummaryLines(state) {
  const targets = Array.isArray(state.targets) ? state.targets : [];
  if (targets.length === 0) {
    if (state.expiresAt) return [`${state.reportName || 'egern'}@${state.po0Host || 'PO0'} TTL ${ttlRemaining(state.expiresAt)}`];
    return [];
  }
  return targets.slice(0, 4).map((target) => {
    const name = `${target.reportName || 'egern'}@${target.host || 'PO0'}`;
    if (target.ok) return `${name} TTL ${ttlRemaining(target.expiresAt)}`;
    return `${name} failed: ${target.error || 'unknown'}`;
  });
}

export default async function(ctx) {
  const state = parseState(await storageGet(ctx, STORAGE_KEY));
  if (!state) {
    return panel('PO0 Client IP', 'No report state yet.\nRun "PO0 Client IP Report Now" once.', false);
  }

  if (!state.ok) {
    const targets = Array.isArray(state.targets) ? state.targets : [];
    const successCount = state.successCount ?? targets.filter((target) => target.ok).length;
    const targetCount = state.targetCount ?? targets.length;
    return panel(
      'PO0 Client IP',
      [
        `IP: ${state.ip || 'unknown'}`,
        `Last failure: ${formatTime(state.at)}`,
        `Targets: ${successCount}/${targetCount || 1} OK`,
        `Network: ${state.network || 'unknown'}`,
        ...(targetSummaryLines(state).length ? targetSummaryLines(state) : [`Reason: ${state.error || 'unknown'}`]),
      ].join('\n'),
      false,
    );
  }

  return panel(
    'PO0 Client IP',
    [
      `IP: ${state.ip || 'unknown'}`,
      `Targets: ${state.successCount ?? 1}/${state.targetCount ?? 1} OK`,
      `Last success: ${formatTime(state.at)}`,
      `Network: ${state.network || 'unknown'}`,
      ...targetSummaryLines(state),
    ].join('\n'),
    true,
  );
}
