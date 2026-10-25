import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { fakeAsync, TestBed, tick } from '@angular/core/testing';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { RuntimeConfig } from '../../core/runtime-config';
import { AdminChannelsPage } from './admin-channels-page';
import { AdminChannel } from './admin-channels.service';

describe('Channel suspension duration', () => {
  const base = 'http://localhost:5080/api/v1/admin';
  const channel: AdminChannel = { channelId: 'channel-1', name: 'Wolf Music', handle: 'wolfmusic',
    ownerUserId: 'owner-1', ownerName: 'Owner', ownerEmail: 'owner@example.test',
    status: 'active', createdAt: '2026-10-20T00:00:00Z', videoCount: 2, subscriberCount: 0, activeStrikeCount: 0 };
  let http: HttpTestingController;
  let page: AdminChannelsPage;
  let allowed: boolean;

  beforeEach(() => {
    allowed = true;
    TestBed.configureTestingModule({ imports: [AdminChannelsPage], providers: [
      provideHttpClient(), provideHttpClientTesting(),
      { provide: AuthService, useValue: { hasPermission: () => allowed } }
    ] });
    TestBed.inject(RuntimeConfig).apiBaseUrl = base.slice(0, -6);
    http = TestBed.inject(HttpTestingController);
    page = TestBed.createComponent(AdminChannelsPage).componentInstance;
  });
  afterEach(() => http.verify());

  function finish() {
    http.expectOne(request => request.url === base + '/channels').flush({ items: [], page: 1, pageSize: 8, total: 0 });
    http.expectOne(base + '/channels/counts').flush({ all: 0, active: 0, restricted: 0, banned: 0 });
    tick(4000);
  }

  it('defaults to seven days and sends a UTC deadline only once while busy', fakeAsync(() => {
    const now = Date.now();
    page.openActionModal('suspend', channel);
    page.actionModalReason.set('Test suspension');
    expect(page.suspensionDuration()).toBe('7');
    page.submitAction();
    page.submitAction();
    page.closeActionModal();
    expect(page.showActionModal()).toBeTrue();
    const request = http.expectOne(base + '/channels/channel-1/suspend');
    expect(request.request.method).toBe('POST');
    expect(new Date(request.request.body.suspendedUntil).getTime()).toBe(now + 7 * 86_400_000);
    expect(request.request.body.notifyOwner).toBeTrue();
    request.flush(null);
    expect(page.showActionModal()).toBeFalse();
    finish();
  }));

  it('requires a future custom date and revalidates immediately before submitting', fakeAsync(() => {
    page.openActionModal('suspend', channel);
    page.actionModalReason.set('Test suspension');
    page.suspensionDuration.set('custom');
    for (const value of ['', 'bad-date', '2000-01-01T10:00']) {
      page.suspensionCustomUntil.set(value);
      page.submitAction();
      expect(page.suspensionInvalid()).toBeTrue();
      http.expectNone(base + '/channels/channel-1/suspend');
    }
    // datetime-local is interpreted in the device time zone and serialized as UTC.
    const date = new Date(Date.now() + 86_400_000);
    const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000).toISOString().slice(0, 16);
    page.suspensionCustomUntil.set(local);
    expect(page.suspensionInvalid()).toBeFalse();
    page.submitAction();
    const request = http.expectOne(base + '/channels/channel-1/suspend');
    expect(request.request.body.suspendedUntil).toBe(new Date(local).toISOString());
    request.flush(null);
    finish();
  }));

  it('keeps the duration on failure and resets it for a new action', () => {
    page.openActionModal('suspend', channel);
    page.actionModalReason.set('Test suspension');
    page.suspensionDuration.set('30');
    page.submitAction();
    http.expectOne(base + '/channels/channel-1/suspend').flush({ message: 'Retry please' }, { status: 503, statusText: 'Unavailable' });
    expect(page.showActionModal()).toBeTrue();
    expect(page.suspensionDuration()).toBe('30');
    expect(page.error()).toBe('Retry please');
    page.closeActionModal();
    page.openActionModal('ban', channel);
    expect(page.suspensionDuration()).toBe('7');
    expect(page.error()).toBe('');
    page.actionModalReason.set('Ban reason');
    page.submitAction();
    const request = http.expectOne(base + '/channels/channel-1/ban');
    expect(request.request.body.suspendedUntil).toBeUndefined();
    request.flush({}, { status: 503, statusText: 'Unavailable' });
  });

  it('supports explicit indefinite suspension', fakeAsync(() => {
    page.openActionModal('suspend', channel);
    page.actionModalReason.set('Manual restore required');
    page.suspensionDuration.set('indefinite');
    page.submitAction();
    const request = http.expectOne(base + '/channels/channel-1/suspend');
    expect(request.request.body.suspendedUntil).toBeNull();
    request.flush(null);
    finish();
  }));

  it('does not open a suspension dialog without permission', () => {
    allowed = false;
    page.openActionModal('suspend', channel);
    expect(page.showActionModal()).toBeFalse();
  });

  it('provides Vietnamese and English duration and expiry labels', () => {
    const i18n = TestBed.inject(I18nService);
    const previous = i18n.currentLang();
    try {
      i18n.setLang('vi');
      expect(i18n.t('channels.suspensionDuration')).toBe('Thời gian tạm ngưng');
      expect(page.auditActionLabel('channel.suspension_expired')).toContain('tự động mở lại');
      i18n.setLang('en');
      expect(i18n.t('channels.suspensionDuration')).toBe('Suspension duration');
      expect(page.auditActionLabel('channel.suspension_expired')).toContain('automatically restored');
    } finally { i18n.setLang(previous); }
  });
});
