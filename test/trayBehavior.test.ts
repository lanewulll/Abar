import { describe, expect, it } from 'vitest';
import { shouldUseNativeTrayMenu } from '../electron/trayBehavior';

describe('tray behavior', () => {
  it('does not use a native tray menu because Abar opens a popover instead', () => {
    expect(shouldUseNativeTrayMenu()).toBe(false);
  });
});
