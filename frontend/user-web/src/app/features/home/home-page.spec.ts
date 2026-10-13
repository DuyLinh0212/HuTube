import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideRouter, Router, withRouterConfig } from '@angular/router';
import { of, Subject, throwError } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { ContentService, PageResult, VideoCard } from '../../core/content.service';
import { I18nService } from '../../core/i18n.service';
import { HomePage } from './home-page';

describe('Home feed initialization', () => {
  let feed: jasmine.Spy;
  let router: Router;
  beforeEach(() => {
    feed = jasmine.createSpy('feed').and.returnValue(of({ items: [], page: 1, pageSize: 50, total: 0 }));
    TestBed.configureTestingModule({
      imports: [HomePage],
      providers: [
        provideRouter([{ path: 'home', component: HomePage }], withRouterConfig({ onSameUrlNavigation: 'reload' })),
        provideHttpClient(), provideHttpClientTesting(),
        { provide: AuthService, useValue: { user: signal({ userId: 'signed-in-user' }) } },
        { provide: ContentService, useValue: { feed } },
      ],
    });
    TestBed.inject(I18nService).setLang('vi');
    router = TestBed.inject(Router);
  });

  it('starts the feed when the shell creates Home after navigation has already ended', async () => {
    await router.navigateByUrl('/home');
    const fixture = TestBed.createComponent(HomePage);
    fixture.detectChanges();
    await fixture.whenStable();
    expect(feed.calls.allArgs().filter(args => args[0] === 'home').length).toBe(1);
    expect(fixture.componentInstance.loading()).toBeFalse();
  });

  it('still starts the late-created feed without IntersectionObserver support', async () => {
    await router.navigateByUrl('/home');
    const original = window.IntersectionObserver;
    Object.defineProperty(window, 'IntersectionObserver', { value: undefined, configurable: true });
    try {
      const fixture = TestBed.createComponent(HomePage);
      fixture.detectChanges();
      await fixture.whenStable();
      expect(feed.calls.allArgs().filter(args => args[0] === 'home').length).toBe(1);
      expect(fixture.componentInstance.loading()).toBeFalse();
    } finally {
      Object.defineProperty(window, 'IntersectionObserver', { value: original, configurable: true });
    }
  });

  it('loads once during normal navigation and refreshes on a later same-URL navigation', async () => {
    const fixture = TestBed.createComponent(HomePage);
    fixture.detectChanges();
    await router.navigateByUrl('/home');
    await fixture.whenStable();
    expect(feed.calls.allArgs().filter(args => args[0] === 'home').length).toBe(1);
    await router.navigateByUrl('/home');
    await fixture.whenStable();
    expect(feed.calls.allArgs().filter(args => args[0] === 'home').length).toBe(2);
    expect(fixture.componentInstance.loading()).toBeFalse();
  });

  it('leaves loading and displays an error if both the home feed and fallback fail', async () => {
    feed.and.returnValue(throwError(() => new Error('Feed unavailable')));
    await router.navigateByUrl('/home');
    const fixture = TestBed.createComponent(HomePage);
    fixture.detectChanges();
    await fixture.whenStable();
    expect(feed.calls.allArgs().map(args => args[0])).toEqual(['home', 'explore']);
    expect(fixture.componentInstance.loading()).toBeFalse();
    expect(fixture.componentInstance.error()).toBe(TestBed.inject(I18nService).t('home.error'));
  });

  it('ignores a pending feed result after the old layout destroys Home', async () => {
    const pending = new Subject<PageResult<VideoCard>>();
    feed.and.callFake((kind: string) => kind === 'home'
      ? pending : of({ items: [], page: 1, pageSize: 50, total: 0 }));
    await router.navigateByUrl('/home');
    const fixture = TestBed.createComponent(HomePage);
    fixture.detectChanges();
    fixture.destroy();
    pending.next({ items: [], page: 1, pageSize: 50, total: 0 });
    pending.complete();
    await fixture.whenStable();
    expect(feed.calls.allArgs().map(args => args[0])).toEqual(['home']);
  });
});
