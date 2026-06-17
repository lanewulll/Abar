import type { AbarApi } from '../../electron/preload';

declare global {
  interface Window {
    abar: AbarApi;
  }
}

export {};
