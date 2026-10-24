import { TestBed, fakeAsync, tick, flushMicrotasks } from '@angular/core/testing';
import { HttpEventType, provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { firstValueFrom, of } from 'rxjs';
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
      { provide: AuthService, useValue: { user: () => signedIn ? { userId: 'viewer' } : null, sessionVersion: 1,
        ensureFreshAccessToken: () => of('token') } },
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
  it('uses the fallback during the recommendation service cooldown', async () => {
    const first = firstValueFrom(service.feed('home'));
    http.expectOne(request => request.url.startsWith(recommendationBase)).flush({}, { status: 429, statusText: 'Limited' });
    http.expectOne(`${contentBase}/feed/resolve`).flush(page);
    await first;
    const second = firstValueFrom(service.feed('home'));
    http.expectNone(request => request.url.startsWith(recommendationBase));
    http.expectOne(`${contentBase}/feed/resolve`).flush(page);
    expect(await second).toEqual(page);
  });
  it('polls an accepted upload completion and emits only the completed video', fakeAsync(() => {
    const data = new FormData();
    data.append('Video', new File(['video'], 'video.mp4', { type: 'video/mp4' }));
    data.append('ChannelId', 'channel');
    let result: unknown;
    service.upload(data, 'upload-id').subscribe(event => { if ('body' in event) result = event.body; });
    http.expectOne(`${contentBase}/videos/upload-sessions`).flush({ uploadId: 'upload-id', chunkSize: 8, nextChunk: 0 });
    http.expectOne(`${contentBase}/videos/upload-sessions/upload-id/chunks/0`).flush({ nextChunk: 1 });
    const complete = http.expectOne(`${contentBase}/videos/upload-sessions/upload-id/complete`);
    expect(complete.request.headers.get('Prefer')).toBe('respond-async');
    complete.flush({ status: 'processing' }, { status: 202, statusText: 'Accepted' });
    expect(result).toBeUndefined();
    tick(5_000);
    http.expectOne(`${contentBase}/videos/upload-sessions/upload-id`).flush({ status: 'processing' }, { status: 202, statusText: 'Accepted' });
    tick(5_000);
    http.expectOne(`${contentBase}/videos/upload-sessions/upload-id`).flush({ videoId: 'video-id' });
    flushMicrotasks();
    expect(result).toEqual({ videoId: 'video-id' });
    tick(5_000);
    http.expectNone(`${contentBase}/videos/upload-sessions/upload-id`);
  }));
  it('reuses one chunk URL with index headers when the server supports protocol 2', () => {
    const data = new FormData();
    data.append('Video', new File(['0123456789'], 'video.mp4', { type: 'video/mp4' }));
    data.append('ChannelId', 'channel');
    let completed: unknown;
    service.upload(data, 'resumed').subscribe(event => { if ('body' in event) completed = event.body; });
    http.expectOne(`${contentBase}/videos/upload-sessions`).flush({
      uploadId: 'resumed', chunkSize: 4, nextChunk: 1, chunkProtocol: 2,
    });
    const first = http.expectOne(`${contentBase}/videos/upload-sessions/resumed/chunks`);
    expect(first.request.headers.get('X-Upload-Chunk-Index')).toBe('1');
    expect(first.request.body.get('chunk').size).toBe(4);
    first.flush({ nextChunk: 2 });
    const second = http.expectOne(`${contentBase}/videos/upload-sessions/resumed/chunks`);
    expect(second.request.headers.get('X-Upload-Chunk-Index')).toBe('2');
    expect(second.request.body.get('chunk').size).toBe(2);
    second.flush({ nextChunk: 3 });
    http.expectOne(`${contentBase}/videos/upload-sessions/resumed/complete`).flush({ videoId: 'saved' });
    expect(completed).toEqual({ videoId: 'saved' });
  });
  it('waits for the final chunk acknowledgement before reporting all bytes received', () => {
    const data = new FormData();
    data.append('Video', new File(['0123'], 'video.mp4', { type: 'video/mp4' }));
    const loaded: number[] = [];
    service.upload(data, 'ack').subscribe(event => {
      if (event.type === HttpEventType.UploadProgress) loaded.push(event.loaded);
    });
    http.expectOne(`${contentBase}/videos/upload-sessions`).flush({ uploadId: 'ack', chunkSize: 4, nextChunk: 0 });
    const chunk = http.expectOne(`${contentBase}/videos/upload-sessions/ack/chunks/0`);
    chunk.event({ type: HttpEventType.UploadProgress, loaded: 4, total: 4 });
    expect(loaded.at(-1)).toBe(3);
    chunk.flush({ nextChunk: 1 });
    expect(loaded.at(-1)).toBe(4);
    http.expectOne(`${contentBase}/videos/upload-sessions/ack/complete`).flush({ videoId: 'saved' });
  });
});
