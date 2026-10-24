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
