import { fakeAsync, flushMicrotasks, TestBed, tick } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { signal } from '@angular/core';
import { Router } from '@angular/router';
import { of } from 'rxjs';
import { HubConnection, HubConnectionBuilder, HubConnectionState } from '@microsoft/signalr';
import { NotificationService } from './notification.service';
import { AuthService } from './auth.service';
import { RuntimeConfig } from './runtime-config';
import { I18nService } from './i18n.service';
import { NetworkStatusService } from './network/network-status.service';

describe('Notification request budget', () => {
  const page = { items: [], page: 1, pageSize: 5, total: 0, unreadCount: 0, hasMore: false };
  let service: NotificationService;
  let http: HttpTestingController;
  let offline: ReturnType<typeof signal<boolean>>;
  let state: HubConnectionState;
  let reconnecting: () => void;
  let me: jasmine.Spy;

  beforeEach(() => {
    offline = signal(false);
    state = HubConnectionState.Connected;
    me = jasmine.createSpy('me').and.returnValue(of(null));
    const hub = {
      get state() { return state; },
      on() {}, onreconnected() {}, onclose() {},
      onreconnecting(callback: () => void) { reconnecting = callback; },
      start: () => Promise.resolve(), stop: () => Promise.resolve(),
    } as unknown as HubConnection;
    spyOn(HubConnectionBuilder.prototype, 'build').and.returnValue(hub);
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting(),
      { provide: AuthService, useValue: { user: signal(null), accessToken: signal('token'), currentSessionId: () => 'session', me } },
      { provide: NetworkStatusService, useValue: { unavailable: offline } },
      { provide: RuntimeConfig, useValue: { apiBaseUrl: 'https://api.test/api/v1' } },
      { provide: I18nService, useValue: { t: (key: string) => key } },
      { provide: Router, useValue: { navigate: () => Promise.resolve(true) } },
    ] });
    service = TestBed.inject(NotificationService);
    http = TestBed.inject(HttpTestingController);
    TestBed.flushEffects();
  });

  afterEach(() => { service.ngOnDestroy(); http.verify(); });

  function connect() {
    void service.connect();
    flushMicrotasks();
    http.expectOne('https://api.test/api/v1/notifications?page=1&pageSize=5').flush(page);
  }

  it('uses pushed events without polling notifications or auth while connected', fakeAsync(() => {
    connect();
    tick(180_000);
    http.expectNone(request => request.url.endsWith('/notifications'));
    expect(me).not.toHaveBeenCalled();
    service.ngOnDestroy();
  }));

  it('falls back every thirty seconds without overlapping requests and pauses offline', fakeAsync(() => {
    connect();
    state = HubConnectionState.Reconnecting;
    tick(29_999);
    http.expectNone(request => request.url.endsWith('/notifications'));
    tick(1);
    const pending = http.expectOne(request => request.url.endsWith('/notifications'));
    tick(30_000);
    http.expectNone(request => request.url.endsWith('/notifications'));
    expect(me).toHaveBeenCalledTimes(1);
    pending.flush(page);
    offline.set(true);
    tick(120_000);
    http.expectNone(request => request.url.endsWith('/notifications'));
    expect(me).toHaveBeenCalledTimes(1);
    service.ngOnDestroy();
  }));

  it('checks for revoked sessions when the server disconnects the hub', fakeAsync(() => {
    connect();
    reconnecting();
    expect(me).toHaveBeenCalledTimes(1);
    service.ngOnDestroy();
  }));
});
