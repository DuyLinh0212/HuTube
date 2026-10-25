import { TestBed } from '@angular/core/testing';
import { I18nService } from './i18n.service';
import { CompactLikeCountPipe } from './locale-number.pipe';

describe('Localized compact like counts', () => {
  let i18n: I18nService;
  let pipe: CompactLikeCountPipe;
  let savedLanguages: (string | null)[];
  const storageKeys = ['hutube_lang', 'hutube_admin_lang'];
  beforeEach(() => {
    savedLanguages = storageKeys.map(key => localStorage.getItem(key));
    TestBed.configureTestingModule({});
    i18n = TestBed.inject(I18nService);
    pipe = TestBed.runInInjectionContext(() => new CompactLikeCountPipe());
  });
  afterEach(() => storageKeys.forEach((key, index) => {
    const value = savedLanguages[index];
    if (value === null) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  }));

  for (const [value, vi, en] of [
    [0, '0', '0'], [999, '999', '999'], [1200, '1,2N', '1.2K'],
    [1200000, '1,2Tr', '1.2M'], [999950, '1Tr', '1M'],
    [1200000000, '1,2T', '1.2B'], [-10, '0', '0'], [NaN, '0', '0'],
  ] as const) {
    it(`formats ${value} and follows language changes`, () => {
      i18n.setLang('vi'); expect(pipe.transform(value)).toBe(vi);
      i18n.setLang('en'); expect(pipe.transform(value)).toBe(en);
    });
  }
});
