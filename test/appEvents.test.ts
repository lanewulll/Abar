import { describe, expect, it, vi } from 'vitest';
import { APP_STATE_CHANGED_CHANNEL, broadcastStateChanged } from '../electron/appEvents';

describe('app event broadcasting', () => {
  it('notifies every live window when app state changes', () => {
    const liveSend = vi.fn();
    const destroyedSend = vi.fn();

    const count = broadcastStateChanged([
      {
        isDestroyed: () => false,
        webContents: { send: liveSend }
      },
      {
        isDestroyed: () => true,
        webContents: { send: destroyedSend }
      }
    ]);

    expect(count).toBe(1);
    expect(liveSend).toHaveBeenCalledWith(APP_STATE_CHANGED_CHANNEL);
    expect(destroyedSend).not.toHaveBeenCalled();
  });
});
