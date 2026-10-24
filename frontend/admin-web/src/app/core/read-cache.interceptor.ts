import { HttpEvent, HttpInterceptorFn, HttpResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, finalize, map, of, shareReplay, tap } from 'rxjs';
import { RuntimeConfig } from './runtime-config';

@Injectable({ providedIn: 'root' })
export class ReadCacheStore {
  readonly values = new Map<string, { expires: number; response: HttpResponse<unknown> }>();
  readonly flights = new Map<string, Observable<HttpEvent<unknown>>>();
  generation = 0;
  constructor() {
    // A second tab may edit the same account. Never persist private response data.
    if (typeof window !== 'undefined') {
      window.addEventListener('focus', () => this.clear());
      window.addEventListener('dalitu:data-changed', () => this.clear());
      window.addEventListener('storage', () => this.clear());
    }
  }
  clear() { this.generation++; this.values.clear(); this.flights.clear(); }
  invalidate(path: string) {
    if (path.endsWith('/player-preferences')) return;
    if (path.endsWith('/progress') || path.includes('/notifications/')) {
      this.generation++;
      this.flights.clear();
      for (const key of this.values.keys()) {
        if (path.endsWith('/progress') ? /\/(library|videos)\//.test(key) : key.includes('/notifications')) this.values.delete(key);
      }
      return;
    }
    this.clear();
  }
}

function identity(authorization: string | null): string {
  if (!authorization) return 'guest';
  try {
    const payload = authorization.replace(/^Bearer /i, '').split('.')[1];
    const claims = JSON.parse(atob(payload.replace(/-/g, '+').replace(/_/g, '/')));
    return `${claims.sub}:${claims.sid}`;
  } catch { return 'uncacheable'; }
}

function ttl(path: string): number {
  if (/\/(playback|download-options|evidence|export|check-handle)(\/|$)/.test(path)
    || /\/(payments\/|jobs\/|upload|feedback-survey|session-player)/.test(path)
    || /\/auth\/(?!me$)/.test(path) || path.endsWith('/auth/sessions')
    || path.endsWith('/operations/system') || path.includes('audit-logs')
    || path.includes('recommendation-context') || path.endsWith('/my-plan')) return 0;
  if (/\/(auth|admin)\/me$/.test(path)) return 10_000; // UI snapshot; every API still authorizes on the server.
  if (/\/admin\/(moderation|reports|appeals|strikes)(\/|$)/.test(path) || path.endsWith('/payments')) return 5_000;
  if (/\/(categories|violation-types|roles|permissions|topics|tags)$/.test(path)) return 60_000;
  if (path.endsWith('/policies')) return 30_000;
  if (/\/(feed|videos|channels|playlists|subscriptions|library|account|studio|notifications|admin|plans)(\/|$)/.test(path)) return 20_000;
  return 0;
}

function copy(response: HttpResponse<unknown>): HttpResponse<unknown> {
  return response.clone({ body: structuredClone(response.body) });
}

export const readCacheInterceptor: HttpInterceptorFn = (request, next) => {
  const config = inject(RuntimeConfig);
  if (!config.owns(request.url)) return next(request);
  const store = inject(ReadCacheStore);
  const url = new URL(request.urlWithParams, window.location.origin);
  const path = url.pathname;
  const readPost = request.method === 'POST' && path.endsWith('/feed/resolve');
  if (request.method !== 'GET' && !readPost) {
    store.invalidate(path);
    return next(request).pipe(finalize(() => store.invalidate(path)));
  }
  const duration = ttl(path);
  const scope = identity(request.headers.get('Authorization'));
  if (!duration || scope === 'uncacheable' || request.responseType !== 'json'
    || url.searchParams.has('_refresh') || request.headers.get('Cache-Control')?.includes('no-cache')) return next(request);
  url.searchParams.sort();
  const key = `${scope}|${request.method}|${url.toString()}|${request.headers.get('Accept-Language') ?? ''}|${readPost ? JSON.stringify(request.body) : ''}`;
  const entry = store.values.get(key);
  if (entry && entry.expires > Date.now()) return of(copy(entry.response));
  store.values.delete(key);
  const flight = store.flights.get(key);
  if (flight) return flight.pipe(map(event => event instanceof HttpResponse ? copy(event) : event));
  const generation = store.generation;
  const source = next(request).pipe(tap({
    next: event => {
      if (event instanceof HttpResponse && event.ok && generation === store.generation) {
        // Bound both entry count and payload size. Do not keep large exports/files.
        if (JSON.stringify(event.body)?.length > 256 * 1024) return;
        if (store.values.size >= 160) store.values.delete(store.values.keys().next().value!);
        store.values.set(key, { expires: Date.now() + duration, response: copy(event) });
      }
    },
    error: error => { if (error?.status === 401 || error?.status === 403) store.clear(); }
  }), finalize(() => { if (store.flights.get(key) === source) store.flights.delete(key); }),
    shareReplay({ bufferSize: 1, refCount: true }));
  store.flights.set(key, source);
  return source.pipe(map(event => event instanceof HttpResponse ? copy(event) : event));
};
