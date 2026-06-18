import { describe, expect, it } from 'vitest';
import {
  AUTO_REFRESH_INTERVALS_MS,
  shouldOpenNativeMenuForTrayEvent,
  shouldOpenPopoverForMouseUpEvent,
  shouldOpenPopoverForTrayEvent,
  shouldUseNativeTrayMenu
} from '../electron/trayBehavior';

describe('tray behavior', () => {
  it('uses a native tray menu for right-click quit while keeping normal clicks for the popover', () => {
    expect(shouldUseNativeTrayMenu()).toBe(true);
    expect(shouldOpenNativeMenuForTrayEvent('right-click')).toBe(true);
    expect(shouldOpenPopoverForTrayEvent('right-click')).toBe(false);
    expect(shouldOpenPopoverForTrayEvent('click')).toBe(true);
    expect(shouldOpenPopoverForTrayEvent('mouse-up')).toBe(true);
  });

  it('does not open the popover from secondary mouse-up events', () => {
    expect(shouldOpenPopoverForMouseUpEvent({ button: 'right' })).toBe(false);
    expect(shouldOpenPopoverForMouseUpEvent({ button: 2 })).toBe(false);
    expect(shouldOpenPopoverForMouseUpEvent({ button: 'left' })).toBe(true);
  });

  it('defines automatic refresh intervals for quota and skills', () => {
    expect(AUTO_REFRESH_INTERVALS_MS.quota).toBe(30 * 1000);
    expect(AUTO_REFRESH_INTERVALS_MS.skills).toBe(60 * 1000);
  });
});
