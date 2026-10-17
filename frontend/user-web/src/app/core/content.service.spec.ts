import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { firstValueFrom } from 'rxjs';
import { AuthService } from './auth.service';
import { ContentService } from './content.service';
import { RuntimeConfig } from './runtime-config';

describe('Direct recommendation feed', () => {
  const contentBase = 'http://localhost:5080/api/v1';
  const recommendationBase = 'http://localhost:8000/api/v1';
  const page = { items: [], page: 2, pageSize: 10, total: 0 };
  let service: ContentService;
  let http: HttpTestingController;
  let signedIn: boolean;

  beforeEach(() => {
    signedIn = true;
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting(),
      { provide: AuthService, useValue: { user: () => signedIn ? { userId: 'viewer' } : null, sessionVersion: 1 } },
    ] });
    const config = TestBed.inject(RuntimeConfig);
    config.apiBaseUrl = contentBase;
    config.recommendationBaseUrl = recommendationBase;
    service = TestBed.inject(ContentService);
    http = TestBed.inject(HttpTestingController);
  });
  afterEach(() => http.verify());

  it('loads signed-in recommendations directly from FastAPI with pagination', async () => {
    const result = firstValueFrom(service.feed('home', 2, 10));
    const request = http.expectOne(`${recommendationBase}/feed/recommended?page=2&pageSize=10`);
    expect(request.request.method).toBe('GET');
    request.flush(page);
    expect(await result).toEqual(page);
  });

  it('resolves an empty ranking on FastAPI failure without calling the .NET recommendation route', async () => {
    const result = firstValueFrom(service.feed('home', 2, 10));
    http.expectOne(`${recommendationBase}/feed/recommended?page=2&pageSize=10`)
      .flush({}, { status: 503, statusText: 'Service Unavailable' });
    const fallback = http.expectOne(`${contentBase}/feed/resolve`);
    expect(fallback.request.body).toEqual({ videoIds: [], page: 2, pageSize: 10 });
    fallback.flush(page);
    expect(await result).toEqual(page);
    http.expectNone(request => request.url === `${contentBase}/feed/home`);
  });

  it('keeps anonymous and exploration feeds on the content API', async () => {
    signedIn = false;
    const home = firstValueFrom(service.feed('home', 2, 10));
    http.expectOne(`${contentBase}/feed/home?page=2&pageSize=10`).flush(page);
    expect(await home).toEqual(page);
    signedIn = true;
    const explore = firstValueFrom(service.feed('explore', 2, 10));
    http.expectOne(`${contentBase}/feed/explore?page=2&pageSize=10`).flush(page);
    expect(await explore).toEqual(page);
  });
});
