import { TestBed, fakeAsync, flushMicrotasks, tick } from '@angular/core/testing';
import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter, Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { AuthService, LoginResponse, safeReturnUrl } from './auth.service';
import { authInterceptor } from './auth.interceptor';
import { ADMIN_APP, RuntimeConfig, validateApiUrl } from './runtime-config';

describe('Authentication boundary', () => {
  const base = 'http://localhost:5080/api/v1';
  const user = { userId: '1', username: 'linh', email: 'linh@example.test', displayName: 'Linh', emailVerified: true, isAdmin: ADMIN_APP };
  const response: LoginResponse = { accessToken: 'token-one', expiresAt: '2030-01-01T00:00:00Z', user };
  let auth: AuthService; let http: HttpClient; let controller: HttpTestingController;
  beforeEach(() => {
    TestBed.configureTestingModule({ providers: [provideHttpClient(withInterceptors([authInterceptor])), provideHttpClientTesting(), provideRouter([])] });
    TestBed.inject(RuntimeConfig).apiBaseUrl = base;
    auth = TestBed.inject(AuthService); http = TestBed.inject(HttpClient); controller = TestBed.inject(HttpTestingController);
    // Deterministic in-tab tests; production additionally uses the browser lock manager.
    spyOn(navigator.locks, 'request').and.callFake(((_name: string, callback: () => Promise<unknown>) => callback()) as typeof navigator.locks.request);
  });
  afterEach(() => controller.verify());
  function login() {
    const promise = firstValueFrom(auth.login(user.email, 'StrongPass123'));
    const request = controller.expectOne(base + '/auth/login');
    expect(request.request.withCredentials).toBeTrue();
    expect(request.request.headers.get('X-HuTube-Client')).toBe('web');
    expect(request.request.body.platform).toBe(ADMIN_APP ? 'admin' : 'web');
    expect(request.request.headers.get('X-HuTube-App')).toBe(ADMIN_APP ? 'admin' : null);
    request.flush(response);
    const me = controller.expectOne(base + (ADMIN_APP ? '/admin/me' : '/auth/me'));
    expect(me.request.headers.get('Authorization')).toBe('Bearer token-one'); me.flush(user);
    return promise;
  }
  it('logs in and verifies the account through protected me, keeping tokens out of web storage', async () => {
    const local = spyOn(localStorage, 'setItem'); const session = spyOn(sessionStorage, 'setItem');
    expect(await login()).toEqual(user); expect(auth.user()).toEqual(user); expect(local).not.toHaveBeenCalled(); expect(session).not.toHaveBeenCalled();
  });
  it('never leaks bearer headers or cookies to an external URL or a prefix lookalike', async () => {
    await login();
    for (const url of ['https://example.test/api', base + '-other/auth/me']) {
      http.get(url).subscribe(); const request = controller.expectOne(url);
      expect(request.request.headers.has('Authorization')).toBeFalse(); expect(request.request.withCredentials).toBeFalse(); request.flush({});
    }
  });
  it('rejects denied account/admin access even after a successful credential response', async () => {
    const promise = firstValueFrom(auth.login(user.email, 'StrongPass123'));
    controller.expectOne(base + '/auth/login').flush(response);
    controller.expectOne(base + (ADMIN_APP ? '/admin/me' : '/auth/me')).flush({ code: 'ADMIN_ACCESS_DENIED' }, {status:403,statusText:'Forbidden'});
    await expectAsync(promise).toBeRejected(); expect(auth.user()).toBeNull(); expect(auth.accessToken()).toBeNull();
  });
  it('restores a session from the HttpOnly cookie and validates current account status', async () => {
    const promise = firstValueFrom(auth.restore());
    const request = controller.expectOne(base + '/auth/refresh'); expect(request.request.body.deviceName).toEqual(jasmine.any(String)); expect(request.request.withCredentials).toBeTrue(); request.flush(response);
    await Promise.resolve(); await Promise.resolve();
    controller.expectOne(base + (ADMIN_APP ? '/admin/me' : '/auth/me')).flush(user);
    expect(await promise).toBeTrue();
  });
  it('deduplicates concurrent refresh and does not repeat a failed restore', async () => {
    const first = firstValueFrom(auth.refresh()); const second = firstValueFrom(auth.refresh());
    controller.expectOne(base + '/auth/refresh').flush(response);
    expect(await first).toEqual(response); expect(await second).toEqual(response);
    auth.clear(); expect(await firstValueFrom(auth.restore())).toBeFalse(); controller.expectNone(base + '/auth/refresh');
  });
  it('cannot resurrect a session when logout races an in-flight refresh', async () => {
    const refreshing = firstValueFrom(auth.refresh()); const request = controller.expectOne(base + '/auth/refresh');
    const loggingOut = firstValueFrom(auth.logout()); controller.expectOne(base + '/auth/logout').flush({message:'ok'});
    request.flush(response); await loggingOut; await expectAsync(refreshing).toBeRejected(); expect(auth.accessToken()).toBeNull();
  });
  it('does not restore stale user details when me finishes after logout', async () => {
    await login(); const pending = firstValueFrom(auth.me());
    const me = controller.expectOne(base + (ADMIN_APP ? '/admin/me' : '/auth/me'));
    const logout = firstValueFrom(auth.logout()); controller.expectOne(base + '/auth/logout').flush({message:'ok'});
    me.flush(user); await logout; await expectAsync(pending).toBeRejected(); expect(auth.user()).toBeNull(); expect(auth.accessToken()).toBeNull();
  });
  it('does not clear a newer session when an older login fails late', async () => {
    const old = firstValueFrom(auth.login(user.email,'WrongPassword123'));
    const request = controller.expectOne(base + '/auth/login');
    await login(); request.flush({code:'INVALID_CREDENTIALS'},{status:401,statusText:'Unauthorized'});
    await expectAsync(old).toBeRejected(); expect(auth.user()).toEqual(user); expect(auth.accessToken()).toBe('token-one');
  });
  it('does not clear a newer login when an old restore account check completes late', async () => {
    await login(); const old = firstValueFrom(auth.restore());
    const me = controller.expectOne(base + (ADMIN_APP ? '/admin/me' : '/auth/me'));
    await login(); me.flush(user);
    expect(await old).toBeFalse(); expect(auth.user()).toEqual(user); expect(auth.accessToken()).toBe('token-one');
  });
  it('retries a protected request once after a 401 with the rotated access token', async () => {
    await login(); const result = firstValueFrom(auth.sessions());
    controller.expectOne(base + '/auth/sessions').flush({}, {status:401,statusText:'Unauthorized'});
    controller.expectOne(base + '/auth/refresh').flush({...response,accessToken:'token-two'});
    await Promise.resolve(); await Promise.resolve();
    const retry = controller.expectOne(base + '/auth/sessions'); expect(retry.request.headers.get('Authorization')).toBe('Bearer token-two'); retry.flush({items:[]});
    expect(await result).toEqual({items:[]});
  });
  it('ends expired sessions and retains the intended safe destination', async () => {
    await login(); const router = TestBed.inject(Router); const navigation = spyOn(router, 'navigate').and.resolveTo(true);
    const result = firstValueFrom(auth.sessions());
    controller.expectOne(base + '/auth/sessions').flush({}, {status:401,statusText:'Unauthorized'});
    controller.expectOne(base + '/auth/refresh').flush({}, {status:401,statusText:'Unauthorized'});
    await expectAsync(result).toBeRejected(); expect(auth.accessToken()).toBeNull(); expect(navigation).toHaveBeenCalledWith(['/login'], {queryParams:{reason:'expired',returnUrl:'/'}});
  });
  for (const status of [0, 408, 429, 500, 502, 503, 504]) {
    it(`keeps the admin session and permits recovery after refresh fails with ${status}`, async () => {
      await login();
      const navigation = spyOn(TestBed.inject(Router), 'navigate').and.resolveTo(true);
      const result = firstValueFrom(auth.sessions());
      controller.expectOne(base + '/auth/sessions').flush({ code: 'SESSION_EXPIRED' }, { status: 401, statusText: 'Unauthorized' });
      const refresh = controller.expectOne(base + '/auth/refresh');
      if (status === 0) refresh.error(new ProgressEvent('error'));
      else refresh.flush({}, { status, statusText: 'Temporary failure' });
      await expectAsync(result).toBeRejected();
      expect(auth.accessToken()).toBe('token-one');
      expect(auth.user()).toEqual(user);
      expect(navigation).not.toHaveBeenCalled();

      const recovered = firstValueFrom(auth.sessions());
      controller.expectOne(base + '/auth/sessions').flush({}, { status: 401, statusText: 'Unauthorized' });
      controller.expectOne(base + '/auth/refresh').flush({ ...response, accessToken: 'token-two' });
      await Promise.resolve(); await Promise.resolve();
      controller.expectOne(base + '/auth/sessions').flush({ items: [] });
      expect(await recovered).toEqual({ items: [] });
      expect(auth.accessToken()).toBe('token-two');
    });
  }
  it('refreshes a token nearing expiry before sending protected admin requests', async () => {
    await login();
    spyOn(Date, 'now').and.returnValue(Date.parse(response.expiresAt) - 60_000);
    const first = firstValueFrom(auth.sessions());
    const second = firstValueFrom(http.get(base + '/admin/recommendations/models'));
    controller.expectNone(base + '/auth/sessions');
    controller.expectNone(base + '/admin/recommendations/models');
    controller.expectOne(base + '/auth/refresh').flush({ ...response, accessToken: 'token-two' });
    await Promise.resolve(); await Promise.resolve();
    const sessions = controller.expectOne(base + '/auth/sessions');
    const models = controller.expectOne(base + '/admin/recommendations/models');
    expect(sessions.request.headers.get('Authorization')).toBe('Bearer token-two');
    expect(models.request.headers.get('Authorization')).toBe('Bearer token-two');
    sessions.flush({ items: [] }); models.flush({ items: [] });
    await first; await second;
  });
  it('preserves a session when proactive refresh temporarily fails', async () => {
    await login();
    spyOn(Date, 'now').and.returnValue(Date.parse(response.expiresAt) - 60_000);
    const navigation = spyOn(TestBed.inject(Router), 'navigate').and.resolveTo(true);
    const result = firstValueFrom(auth.sessions());
    controller.expectOne(base + '/auth/refresh').flush({}, { status: 503, statusText: 'Unavailable' });
    await expectAsync(result).toBeRejected();
    controller.expectNone(base + '/auth/sessions');
    expect(auth.accessToken()).toBe('token-one');
    expect(navigation).not.toHaveBeenCalled();
  });
  it('redirects when proactive refresh confirms that the session has ended', async () => {
    await login();
    spyOn(Date, 'now').and.returnValue(Date.parse(response.expiresAt) - 60_000);
    const navigation = spyOn(TestBed.inject(Router), 'navigate').and.resolveTo(true);
    const result = firstValueFrom(auth.sessions());
    controller.expectOne(base + '/auth/refresh').flush({ code: 'INVALID_REFRESH_TOKEN' }, { status: 401, statusText: 'Unauthorized' });
    await expectAsync(result).toBeRejected();
    controller.expectNone(base + '/auth/sessions');
    expect(auth.accessToken()).toBeNull();
    expect(navigation).toHaveBeenCalledWith(['/login'], { queryParams: { reason: 'expired', returnUrl: '/' } });
  });
  it('stops a refresh when the API does not respond within 15 seconds', fakeAsync(() => {
    let failed = false;
    auth.refresh().subscribe({ error: () => { failed = true; } });
    const refresh = controller.expectOne(base + '/auth/refresh');
    tick(16_000);
    flushMicrotasks();
    expect(refresh.cancelled).toBeTrue();
    expect(failed).toBeTrue();
  }));
  it('stops restoration after three failures instead of retrying indefinitely', fakeAsync(() => {
    let failed = false;
    auth.restore().subscribe({ error: () => { failed = true; } });
    for (let attempt = 0; attempt < 3; attempt++) {
      controller.expectOne(base + '/auth/refresh').error(new ProgressEvent('error'));
      flushMicrotasks();
      if (attempt < 2) tick(5_000);
    }
    expect(failed).toBeTrue();
    tick(60_000);
    controller.expectNone(base + '/auth/refresh');
  }));
  it('does not automatically retry a rate-limited restoration', fakeAsync(() => {
    let failed = false;
    auth.restore().subscribe({ error: () => { failed = true; } });
    controller.expectOne(base + '/auth/refresh').flush({}, { status: 429, statusText: 'Too Many Requests' });
    flushMicrotasks();
    expect(failed).toBeTrue();
    tick(60_000);
    controller.expectNone(base + '/auth/refresh');
  }));
  it('retries session restoration after temporary API unavailability', fakeAsync(() => {
    let restored: boolean | undefined;
    auth.restore().subscribe(value => { restored = value; });
    controller.expectOne(base + '/auth/refresh').flush({}, { status: 503, statusText: 'Unavailable' });
    flushMicrotasks();
    expect(restored).toBeUndefined();
    tick(5_000);
    controller.expectOne(base + '/auth/refresh').flush(response);
    flushMicrotasks();
    controller.expectOne(base + '/admin/me').flush(user);
    expect(restored).toBeTrue();
    expect(auth.user()).toEqual(user);
  }));
  it('does not refresh or redirect for a business 403', async () => {
    await login(); const result = firstValueFrom(auth.sessions());
    controller.expectOne(base + '/auth/sessions').flush({}, {status:403,statusText:'Forbidden'});
    await expectAsync(result).toBeRejected(); controller.expectNone(base + '/auth/refresh');
  });
  it('keeps the refreshed session when a retried endpoint returns a server error', async () => {
    await login(); const result = firstValueFrom(auth.sessions());
    controller.expectOne(base + '/auth/sessions').flush({}, {status:401,statusText:'Unauthorized'});
    controller.expectOne(base + '/auth/refresh').flush({...response,accessToken:'token-two'});
    await Promise.resolve(); await Promise.resolve();
    controller.expectOne(base + '/auth/sessions').flush({}, {status:500,statusText:'Server error'});
    await expectAsync(result).toBeRejected(); expect(auth.accessToken()).toBe('token-two');
  });
  it('reuses a token already rotated by a concurrent request', async () => {
    await login(); const first = firstValueFrom(auth.sessions()); const second = firstValueFrom(auth.sessions());
    const requests = controller.match(base + '/auth/sessions');
    requests[0].flush({}, {status:401,statusText:'Unauthorized'});
    controller.expectOne(base + '/auth/refresh').flush({...response,accessToken:'token-two'});
    await Promise.resolve(); await Promise.resolve();
    controller.expectOne(base + '/auth/sessions').flush({items:[]}); await first;
    requests[1].flush({}, {status:401,statusText:'Unauthorized'});
    controller.expectNone(base + '/auth/refresh');
    const retry = controller.expectOne(base + '/auth/sessions'); expect(retry.request.headers.get('Authorization')).toBe('Bearer token-two'); retry.flush({items:[]}); await second;
  });
  it('uses protected session revocation APIs and clears memory on password reset', async () => {
    await login();
    auth.logoutOthers().subscribe(); const others = controller.expectOne(base + '/auth/logout-others'); expect(others.request.method).toBe('POST'); others.flush({message:'ok'});
    auth.revoke('session-2').subscribe(); const revoke = controller.expectOne(base + '/auth/sessions/session-2'); expect(revoke.request.method).toBe('DELETE'); revoke.flush({message:'ok'});
    auth.reset('reset-token','NewPassword123').subscribe(); const reset = controller.expectOne(base + '/auth/reset-password'); expect(reset.request.body).toEqual({token:'reset-token',password:'NewPassword123'}); reset.flush({message:'ok'}); expect(auth.accessToken()).toBeNull();
  });
});

describe('Runtime configuration and return navigation', () => {
  it('keeps valid internal destinations', () => expect(safeReturnUrl('/account?tab=sessions')).toBe('/account?tab=sessions'));
  it('rejects external, encoded external, malformed and auth-loop destinations', () => {
    for (const url of [null,'https://evil.test','//evil.test','/%2fevil.test','/\\evil.test','/login?returnUrl=x','/register','/%','/\n/evil']) expect(safeReturnUrl(url)).toBe('/account');
  });
  it('accepts local and hosted API bases and removes trailing slash', () => {
    expect(validateApiUrl('http://localhost:5080/api/v1/')).toBe('http://localhost:5080/api/v1');
    expect(validateApiUrl('https://api.hutube.test/api/v1')).toBe('https://api.hutube.test/api/v1');
  });
  it('rejects unsafe or credential-bearing configuration', () => {
    for (const url of ['javascript:alert(1)','https://name:secret@example.test/api','https://api.test/#x','https://api.test/?q=x',undefined]) expect(() => validateApiUrl(url)).toThrow();
  });
});
