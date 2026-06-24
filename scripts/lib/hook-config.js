export const ABAR_HOOK_MARKER = 'ABAR_HOOK_OWNER=abar-v1';
const EVENTS = ['UserPromptSubmit', 'Stop'];

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function commandFor(reporterPath, port) {
  return `${ABAR_HOOK_MARKER} ABAR_SERVER_PORT=${port} node ${shellQuote(reporterPath)}`;
}

export function buildAbarHookConfig(reporterPath, port = 3987) {
  const command = commandFor(reporterPath, port);
  const group = {
    hooks: [{
      type: 'command',
      command,
      timeout: 2,
      statusMessage: 'Abar 正在记录本地任务状态'
    }]
  };
  return {
    hooks: Object.fromEntries(EVENTS.map((event) => [event, [structuredClone(group)]]))
  };
}

function commandsIn(group) {
  return Array.isArray(group?.hooks)
    ? group.hooks.map((hook) => String(hook?.command ?? ''))
    : [];
}

export function isOwnedAbarGroup(group) {
  return commandsIn(group).some((command) => command.includes(ABAR_HOOK_MARKER));
}

export function isLegacyAbarGroup(group) {
  return commandsIn(group).some((command) =>
    command.includes('codex-hook-reporter/reporter.js') && !command.includes(ABAR_HOOK_MARKER)
  );
}

export function mergeAbarHooks(existing, generated) {
  const result = structuredClone(existing ?? {});
  result.hooks = typeof result.hooks === 'object' && result.hooks !== null ? result.hooks : {};

  for (const event of EVENTS) {
    const current = Array.isArray(result.hooks[event]) ? result.hooks[event] : [];
    result.hooks[event] = [
      ...current.filter((group) => !isOwnedAbarGroup(group) && !isLegacyAbarGroup(group)),
      ...structuredClone(generated.hooks[event] ?? [])
    ];
  }
  return result;
}

export function removeOwnedAbarHooks(existing) {
  const result = structuredClone(existing ?? {});
  const legacyEntries = [];
  let removedCount = 0;
  if (typeof result.hooks !== 'object' || result.hooks === null) {
    return { config: result, removedCount, legacyEntries };
  }

  for (const [event, groups] of Object.entries(result.hooks)) {
    if (!Array.isArray(groups)) {
      continue;
    }
    const kept = [];
    groups.forEach((group, index) => {
      if (isOwnedAbarGroup(group)) {
        removedCount += 1;
      } else {
        kept.push(group);
        if (isLegacyAbarGroup(group)) {
          legacyEntries.push({ event, index });
        }
      }
    });
    result.hooks[event] = kept;
  }
  return { config: result, removedCount, legacyEntries };
}

