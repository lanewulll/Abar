export function compareUpdateState({ currentCommit, latestCommit }) {
  if (!currentCommit || !latestCommit) {
    return { status: 'unknown', currentCommit, latestCommit };
  }
  return {
    status: currentCommit === latestCommit ? 'current' : 'available',
    currentCommit,
    latestCommit
  };
}
