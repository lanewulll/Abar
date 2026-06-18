import { describe, expect, it } from 'vitest';
import { calculatePopoverBounds, calculatePopoverPlacement } from '../electron/popoverGeometry';

describe('calculatePopoverBounds', () => {
  it('centers the popover below the tray icon', () => {
    expect(
      calculatePopoverBounds({
        trayBounds: { x: 700, y: 0, width: 28, height: 24 },
        windowSize: { width: 420, height: 560 },
        workArea: { x: 0, y: 0, width: 1440, height: 900 },
        gap: 8
      })
    ).toEqual({ x: 504, y: 32, width: 420, height: 560 });
  });

  it('keeps the popover inside the visible work area', () => {
    expect(
      calculatePopoverBounds({
        trayBounds: { x: 4, y: 0, width: 24, height: 24 },
        windowSize: { width: 420, height: 560 },
        workArea: { x: 16, y: 0, width: 390, height: 760 },
        gap: 8,
        margin: 12
      })
    ).toEqual({ x: 28, y: 32, width: 420, height: 560 });
  });

  it('anchors below the top menu bar when tray coordinates are reported outside the work area', () => {
    expect(
      calculatePopoverBounds({
        trayBounds: { x: 2310, y: 1440, width: 24, height: 22 },
        windowSize: { width: 420, height: 560 },
        workArea: { x: 0, y: 30, width: 2560, height: 1320 },
        gap: 8,
        margin: 12
      })
    ).toEqual({ x: 2112, y: 38, width: 420, height: 560 });
  });

  it('does not fall back to the left edge when the tray x coordinate is unusable', () => {
    expect(
      calculatePopoverPlacement({
        trayBounds: { x: 0, y: 1440, width: 69, height: 22 },
        windowSize: { width: 420, height: 560 },
        workArea: { x: 0, y: 30, width: 2560, height: 1320 },
        gap: 8,
        margin: 12
      })
    ).toBeNull();
  });

  it('reports the arrow offset from the clamped window to the tray icon center', () => {
    expect(
      calculatePopoverPlacement({
        trayBounds: { x: 2460, y: 4, width: 24, height: 22 },
        windowSize: { width: 420, height: 560 },
        workArea: { x: 0, y: 30, width: 2560, height: 1320 },
        gap: 8,
        margin: 12
      })
    ).toEqual({
      bounds: { x: 2128, y: 34, width: 420, height: 560 },
      arrowOffsetX: 344
    });
  });
});
