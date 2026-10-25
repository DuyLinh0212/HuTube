import { DOCUMENT } from '@angular/common';
import { Injectable, inject } from '@angular/core';

export const CHUNK_RETRY_KEY = 'dalitu.admin.chunk-retry';
const RETRY_WINDOW_MS = 60_000;

export function internalPath(value: string, origin: string): string | null {
  if (!value.startsWith('/') || value.startsWith('//') || value.includes('\\')) return null;
  try {
    const url = new URL(value, origin);
    return url.origin === origin ? url.pathname + url.search + url.hash : null;
  } catch { return null; }
}

export function isChunkLoadError(error: unknown): boolean {
  const message = error instanceof Error ? error.message
    : typeof error === 'string' ? error
    : error && typeof error === 'object' && 'message' in error ? String(error.message) : '';
  return /failed to fetch dynamically imported module|error loading dynamically imported module|importing a module script failed|loading (?:css )?chunk .+ failed|chunkloaderror/i.test(message);
}

@Injectable({ providedIn: 'root' })
export class ChunkLoadRecovery {
  private readonly browser = inject(DOCUMENT).defaultView;

  recover(error: unknown, requestedUrl: string): string | null {
    const browser = this.browser;
    if (!browser || !isChunkLoadError(error)) return null;
    const target = internalPath(requestedUrl, browser.location.origin);
    if (!target || target.startsWith('/load-error')) return null;
    // A full document request gets the current build and clears the browser's
    // failed import cache. Persist the guard across that reload, not just in RAM.
    if (browser.navigator.onLine) {
      try {
        const last = Number(browser.sessionStorage.getItem(CHUNK_RETRY_KEY));
        const now = Date.now();
        if (!last || now - last >= RETRY_WINDOW_MS) {
          browser.sessionStorage.setItem(CHUNK_RETRY_KEY, String(now));
          browser.location.replace(target);
        }
      } catch {
        // Storage can be blocked. Offer a manual retry instead of risking a loop.
      }
    }
    return target;
  }
}
