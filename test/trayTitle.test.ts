import { describe, expect, it } from 'vitest';
import { formatTrayTitle } from '../electron/trayTitle';

describe('formatTrayTitle', () => {
  it('uses a minimal spacer title before quota is available', () => {
    expect(formatTrayTitle(undefined)).toBe(' ');
  });

  it('keeps the title minimal when quota percentage is available', () => {
    expect(formatTrayTitle(78.4)).toBe(' ');
  });
});
