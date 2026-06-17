export function formatTrayTitle(usedPercent: number | undefined): string {
  if (typeof usedPercent !== 'number' || !Number.isFinite(usedPercent)) {
    return 'Abar';
  }

  return `Abar ${Math.round(usedPercent)}%`;
}
