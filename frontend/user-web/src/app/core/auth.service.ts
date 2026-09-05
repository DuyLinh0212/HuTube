import { HttpBackend, HttpClient, HttpErrorResponse, HttpHeaders } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import { Observable, catchError, defer, finalize, firstValueFrom, map, of, shareReplay, switchMap, tap, throwError } from 'rxjs';
import { ADMIN_APP, RuntimeConfig } from './runtime-config';

export interface User { userId: string; username: string; email: string; displayName: string; emailVerified: boolean; isAdmin: boolean; }
export interface LoginResponse { accessToken: string; expiresAt: string; user: User; }
export interface Session { sessionId: string; deviceName: string; platform: string; issuedAt: string; lastActiveAt: string; expiresAt: string; isCurrent: boolean; }
export interface Message { message: string; }

@Injectable({ providedIn: 'root' })
export class AuthService {
  private raw = new HttpClient(inject(HttpBackend));
  private http = inject(HttpClient);
  private config = inject(RuntimeConfig);
  readonly user = signal<User | null>(null);
  readonly accessToken = signal<string | null>(null);
  private refreshFlight?: Observable<LoginResponse>;
  private generation = 0;
  private restored = false;
  get sessionVersion(): number { return this.generation; }
  private get headers(): HttpHeaders {
    let headers = new HttpHeaders({ 'X-HuTube-Client': 'web' });
    if (ADMIN_APP) headers = headers.set('X-HuTube-App', 'admin');
    return headers;
  }
  private post<T>(path: string, body: unknown): Observable<T> {
    return this.raw.post<T>(this.config.apiBaseUrl + path, body, { withCredentials: true, headers: this.headers });
  }
  clear(): void { this.generation++; this.restored = true; this.user.set(null); this.accessToken.set(null); }
  private accept(response: LoginResponse): void { this.accessToken.set(response.accessToken); this.user.set(response.user); this.restored = true; }
  login(email: string, password: string): Observable<User> {
    const generation = ++this.generation;
    return this.post<LoginResponse>('/auth/login', { email, password, platform: ADMIN_APP ? 'admin' : 'web', deviceName: ADMIN_APP ? 'HuTube Admin Web' : 'HuTube Web' }).pipe(
      tap(response => { if (generation !== this.generation) throw new Error('Yêu cầu đăng nhập đã bị hủy.'); this.accept(response); }),
      switchMap(() => this.me()),
      catchError(error => { if (generation === this.generation) this.clear(); return throwError(() => error); })
    );
  }
  google(credential: string): Observable<User> {
    const generation = ++this.generation;
    return this.post<LoginResponse>('/auth/google', { credential, platform: 'web', deviceName: 'HuTube Web / Google' }).pipe(
      tap(response => { if (generation !== this.generation) throw new Error('Yêu cầu đăng nhập đã bị hủy.'); this.accept(response); }),
      switchMap(() => this.me()),
      catchError(error => { if (generation === this.generation) this.clear(); return throwError(() => error); })
    );
  }
  refresh(): Observable<LoginResponse> {
    if (!this.refreshFlight) {
      const generation = this.generation;
      // Serialize refresh cookie rotation across same-origin tabs as well as within this tab.
      const request = () => firstValueFrom(this.post<LoginResponse>('/auth/refresh', {}));
      this.refreshFlight = defer(async () => typeof navigator !== 'undefined' && navigator.locks
        ? await navigator.locks.request('hutube-refresh-' + (ADMIN_APP ? 'admin' : 'web'), request)
        : await request()).pipe(
        tap(response => { if (generation !== this.generation) throw new Error('Phiên đã kết thúc.'); this.accept(response); }),
        catchError(error => { if (generation === this.generation) this.clear(); return throwError(() => error); }),
        finalize(() => { this.refreshFlight = undefined; }),
        shareReplay({ bufferSize: 1, refCount: false })
      );
    }
    return this.refreshFlight;
  }
  restore(): Observable<boolean> {
    const generation = this.generation;
    const denied = () => { if (generation === this.generation) this.clear(); return of(false); };
    if (this.accessToken()) return this.me().pipe(map(() => true), catchError(denied));
    if (this.restored) return of(false);
    return this.refresh().pipe(switchMap(() => this.me()), map(() => true), catchError(denied));
  }
  me(): Observable<User> {
    const generation = this.generation;
    return this.http.get<User>(this.config.apiBaseUrl + (ADMIN_APP ? '/admin/me' : '/auth/me')).pipe(tap(user => {
      if (generation !== this.generation) throw new Error('Phiên đã thay đổi.');
      this.user.set(user);
    }));
  }
  register(body: unknown) { return this.post<Message>('/auth/register', body); }
  verify(token: string) { return this.post<Message>('/auth/verify-email', { token }); }
  resend(email: string) { return this.post<Message>('/auth/resend-verification', { email }); }
  forgot(email: string) { return this.post<Message>('/auth/forgot-password', { email }); }
  reset(token: string, password: string) { return this.post<Message>('/auth/reset-password', { token, password }).pipe(tap(() => this.clear())); }
  sessions() { return this.http.get<{ items: Session[] }>(this.config.apiBaseUrl + '/auth/sessions'); }
  logoutOthers() { return this.http.post<Message>(this.config.apiBaseUrl + '/auth/logout-others', {}); }
  revoke(id: string) { return this.http.delete<Message>(this.config.apiBaseUrl + '/auth/sessions/' + encodeURIComponent(id)); }
  logout() { this.clear(); return this.post<Message>('/auth/logout', {}); }
  info() { return this.raw.get(this.config.apiBaseUrl + '/system/info'); }
}

export function safeReturnUrl(value: string | null): string {
  if (!value || !value.startsWith('/') || value.startsWith('//') || /[\\\r\n]/.test(value) || /^\/(login|register|verify-email|forgot-password|reset-password)([/?#]|$)/.test(value)) return '/account';
  // Decode before checking to reject encoded protocol-relative destinations.
  try { const decoded = decodeURIComponent(value); if (decoded.startsWith('//') || /[\\\r\n]/.test(decoded)) return '/account'; } catch { return '/account'; }
  return value;
}

export function errorMessage(error: unknown): string {
  if (!(error instanceof HttpErrorResponse)) return 'Không thể hoàn tất yêu cầu. Vui lòng thử lại.';
  const messages: Record<string, string> = {
    INVALID_CREDENTIALS: 'Email hoặc mật khẩu chưa đúng.',
    EMAIL_NOT_VERIFIED: 'Vui lòng xác minh email trước khi đăng nhập.',
    EMAIL_UNVERIFIED: 'Vui lòng xác minh email trước khi đăng nhập.',
    ACCOUNT_SUSPENDED: 'Tài khoản đang bị tạm khóa.', ACCOUNT_BANNED: 'Tài khoản đã bị khóa.',
    ADMIN_ACCESS_DENIED: 'Tài khoản không có quyền quản trị hoặc quyền đã bị vô hiệu hóa.',
    ADMIN_DISABLED: 'Quyền quản trị của tài khoản đã bị vô hiệu hóa.',
    EMAIL_EXISTS: 'Email này đã được sử dụng.', USERNAME_EXISTS: 'Tên người dùng này đã được sử dụng.',
    INVALID_TOKEN: 'Liên kết không hợp lệ hoặc đã hết hạn. Hãy yêu cầu liên kết mới.',
    TOKEN_EXPIRED: 'Liên kết đã hết hạn. Hãy yêu cầu liên kết mới.',
    GOOGLE_LOGIN_NOT_CONFIGURED: 'Đăng nhập Google chưa được cấu hình.',
    INVALID_GOOGLE_TOKEN: 'Không thể xác thực tài khoản Google. Vui lòng thử lại.',
    GOOGLE_ACCOUNT_CONFLICT: 'Email này đã được liên kết với một tài khoản Google khác.'
  };
  if (error.status === 0) return 'Chưa kết nối được máy chủ. Kiểm tra kết nối và thử lại.';
  if (error.status === 429) return 'Bạn đã thử quá nhiều lần. Vui lòng đợi một lát rồi thử lại.';
  if (messages[error.error?.code]) return messages[error.error.code];
  if (error.status === 403) return 'Tài khoản không có quyền truy cập hoặc đã bị vô hiệu hóa.';
  return typeof error.error?.detail === 'string' ? error.error.detail : 'Không thể hoàn tất yêu cầu. Vui lòng thử lại.';
}
