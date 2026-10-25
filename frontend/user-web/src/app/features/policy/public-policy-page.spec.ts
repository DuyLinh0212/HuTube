import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ActivatedRoute, Router, UrlSegment, provideRouter } from '@angular/router';
import { BehaviorSubject } from 'rxjs';
import { I18nService } from '../../core/i18n.service';
import { PublicPolicy, PublicPolicyPage } from './public-policy-page';

function isolateLanguagePreference(): void {
  const keys = ['hutube_lang', 'hutube_admin_lang'];
  let saved: (string | null)[];
  beforeEach(() => {
    saved = keys.map(key => localStorage.getItem(key));
    keys.forEach(key => localStorage.setItem(key, 'vi'));
  });
  afterEach(() => {
    // setLang persists both preferences; never leak a test's language to another suite.
    keys.forEach((key, index) => {
      const value = saved[index];
      if (value === null) localStorage.removeItem(key);
      else localStorage.setItem(key, value);
    });
  });
}

describe('Public policy collection and complete exports', () => {
  isolateLanguagePreference();
  let page: PublicPolicyPage;
  let http: HttpTestingController;
  let query: BehaviorSubject<Record<string, string>>;
  let url: BehaviorSubject<UrlSegment[]>;
  const published = (code: string, group: string): PublicPolicy => ({
    policyId: code, code, group, name: `Published ${code}`, content: `Latest content for ${code}`,
    severity: 'high', version: '9.4', status: 'published', effectiveAt: '2026-10-24T00:00:00Z'
  });
  beforeEach(() => {
    query = new BehaviorSubject<Record<string, string>>({});
    url = new BehaviorSubject([new UrlSegment('policies', {})]);
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting(),
      { provide: ActivatedRoute, useValue: { url, queryParams: query } },
      { provide: Router, useValue: { navigate: () => Promise.resolve(true) } }
    ] });
    TestBed.inject(I18nService).setLang('vi');
    page = TestBed.runInInjectionContext(() => new PublicPolicyPage());
    http = TestBed.inject(HttpTestingController);
  });
  afterEach(() => http.verify());

  it('shows the full four-category collection on the default route', () => {
    page.ngOnInit(); http.expectOne('/policies').flush([]);
    expect(page.activeTab()).toBe('all');
    expect(page.policySections().length).toBe(4);
    expect(page.activeList().some(item => item.code === page.privacyList[0].code)).toBeTrue();
    expect(page.activeList().some(item => item.code === page.enforcementList[0].code)).toBeTrue();
    expect(page.activeList().length).toBe(page.allPolicyItems().length);
  });
  it('resets the category when navigating back to a URL without a tab', () => {
    page.ngOnInit(); http.expectOne('/policies').flush([]);
    query.next({ tab: 'privacy' }); expect(page.activeTab()).toBe('privacy');
    query.next({}); expect(page.activeTab()).toBe('all');
    url.next([new UrlSegment('terms', {})]); expect(page.activeTab()).toBe('terms');
    query.next({ tab: 'invalid' }); expect(page.activeTab()).toBe('terms');
  });
  it('does not reopen the retired category from a saved URL', () => {
    query.next({ tab: 'monetization' });
    page.ngOnInit(); http.expectOne('/policies').flush([]);
    expect(page.activeTab()).toBe('all');
    expect(page.tabs.some(tab => String(tab.key) === 'monetization')).toBeFalse();
  });
  it('excludes monetization policies from search, print data and the full PDF even when the API returns them', () => {
    page.policies.set([
      published('AD_SUITABILITY_GUIDE', 'content'),
      published('PARTNER_ELIGIBILITY', 'terms'),
      published('REVENUE_PAYOUTS', 'privacy'),
      published('NEW_MONETIZATION_RULE', 'monetization'),
      published('VISIBLE_PRIVACY_RULE', 'privacy')
    ]);
    const codes = page.allPolicyItems().map(item => item.code);
    for (const code of ['AD_SUITABILITY_GUIDE', 'PARTNER_ELIGIBILITY', 'REVENUE_PAYOUTS', 'NEW_MONETIZATION_RULE']) {
      expect(codes).not.toContain(code);
      expect(JSON.stringify(page.createPdfDocument().content)).not.toContain(code);
    }
    expect(codes).toContain('VISIBLE_PRIVACY_RULE');
    page.searchQuery.set('AD_SUITABILITY_GUIDE'); expect(page.activeList()).toEqual([]);
  });
  it('uses the latest published text once, even if a known code changes category', () => {
    page.policies.set([published('CHILD_SAFETY', 'privacy')]);
    const items = page.allPolicyItems().filter(item => item.code === 'CHILD_SAFETY');
    expect(items.length).toBe(1);
    expect(page.getItemSummary(items[0])).toBe('Latest content for CHILD_SAFETY');
    expect(page.policySections().find(section => section.key === 'privacy')!.items).toContain(items[0]);
  });
  it('retains legacy groups and previously unknown published policy codes', () => {
    page.policies.set([published('NEW_RULE', 'new-group'), published('NEW_LEGAL_RULE', 'legal')]);
    expect(page.policySections()[0].items.some(item => item.code === 'NEW_RULE')).toBeTrue();
    expect(page.policySections().find(section => section.key === 'terms')!.items.some(item => item.code === 'NEW_LEGAL_RULE')).toBeTrue();
  });
  it('searches across categories with Vietnamese accent-insensitive matching', () => {
    page.searchQuery.set('  quyen rieng tu  ');
    expect(page.activeList().length).toBeGreaterThan(0);
    page.searchQuery.set('no-such-policy-9876'); expect(page.activeList()).toEqual([]);
  });
  it('exports every category and latest policy even when the screen has no search results', () => {
    page.policies.set([published('NEW_PRIVACY_RULE', 'privacy')]);
    page.activeTab.set('guidelines'); page.searchQuery.set('no-such-policy-9876');
    expect(page.activeList()).toEqual([]);
    const document = JSON.stringify(page.createPdfDocument().content);
    expect(document).toContain('Latest content for NEW_PRIVACY_RULE');
    for (const section of page.policySections()) {
      expect(document).toContain(page.i18n.t(section.labelKey));
      for (const item of section.items) expect(document).toContain(page.getItemSummary(item));
    }
    expect(document).toContain('9.4');
  });
  it('keeps search and selected category unchanged after preparing a full PDF', () => {
    page.activeTab.set('privacy'); page.searchQuery.set('privacy');
    page.createPdfDocument();
    expect(page.activeTab()).toBe('privacy'); expect(page.searchQuery()).toBe('privacy');
  });
  it('reports failed loading and allows a fresh retry', () => {
    page.loadBackendPolicies(); http.expectOne('/policies').flush('unavailable', { status: 503, statusText: 'Unavailable' });
    expect(page.loadError()).toBeTrue(); expect(page.loading()).toBeFalse();
    page.loadBackendPolicies(); expect(page.loadError()).toBeFalse();
    http.expectOne('/policies').flush([published('RETRY_RULE', 'terms')]);
    expect(page.policies()[0].code).toBe('RETRY_RULE'); expect(page.loading()).toBeFalse();
  });
});

describe('Compact policy page removes retired UI', () => {
  isolateLanguagePreference();
  beforeEach(() => TestBed.configureTestingModule({
    imports: [PublicPolicyPage],
    providers: [provideRouter([]), provideHttpClient(), provideHttpClientTesting()]
  }));
  it('never renders privacy tool cards or a monetization link in either language', () => {
    const fixture = TestBed.createComponent(PublicPolicyPage);
    fixture.detectChanges(); TestBed.inject(HttpTestingController).expectOne('/policies').flush([]);
    const page = fixture.componentInstance;
    for (const lang of ['vi', 'en'] as const) {
      page.i18n.setLang(lang);
      for (const tab of ['all', 'privacy', 'terms', 'enforcement'] as const) {
        page.activeTab.set(tab); fixture.detectChanges();
        const root: HTMLElement = fixture.nativeElement;
        expect(root.querySelector('#quyen-va-lua-chon, .tools-grid, .custom-switch')).toBeNull();
        expect(root.textContent).not.toContain('Kiếm tiền & Đối tác');
        expect(root.textContent).not.toContain('Monetization & Partner');
        expect(root.querySelector('.badge-vn-standard, .hero-meta-row, .tab-counter')).toBeNull();
      }
    }
  });
});
