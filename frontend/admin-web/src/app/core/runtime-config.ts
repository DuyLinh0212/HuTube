import { Injectable } from '@angular/core';

export const ADMIN_APP = true;

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
  userWebBaseUrl = '';
  async load(): Promise<void> {
    const response = await fetch('config.json', { cache: 'no-store' });
    if (!response.ok) throw new Error('Không tải được cấu hình kết nối.');
    const config = await response.json();
    this.apiBaseUrl = validateApiUrl(config.API_BASE_URL);
    const local = ['localhost', '127.0.0.1'].includes(location.hostname);
    this.userWebBaseUrl = config.USER_WEB_BASE_URL ? validateApiUrl(config.USER_WEB_BASE_URL) : local ? 'http://localhost:4200' : '';
    if (this.userWebBaseUrl && new URL(this.userWebBaseUrl).pathname !== '/') throw new Error('USER_WEB_BASE_URL phải là origin.');
  }
  owns(url: string): boolean {
    return !!this.apiBaseUrl && url.startsWith(this.apiBaseUrl + '/');
  }
}
