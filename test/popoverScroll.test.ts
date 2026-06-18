import { describe, expect, it } from 'vitest';
import { buildResetPopoverScrollScript } from '../electron/popoverScroll';

describe('buildResetPopoverScrollScript', () => {
  it('resets the popover content scroll position to the top', () => {
    const script = buildResetPopoverScrollScript();

    expect(script).toContain('.popover-content');
    expect(script).toContain('scrollTop = 0');
  });
});
