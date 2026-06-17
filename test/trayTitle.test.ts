import { describe, expect, it } from 'vitest';
import { formatTrayTitle } from '../electron/trayTitle';

describe('formatTrayTitle', () => {
  it('uses a visible app name before quota is available', () => {
    expect(formatTrayTitle(undefined)).toBe('Abar');
  });

  it('shows Codex quota percentage when available', () => {
    expect(formatTrayTitle(78.4)).toBe('C 78%');
  });
});
