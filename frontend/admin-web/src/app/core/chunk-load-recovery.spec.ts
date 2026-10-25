import { DOCUMENT } from '@angular/common';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, convertToParamMap } from '@angular/router';
import { CHUNK_RETRY_KEY, ChunkLoadRecovery, internalPath, isChunkLoadError } from './chunk-load-recovery';
import { PageLoadError } from './page-load-error';

describe('lazy page recovery', () => {
  const missingChunk = new TypeError('Failed to fetch dynamically imported module: /chunk-old.js');
  let values: Map<string, string>;
  let browser: { location: { origin: string; pathname: string; search: string; replace: jasmine.Spy; reload: jasmine.Spy }; history: { state: unknown; replaceState: jasmine.Spy }; navigator: { onLine: boolean }; sessionStorage: { getItem: jasmine.Spy; setItem: jasmine.Spy } };
  let recovery: ChunkLoadRecovery;

  beforeEach(() => {
    values = new Map();
    browser = {
      location: { origin: 'https://admin.example.test', pathname: '/roles', search: '', replace: jasmine.createSpy('replace'), reload: jasmine.createSpy('reload') },
      history: { state: { navigationId: 1 }, replaceState: jasmine.createSpy('replaceState') },
      navigator: { onLine: true },
      sessionStorage: {
        getItem: jasmine.createSpy('getItem').and.callFake((key: string) => values.get(key) ?? null),
        setItem: jasmine.createSpy('setItem').and.callFake((key: string, value: string) => values.set(key, value)),
      },
    };
    TestBed.configureTestingModule({ providers: [{ provide: DOCUMENT, useValue: { defaultView: browser } }] });
    spyOn(Date, 'now').and.returnValue(100_000);
    recovery = TestBed.inject(ChunkLoadRecovery);
  });

  it('requests a fresh document at the intended page, preserving query and fragment', () => {
    expect(recovery.recover(missingChunk, '/moderation/videos?tab=active#queue')).toBe('/moderation/videos?tab=active#queue');
    expect(browser.location.replace).toHaveBeenCalledOnceWith('/moderation/videos?tab=active#queue');
    expect(values.get(CHUNK_RETRY_KEY)).toBe('100000');
  });

  it('keeps its guard across another application instance after a reload', () => {
    recovery.recover(missingChunk, '/moderation/videos');
    const second = TestBed.runInInjectionContext(() => new ChunkLoadRecovery());
    second.recover(missingChunk, '/moderation/videos');
    expect(browser.location.replace).toHaveBeenCalledTimes(1);
  });

  it('forces a document reload when a direct URL already has the requested path and fragment', () => {
    browser.location.pathname = '/moderation/videos';
    browser.location.search = '?tab=active';
    recovery.recover(missingChunk, '/moderation/videos?tab=active#queue');
    expect(browser.history.replaceState).toHaveBeenCalledOnceWith(browser.history.state, '', '/moderation/videos?tab=active#queue');
    expect(browser.location.reload).toHaveBeenCalledOnceWith();
    expect(browser.location.replace).not.toHaveBeenCalled();
    recovery.recover(missingChunk, '/moderation/videos?tab=active#queue');
    expect(browser.location.reload).toHaveBeenCalledTimes(1);
  });

  it('allows a later recovery after the cooldown', () => {
    values.set(CHUNK_RETRY_KEY, '10000');
    recovery.recover(missingChunk, '/moderation/videos');
    expect(browser.location.replace).toHaveBeenCalledTimes(1);
  });

  it('offers manual recovery while offline without reloading', () => {
    browser.navigator.onLine = false;
    expect(recovery.recover(missingChunk, '/moderation/videos')).toBe('/moderation/videos');
    expect(browser.location.replace).not.toHaveBeenCalled();
  });

  it('does not loop when session storage is blocked', () => {
    browser.sessionStorage.setItem.and.throwError('blocked');
    expect(recovery.recover(missingChunk, '/moderation/videos')).toBe('/moderation/videos');
    expect(browser.location.replace).not.toHaveBeenCalled();
  });

  it('leaves ordinary application errors and API errors to the existing handler', () => {
    expect(recovery.recover(new Error('API unavailable'), '/moderation/videos')).toBeNull();
    expect(recovery.recover(new TypeError('Cannot read properties of undefined'), '/moderation/videos')).toBeNull();
    expect(browser.location.replace).not.toHaveBeenCalled();
  });

  it('recognizes Firefox and Safari module failures', () => {
    expect(isChunkLoadError(new TypeError('error loading dynamically imported module'))).toBeTrue();
    expect(isChunkLoadError(new TypeError('Importing a module script failed.'))).toBeTrue();
  });

  it('rejects external targets and never tries to recover its own error page', () => {
    for (const target of ['https://evil.test', '//evil.test', '/\\evil.test', '/load-error?returnUrl=/roles']) {
      expect(recovery.recover(missingChunk, target)).toBeNull();
    }
    expect(browser.location.replace).not.toHaveBeenCalled();
    expect(internalPath('/moderation/videos?tab=active#queue', browser.location.origin)).toBe('/moderation/videos?tab=active#queue');
  });

  it('validates the manual retry URL independently', () => {
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({ providers: [
      { provide: DOCUMENT, useValue: { defaultView: browser } },
      { provide: ActivatedRoute, useValue: { snapshot: { queryParamMap: convertToParamMap({ returnUrl: '//evil.test' }) } } },
    ] });
    const page = TestBed.runInInjectionContext(() => new PageLoadError());
    page.retry();
    expect(browser.location.replace).toHaveBeenCalledOnceWith('/roles');
  });
});
