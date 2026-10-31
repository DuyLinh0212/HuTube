import { HttpBackend, HttpClient, HttpErrorResponse, HttpHeaders } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import { Observable, TimeoutError, catchError, defer, finalize, firstValueFrom, map, of, retry, shareReplay, switchMap, timer, tap, throwError, timeout } from 'rxjs';
import { ADMIN_APP, RuntimeConfig } from './runtime-config';
import { ReadCacheStore } from './read-cache.interceptor';
import { I18nService } from './i18n.service';

export interface User { userId: string; username: string; email: string; displayName: string; emailVerified: boolean; isAdmin: boolean; role?: string; permissions?: string[]; }
export interface LoginResponse { accessToken: string; expiresAt: string; user: User; }
export interface Session { sessionId: string; deviceName: string; platform: string; issuedAt: string; lastActiveAt: string; expiresAt: string; isCurrent: boolean; ipAddress?: string | null; deviceId?: string | null; countryCode?: string | null; region?: string | null; city?: string | null; latitude?: number | null; longitude?: number | null; }
export interface LoginHistoryItem { loginHistoryId: string; deviceId: string; deviceName: string; platform: string; ipAddress?: string | null; countryCode?: string | null; region?: string | null; city?: string | null; latitude?: number | null; longitude?: number | null; loginAt: string; }
export interface LoginHistoryPage { items: LoginHistoryItem[]; page: number; pageSize: number; total: number; }
export interface Message { message: string; }

export function isSessionRejected(error: unknown): boolean {
  return error instanceof HttpErrorResponse && (error.status === 401 || error.status === 403);
}

function stableDeviceId(): string {
  if (typeof document === 'undefined') return '';
  const key = `hutube_device_id_${ADMIN_APP ? 'admin' : 'user'}`;
  const existing = document.cookie.split('; ').find(item => item.startsWith(`${key}=`))?.slice(key.length + 1);
  if (existing) return decodeURIComponent(existing);
  const generated = typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  try { document.cookie = `${key}=${encodeURIComponent(generated)}; Max-Age=31536000; Path=/; SameSite=Lax`; } catch { /* non-browser host */ }
  return generated;
}

function browserDeviceName(i18n: I18nService): string {
  const mobile = typeof navigator !== 'undefined' && /android|iphone|ipad|ipod|mobile/i.test(navigator.userAgent);
  return `Dalitu Admin · ${i18n.t(mobile ? 'auth.deviceMobile' : 'auth.deviceDesktop')}`;
}

export interface ClientGeoPayload {
  latitude?: number;
  longitude?: number;
  city?: string;
  region?: string;
  countryCode?: string;
}

function formatDetailedAddress(data: Record<string, unknown>): ClientGeoPayload {
  const localityInfo = (data['localityInfo'] as Record<string, unknown> | undefined) || {};
  const admin = (localityInfo['administrative'] as Array<Record<string, unknown>> | undefined) || [];
  const informative = (localityInfo['informative'] as Array<Record<string, unknown>> | undefined) || [];

  const districtObj = informative.find(item =>
    /^(quận|huyện|thị xã|thành phố)\s/i.test(String(item['name'] || '')) ||
    /quận|huyện/i.test(String(item['description'] || ''))
  ) || admin.find(item =>
    /^(quận|huyện|thị xã)\s/i.test(String(item['name'] || ''))
  );

  const rawLocality = typeof data['locality'] === 'string' ? data['locality'].trim() : '';
  const districtName = districtObj?.['name']
    ? String(districtObj['name']).trim()
    : (/^(quận|huyện|thị xã|tp\.)/i.test(rawLocality) ? rawLocality : '');

  const wardObj = admin.find(item =>
    /phường|xã|thị trấn/i.test(String(item['description'] || '')) ||
    /^(phường|xã|thị trấn)\s/i.test(String(item['name'] || ''))
  );
  const rawWard = wardObj?.['name'] ? String(wardObj['name']).trim() : '';
  const candidateWard = rawWard || (!districtName || !districtName.includes(rawLocality) ? rawLocality : '');
  const wardName = candidateWard
    ? (/^(phường|xã|thị trấn)\s/i.test(candidateWard) ? candidateWard : `Phường ${candidateWard}`)
    : '';

  const rawProvince = typeof data['principalSubdivision'] === 'string' && data['principalSubdivision'].trim()
    ? data['principalSubdivision'].trim()
    : (typeof data['city'] === 'string' ? data['city'].trim() : '');

  const localDetails = [wardName, districtName]
    .filter(Boolean)
    .filter((val, idx, arr) => arr.indexOf(val) === idx);

  const city = localDetails.length > 0 ? localDetails.join(', ') : (rawLocality || (typeof data['city'] === 'string' ? data['city'] : ''));

  return {
    latitude: typeof data['latitude'] === 'number' ? data['latitude'] : undefined,
    longitude: typeof data['longitude'] === 'number' ? data['longitude'] : undefined,
    city: city ? city.slice(0, 120) : undefined,
    region: rawProvince ? rawProvince.slice(0, 120) : undefined,
    countryCode: typeof data['countryCode'] === 'string' ? data['countryCode'].slice(0, 8) : undefined
  };
}

export async function fetchIpLocation(): Promise<ClientGeoPayload> {
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 2000);
    const res = await fetch('https://api.bigdatacloud.net/data/reverse-geocode-client?localityLanguage=vi', {
      signal: controller.signal
    });
    clearTimeout(timer);
    if (res.ok) {
      const data = await res.json();
      return formatDetailedAddress(data);
    }
  } catch {
    // ignore
  }
  return {};
}

export async function captureBrowserLocation(): Promise<ClientGeoPayload> {
  if (typeof navigator === 'undefined') {
    return {};
  }
  if (!navigator.geolocation) {
    return fetchIpLocation();
  }
  return new Promise<ClientGeoPayload>((resolve) => {
    let resolved = false;
    const done = (val: ClientGeoPayload) => {
      if (!resolved) {
        resolved = true;
        resolve(val);
      }
    };
    const timer = setTimeout(async () => {
      done(await fetchIpLocation());
    }, 2000);

    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        clearTimeout(timer);
        const { latitude, longitude } = pos.coords;
        try {
          const controller = new AbortController();
          const geoTimer = setTimeout(() => controller.abort(), 1500);
          const res = await fetch(
            `https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${latitude}&longitude=${longitude}&localityLanguage=vi`,
            { signal: controller.signal }
          );
          clearTimeout(geoTimer);
          if (res.ok) {
            const data = await res.json();
            const formatted = formatDetailedAddress(data);
            done({ ...formatted, latitude, longitude });
            return;
          }
        } catch {
          // fallback below
        }
        const ipLoc = await fetchIpLocation();
        done({ ...ipLoc, latitude, longitude });
      },
      async () => {
        clearTimeout(timer);
        done(await fetchIpLocation());
      },
      { timeout: 1800, maximumAge: 300_000, enableHighAccuracy: false }
    );
  });
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private raw = new HttpClient(inject(HttpBackend));
  private http = inject(HttpClient);
  private config = inject(RuntimeConfig);
  private readonly readCache = inject(ReadCacheStore);
  private readonly i18n = inject(I18nService);
  readonly user = signal<User | null>(null);
  readonly accessToken = signal<string | null>(null);
  private refreshFlight?: Observable<LoginResponse>;
  private restoreFlight?: Observable<boolean>;
  private generation = 0;
  private restored = false;
  private accessTokenExpiresAt = 0;
  get sessionVersion(): number { return this.generation; }
  private get headers(): HttpHeaders {
    let headers = new HttpHeaders({ 'X-HuTube-Client': 'web' });
    if (ADMIN_APP) headers = headers.set('X-HuTube-App', 'admin');
    return headers;
  }
  private isTransientNetworkError(error: unknown): boolean {
    return error instanceof TimeoutError || (error instanceof HttpErrorResponse && (
      error.status === 0 || error.status === 408 || error.status >= 500
    ));
  }
  private post<T>(path: string, body: unknown, timeoutMs = 15_000): Observable<T> {
    return this.raw.post<T>(this.config.apiBaseUrl + path, body, { withCredentials: true, headers: this.headers }).pipe(
      timeout({ first: timeoutMs }),
    );
  }
  clear(): void { this.readCache.clear(); this.generation++; this.restored = true; this.user.set(null); this.accessToken.set(null); this.accessTokenExpiresAt = 0; }
  private accept(response: LoginResponse): void {
    this.accessTokenExpiresAt = Date.parse(response.expiresAt) || 0;
    this.accessToken.set(response.accessToken);
    const currentUser = this.user();
    const refreshedUser = response.user;
    const currentAdminProfile = ADMIN_APP && currentUser?.isAdmin && refreshedUser.isAdmin
      && currentUser.userId === refreshedUser.userId ? currentUser : null;
    this.user.set(currentAdminProfile ? {
      ...currentAdminProfile,
      ...refreshedUser,
      role: refreshedUser.role ?? currentAdminProfile.role,
      permissions: refreshedUser.permissions ?? currentAdminProfile.permissions,
    } : refreshedUser);
    this.restored = true;
  }
  ensureFreshAccessToken(): Observable<string> {
    const token = this.accessToken();
    return token && this.accessTokenExpiresAt > Date.now() + 120_000
      ? of(token) : this.refresh().pipe(map(response => response.accessToken));
  }
  login(email: string, password: string, location?: ClientGeoPayload): Observable<User> {
    const generation = ++this.generation;
    const body: Record<string, unknown> = {
      email,
      password,
      platform: ADMIN_APP ? 'admin' : 'web',
      deviceName: browserDeviceName(this.i18n),
      deviceId: stableDeviceId(),
    };
    if (location?.latitude != null) body['latitude'] = location.latitude;
    if (location?.longitude != null) body['longitude'] = location.longitude;
    if (location?.city) body['city'] = location.city;
    if (location?.region) body['region'] = location.region;
    if (location?.countryCode) body['countryCode'] = location.countryCode;

    return this.post<LoginResponse>('/auth/login', body).pipe(
      tap(response => { if (generation !== this.generation) throw new Error(this.i18n.t('auth.error.loginCancelled')); this.accept(response); }),
      switchMap(() => this.me()),
      catchError(error => { if (generation === this.generation) this.clear(); return throwError(() => error); })
    );
  }
  refresh(): Observable<LoginResponse> {
    if (!this.refreshFlight) {
      const generation = this.generation;
      // Serialize refresh cookie rotation across same-origin tabs as well as within this tab.
      const request = () => firstValueFrom(this.post<LoginResponse>('/auth/refresh', {
        deviceName: browserDeviceName(this.i18n),
      }));
      this.refreshFlight = defer(async () => typeof navigator !== 'undefined' && navigator.locks
        ? await navigator.locks.request('hutube-refresh-' + (ADMIN_APP ? 'admin' : 'web'), request)
        : await request()).pipe(
        tap(response => { if (generation !== this.generation) throw new Error(this.i18n.t('auth.error.sessionEnded')); this.accept(response); }),
        catchError(error => {
          if (generation === this.generation && isSessionRejected(error)) this.clear();
          return throwError(() => error);
        }),
        finalize(() => { this.refreshFlight = undefined; }),
        shareReplay({ bufferSize: 1, refCount: false })
      );
    }
    return this.refreshFlight;
  }
  restore(): Observable<boolean> {
    const generation = this.generation;
    const denied = (error: unknown) => {
      if (generation !== this.generation) return of(false);
      if (!isSessionRejected(error)) return throwError(() => error);
      this.clear();
      return of(false);
    };
    if (this.restored && !this.accessToken()) return of(false);
    if (!this.restoreFlight) {
      const restoreAttempt = () => {
        if (generation !== this.generation || (this.restored && !this.accessToken())) return of(false);
        return this.accessToken()
          ? this.me().pipe(map(() => true))
          : this.refresh().pipe(switchMap(() => this.me()), map(() => true));
      };
      this.restoreFlight = defer(restoreAttempt).pipe(
        retry({ count: 2, delay: error => this.isTransientNetworkError(error) && generation === this.generation
          ? timer(5_000)
          : throwError(() => error) }),
        timeout({ first: 30_000 }),
        catchError(denied),
        finalize(() => { this.restoreFlight = undefined; }),
        shareReplay({ bufferSize: 1, refCount: false })
      );
    }
    return this.restoreFlight;
  }
  me(): Observable<User> {
    const generation = this.generation;
    return this.http.get<User>(this.config.apiBaseUrl + (ADMIN_APP ? '/admin/me' : '/auth/me')).pipe(tap(user => {
      if (generation !== this.generation) throw new Error(this.i18n.t('auth.error.sessionChanged'));
      this.user.set(user);
    }));
  }
  register(body: unknown) { return this.post<Message>('/auth/register', body); }
  verify(token: string) { return this.post<Message>('/auth/verify-email', { token }); }
  resend(email: string) { return this.post<Message>('/auth/resend-verification', { email }); }
  forgot(email: string) { return this.post<Message>('/auth/forgot-password', { email }); }
  reset(email: string, code: string, password: string) { return this.post<Message>('/auth/reset-password', { email, code, password }).pipe(tap(() => this.clear())); }
  sessions() { return this.http.get<{ items: Session[] }>(this.config.apiBaseUrl + '/auth/sessions'); }
  loginHistory(page = 1, pageSize = 20) {
    return this.http.get<LoginHistoryPage>(this.config.apiBaseUrl + '/auth/login-history', { params: { page, pageSize } });
  }
  logoutOthers() { return this.http.post<Message>(this.config.apiBaseUrl + '/auth/logout-others', {}); }
  revoke(id: string) { return this.http.delete<Message>(this.config.apiBaseUrl + '/auth/sessions/' + encodeURIComponent(id)); }
  logout() { this.clear(); return this.post<Message>('/auth/logout', {}); }
  info() { return this.raw.get(this.config.apiBaseUrl + '/system/info'); }
  hasPermission(code: string): boolean {
    const u = this.user();
    if (!u || !u.isAdmin) return false;
    if (u.role === 'super_admin') return true;
    return u.permissions?.includes(code) ?? false;
  }
}

export function safeReturnUrl(value: string | null): string {
  if (!value || !value.startsWith('/') || value.startsWith('//') || /[\\\r\n]/.test(value) || /^\/(login|register|verify-email|forgot-password|reset-password)([/?#]|$)/.test(value)) return '/account';
  // Decode before checking to reject encoded protocol-relative destinations.
  try { const decoded = decodeURIComponent(value); if (decoded.startsWith('//') || /[\\\r\n]/.test(decoded)) return '/account'; } catch { return '/account'; }
  return value;
}

export function errorMessage(error: unknown, i18n: I18nService): string {
  if (error instanceof TimeoutError) return i18n.t('auth.error.serverUnavailable');
  if (!(error instanceof HttpErrorResponse)) return i18n.t('auth.error.generic');
  const messageKeys: Record<string, string> = {
    INVALID_CREDENTIALS: 'auth.error.invalidCredentials',
    EMAIL_NOT_VERIFIED: 'auth.error.emailNotVerified',
    EMAIL_UNVERIFIED: 'auth.error.emailNotVerified',
    ACCOUNT_SUSPENDED: 'auth.error.accountSuspended',
    ACCOUNT_BANNED: 'auth.error.accountBanned',
    ADMIN_ACCESS_DENIED: 'auth.error.adminAccessDenied',
    ADMIN_DISABLED: 'auth.error.adminDisabled',
    EMAIL_EXISTS: 'auth.error.emailExists',
    USERNAME_EXISTS: 'auth.error.usernameExists',
    INVALID_TOKEN: 'auth.error.invalidToken',
    TOKEN_EXPIRED: 'auth.error.tokenExpired',
    INVALID_STATISTICS_RANGE: 'users.statistics.invalidRange',
    STATISTICS_RANGE_TOO_LARGE: 'users.statistics.rangeTooLarge',
  };
  if (error.status === 0) return i18n.t('auth.error.serverUnavailable');
  if (error.status === 429) return i18n.t('auth.error.rateLimited');
  if (messageKeys[error.error?.code]) return i18n.t(messageKeys[error.error.code]);
  if (typeof error.error?.detail === 'string') return `${error.error.detail} (${error.status})`;
  if (error.status === 403) return i18n.t('auth.error.forbidden');
  return i18n.format('auth.error.requestFailed', { status: error.status });
}
