import { describe, expect, it } from 'vitest';
import { POPOVER_SIZE } from '../electron/popoverSize';

describe('popover size', () => {
  it('uses a compact fixed height for the condensed menu bar panel', () => {
    expect(POPOVER_SIZE).toEqual({ width: 420, height: 480 });
  });
});
