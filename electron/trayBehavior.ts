export type TrayEventName = 'click' | 'mouse-up' | 'right-click';

export const AUTO_REFRESH_INTERVALS_MS = {
  quota: 30 * 1000,
  skills: 60 * 1000
} as const;

export function shouldUseNativeTrayMenu(): boolean {
  return true;
}

export function shouldOpenNativeMenuForTrayEvent(eventName: TrayEventName): boolean {
  return eventName === 'right-click';
}

export function shouldOpenPopoverForTrayEvent(eventName: TrayEventName): boolean {
  return !shouldOpenNativeMenuForTrayEvent(eventName);
}

export function shouldOpenPopoverForMouseUpEvent(event: unknown): boolean {
  if (!event || typeof event !== 'object' || !('button' in event)) {
    return true;
  }
  const button = (event as { button?: unknown }).button;
  return button !== 'right' && button !== 2;
}
