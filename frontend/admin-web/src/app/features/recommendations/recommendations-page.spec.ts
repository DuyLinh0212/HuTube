import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { RuntimeConfig } from '../../core/runtime-config';
import { I18nService } from '../../core/i18n.service';
import { RecommendationsPage } from './recommendations-page';

describe('Recommendation model statistics', () => {
  const base = 'http://localhost:5080/api/v1/admin/recommendations';
  let http: HttpTestingController;
  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [RecommendationsPage],
      providers: [provideHttpClient(), provideHttpClientTesting(), provideRouter([])],
    });
    TestBed.inject(RuntimeConfig).apiBaseUrl = 'http://localhost:5080/api/v1';
    TestBed.inject(I18nService).setLang('vi');
    http = TestBed.inject(HttpTestingController);
  });
  afterEach(() => http.verify());

  for (const [userCount, actions] of [[119, 100], [50, 1000]]) {
    it(`submits ${userCount * actions} simulation actions`, async () => {
      const fixture = TestBed.createComponent(RecommendationsPage);
      const page = fixture.componentInstance;
      page.selectedCategoryIds.add('music');
      page.selectedVideos.add('video-one');
      for (let i = 0; i < userCount; i++) page.toggleUser({ userId: `bot-${i}`, username: `bot${i}`, displayName: 'Bot', isBot: true });
      page.actionsPerUser = actions;
      await page.simulate();
      const request = http.expectOne(base + '/simulation-jobs');
      expect(request.request.body.userIds.length * request.request.body.actionsPerUser).toBe(userCount * actions);
      request.flush({}, { status: 503, statusText: 'Fixture does not execute simulations' });
      fixture.destroy();
    });
  }

  it('rejects more than 50,000 actions before making a request', async () => {
    const fixture = TestBed.createComponent(RecommendationsPage);
    const page = fixture.componentInstance;
    page.selectedCategoryIds.add('music'); page.selectedVideos.add('video-one');
    for (let i = 0; i < 51; i++) page.toggleUser({ userId: `bot-${i}`, username: `bot${i}`, displayName: 'Bot', isBot: true });
    page.actionsPerUser = 1000;
    await page.simulate();
    http.expectNone(base + '/simulation-jobs');
    expect(page.error()).toContain('50.000');
    fixture.destroy();
  });

  it('loads inventory independently and keeps the previous data when refresh fails', () => {
    const page = TestBed.createComponent(RecommendationsPage).componentInstance;
    const statistics = { activeModelVersion: 'v1', items: [] };
    page.loadModelStatistics();
    expect(page.loadingModelStatistics()).toBeTrue();
    http.expectOne(base + '/models').flush(statistics);
    expect(page.modelStatistics()).toEqual(statistics);
    expect(page.loadingModelStatistics()).toBeFalse();
    page.loadModelStatistics();
    http.expectOne(base + '/models').flush({}, { status: 503, statusText: 'Unavailable' });
    expect(page.modelStatistics()).toEqual(statistics);
    expect(page.loadingModelStatistics()).toBeFalse();
    expect(page.modelStatisticsError()).toContain('thử lại');
    page.loadModelStatistics();
    http.expectOne(base + '/models').flush(statistics);
    expect(page.modelStatisticsError()).toBe('');
  });

  it('distinguishes unknown historical duration from a valid zero duration', () => {
    const page = TestBed.createComponent(RecommendationsPage).componentInstance;
    expect(page.modelDuration(null)).toBe('Chưa ghi nhận');
    expect(page.modelDuration(0)).toBe('0 giây');
    expect(page.modelDuration(1.234)).toBe('1,234 giây');
  });
});
