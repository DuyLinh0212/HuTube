import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { RuntimeConfig } from '../../core/runtime-config';
import { I18nService } from '../../core/i18n.service';
import { RecommendationsPage } from './recommendations-page';

describe('Category comment bank', () => {
  const storageKey = 'hutube.admin.recommendations.comment-bank.v1';
  let original: string | null;
  let fixture: ComponentFixture<RecommendationsPage>;
  let page: RecommendationsPage;
  let http: HttpTestingController;
  beforeEach(() => {
    original = localStorage.getItem(storageKey);
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting(), provideRouter([])] });
    TestBed.inject(RuntimeConfig).apiBaseUrl = 'http://localhost:5080/api/v1';
    TestBed.inject(I18nService).setLang('vi');
    http = TestBed.inject(HttpTestingController);
    fixture = TestBed.createComponent(RecommendationsPage); page = fixture.componentInstance;
    page.categories.set([{ categoryId: 'music-id', name: 'Music', slug: 'music' }, { categoryId: 'daily-id', name: 'Daily', slug: 'daily' }]);
    page.commentCategory.set('daily');
    page.commentBanks.set({ music: ['Music only'], daily: ['Daily only'], default: ['Default only'] });
  });
  afterEach(() => {
    fixture.destroy(); http.verify();
    if (original === null) localStorage.removeItem(storageKey); else localStorage.setItem(storageKey, original);
  });

  function upload(text: string, name = 'comments.csv') {
    const input = { files: [new File([text], name, { type: 'text/csv' })], value: name };
    return { input, event: { target: input } as unknown as Event };
  }

  it('imports and persists comments into the selected category without altering other banks', async () => {
    const { input, event } = upload('comment\nDaily only\n"Ngày vui, rất thú vị"\nno\n');
    await page.importCommentCsv(event);
    expect(input.value).toBe('');
    expect(page.commentBanks()['daily']).toEqual(['Daily only', 'Ngày vui, rất thú vị']);
    expect(page.commentBanks()['music']).toEqual(['Music only']);
    expect(JSON.parse(localStorage.getItem(storageKey)!)['daily']).toEqual(page.commentBanks()['daily']);
    expect(page.commentImportMessage()).toContain('thêm 1');
    expect(page.commentImportMessage()).toContain('1 mẫu trùng, 1 dòng');
  });

  it('keeps the original target category if the selection changes while reading a file', async () => {
    const { input, event } = upload('');
    let finish!: (text: string) => void;
    spyOn(input.files[0], 'text').and.returnValue(new Promise<string>(resolve => { finish = resolve; }));
    const reading = page.importCommentCsv(event);
    page.commentCategory.set('music'); finish('comment\nDaily imported'); await reading;
    expect(page.commentBanks()['daily']).toContain('Daily imported');
    expect(page.commentBanks()['music']).toEqual(['Music only']);
    expect(page.commentImportMessage()).toContain('Daily:');
  });

  it('does not change any bank if the CSV is malformed', async () => {
    await page.importCommentCsv(upload('comment\n"unclosed').event);
    expect(page.commentBanks()['daily']).toEqual(['Daily only']);
    expect(page.commentImportError()).toContain('CSV không đúng');
  });

  it('does not report success or change the bank when browser storage fails', async () => {
    const save = spyOn(Storage.prototype, 'setItem').and.throwError('Storage full');
    await page.importCommentCsv(upload('comment\nNew comment').event);
    expect(page.commentBanks()['daily']).toEqual(['Daily only']);
    expect(page.commentImportError()).toBeTruthy(); expect(page.commentImportMessage()).toBe('');
    save.and.callThrough();
  });

  it('rejects the wrong extension and files over 1 MB before reading them', async () => {
    const wrong = upload('comment\nHello', 'comments.txt');
    const read = spyOn(wrong.input.files[0], 'text');
    await page.importCommentCsv(wrong.event); expect(read).not.toHaveBeenCalled();
    await page.importCommentCsv(upload('x'.repeat(1024 * 1024 + 1)).event);
    expect(page.commentImportError()).toContain('1 MB');
    expect(page.commentBanks()['daily']).toEqual(['Daily only']);
  });

  it('never falls back to the default or another category when a bank is missing', () => {
    page.commentCategory.set('unknown'); expect(page.commentsForActiveCategory()).toEqual([]);
  });

  it('sends separate banks for all selected categories regardless of the editor selection', async () => {
    page.selectedCategoryIds.add('music-id'); page.selectedCategoryIds.add('daily-id');
    page.selectedVideos.add('music-video'); page.selectedVideos.add('daily-video');
    page.toggleUser({ userId: 'bot', username: 'bot', displayName: 'Bot', isBot: true });
    await page.simulate();
    const request = http.expectOne('http://localhost:5080/api/v1/admin/recommendations/simulation-jobs');
    expect(request.request.body.commentTemplates).toEqual([]);
    expect(request.request.body.categoryComments).toEqual([
      { categoryId: 'music-id', templates: ['Music only'] }, { categoryId: 'daily-id', templates: ['Daily only'] },
    ]);
    request.flush({}, { status: 503, statusText: 'Fixture does not execute simulations' });
  });
});
