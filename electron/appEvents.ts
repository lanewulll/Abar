export const APP_STATE_CHANGED_CHANNEL = 'app:stateChanged';

export type StateChangeTarget = {
  isDestroyed: () => boolean;
  webContents: {
    send: (channel: string) => void;
  };
};

export function broadcastStateChanged(windows: StateChangeTarget[]): number {
  let notified = 0;
  for (const window of windows) {
    if (window.isDestroyed()) {
      continue;
    }
    window.webContents.send(APP_STATE_CHANGED_CHANNEL);
    notified += 1;
  }
  return notified;
}
