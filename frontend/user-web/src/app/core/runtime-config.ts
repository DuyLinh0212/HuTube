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
    const response = await fetch('config.json', { cache: 'no-store' });
    if (!response.ok) throw new Error('Không tải được cấu hình kết nối.');
    const config = await response.json();
    this.apiBaseUrl = validateApiUrl(config.API_BASE_URL);
    const configuredGoogleClientId = config.GOOGLE_CLIENT_ID;
    this.googleClientId = typeof configuredGoogleClientId === 'string' && configuredGoogleClientId.endsWith('.apps.googleusercontent.com')
      ? configuredGoogleClientId
      : '';
    try {
      const publicConfig = await fetch(this.apiBaseUrl + '/system/config', { cache: 'no-store' });
      if (publicConfig.ok) {
        const value = (await publicConfig.json()).googleClientId;
        if (typeof value === 'string' && value.endsWith('.apps.googleusercontent.com')) this.googleClientId = value;
      }
    } catch { /* Keep the public fallback so Google remains visible when CORS is not configured for local preview. */ }
  }
  owns(url: string): boolean {
    return !!this.apiBaseUrl && url.startsWith(this.apiBaseUrl + '/');
  }
}
