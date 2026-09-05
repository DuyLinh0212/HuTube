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
  async load(): Promise<void> {
    const response = await fetch('config.json', { cache: 'no-store' });
    if (!response.ok) throw new Error('Không tải được cấu hình kết nối.');
    const config = await response.json();
    this.apiBaseUrl = validateApiUrl(config.API_BASE_URL);
  }
  owns(url: string): boolean {
    return !!this.apiBaseUrl && url.startsWith(this.apiBaseUrl + '/');
  }
}
