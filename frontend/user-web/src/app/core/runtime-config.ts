import { Injectable } from '@angular/core';

export const ADMIN_APP = false;

export function validateApiUrl(value: unknown): string {
  if (typeof value !== 'string') throw new Error('Thiếu API_BASE_URL.');
  const url = new URL(value);
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash)
    throw new Error('API_BASE_URL không hợp lệ.');
  return url.href.replace(/\/$/, '');
}

@Injectable({ providedIn: 'root' })
export class RuntimeConfig {
  apiBaseUrl = '';
  googleClientId = '';
  async load(): Promise<void> {
    const configController = new AbortController();
    const configTimeout = setTimeout(() => configController.abort(), 10_000);
    let response: Response;
    try {
      response = await fetch('config.json', { cache: 'no-store', signal: configController.signal });
    } finally {
      clearTimeout(configTimeout);
    }
    if (!response.ok) throw new Error('Không tải được cấu hình kết nối.');
    const config = await response.json();
    const configuredApiUrl = validateApiUrl(config.API_BASE_URL);
    const localHost = typeof window !== 'undefined'
      && ['localhost', '127.0.0.1', '::1'].includes(window.location.hostname);
    const configuredHost = new URL(configuredApiUrl).hostname;

    // A production build can leave config.json pointing at Render. When that
    // build is previewed on localhost, use the local API instead of silently
    // calling an older staging deployment that may not have the latest routes.
    this.apiBaseUrl = localHost && configuredHost === 'hutube.onrender.com'
      ? 'http://localhost:5080/api/v1'
      : configuredApiUrl;
    const configuredGoogleClientId = config.GOOGLE_CLIENT_ID;
    this.googleClientId = typeof configuredGoogleClientId === 'string' && configuredGoogleClientId.endsWith('.apps.googleusercontent.com')
      ? configuredGoogleClientId
      : '';
    const apiController = new AbortController();
    const apiTimeout = setTimeout(() => apiController.abort(), 8_000);
    try {
      const publicConfig = await fetch(this.apiBaseUrl + '/system/config', {
        cache: 'no-store',
        signal: apiController.signal,
      });
      if (publicConfig.ok) {
        const value = (await publicConfig.json()).googleClientId;
        if (typeof value === 'string' && value.endsWith('.apps.googleusercontent.com')) this.googleClientId = value;
      }
    } catch { /* Keep the public fallback so Google remains visible when CORS is not configured for local preview. */ }
    finally {
      clearTimeout(apiTimeout);
    }
  }
  owns(url: string): boolean {
    return !!this.apiBaseUrl && url.startsWith(this.apiBaseUrl + '/');
  }
}
