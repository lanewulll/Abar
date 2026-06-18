import { describe, expect, it } from 'vitest';
import { recoverRightEdgeStatusBounds } from '../electron/statusItemBounds';

describe('recoverRightEdgeStatusBounds', () => {
  it('recovers Electron status item bounds reported at the bottom-left edge on macOS', () => {
    expect(
      recoverRightEdgeStatusBounds(
        { x: 0, y: 1440, width: 46, height: 0 },
        { x: 0, y: 30, width: 2560, height: 1320 }
      )
    ).toEqual({ x: 2502, y: 6, width: 46, height: 24 });
  });

  it('does not rewrite already usable status item bounds', () => {
    expect(
      recoverRightEdgeStatusBounds(
        { x: 2210, y: 4, width: 46, height: 24 },
        { x: 0, y: 30, width: 2560, height: 1320 }
      )
    ).toBeNull();
  });
});
