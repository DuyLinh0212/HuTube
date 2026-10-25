import { TestBed } from '@angular/core/testing';
import { of } from 'rxjs';
import { AuthService } from './auth.service';
import { RuntimeConfig } from './runtime-config';
import { VideoDownloadService } from './video-download.service';

describe('Video file saving', () => {
  let service: VideoDownloadService;
  let fetchFile: jasmine.Spy;
  let picker: jasmine.Spy;
  let originalPicker: PropertyDescriptor | undefined;
  let bytes: number[];
  let closed: boolean;

  beforeEach(() => {
    bytes = []; closed = false;
    originalPicker = Object.getOwnPropertyDescriptor(window, 'showSaveFilePicker');
    picker = jasmine.createSpy('picker').and.resolveTo({ createWritable: async () => new WritableStream<Uint8Array>({
      write(chunk) { bytes.push(...chunk); }, close() { closed = true; }
    }) });
    Object.defineProperty(window, 'showSaveFilePicker', { configurable: true, value: picker });
    TestBed.configureTestingModule({ providers: [
      { provide: RuntimeConfig, useValue: { apiBaseUrl: 'https://api.test/api/v1' } },
      { provide: AuthService, useValue: { sessionVersion: 1, ensureFreshAccessToken: () => of('access'), refresh: () => of({ accessToken: 'fresh' }) } }
    ] });
    fetchFile = spyOn(window, 'fetch').and.callFake(async () => new Response(new Uint8Array([1, 2, 3]), { headers: { 'Content-Type': 'video/mp4' } }));
    service = TestBed.inject(VideoDownloadService);
  });
  afterEach(() => {
    if (originalPicker) Object.defineProperty(window, 'showSaveFilePicker', originalPicker);
    else delete (window as unknown as Record<string, unknown>)['showSaveFilePicker'];
  });

  it('opens Save As before requesting bytes and streams the authorized video to disk', async () => {
    const saving = service.save('video', '720p', 'Kí sự / Jura', '.webm');
    expect(picker).toHaveBeenCalled();
    expect(fetchFile).not.toHaveBeenCalled();
    expect(await saving).toBe('saved');
    expect(picker.calls.mostRecent().args[0].suggestedName).toBe('Kí sự  Jura-720p.webm');
    expect(fetchFile).toHaveBeenCalledWith('https://api.test/api/v1/videos/video/download-file', jasmine.objectContaining({
      method: 'POST', body: JSON.stringify({ quality: '720p' }),
      headers: jasmine.objectContaining({ Authorization: 'Bearer access' })
    }));
    expect(bytes).toEqual([1, 2, 3]);
    expect(closed).toBeTrue();
  });
  it('does not create a download when the user cancels the save dialog', async () => {
    picker.and.rejectWith(new DOMException('cancel', 'AbortError'));
    expect(await service.save('video', '720p', 'Video')).toBeFalse();
    expect(fetchFile).not.toHaveBeenCalled();
  });
  it('does not write an API error page into the saved video', async () => {
    fetchFile.and.resolveTo(new Response(JSON.stringify({ code: 'DOWNLOAD_NOT_INCLUDED' }), { status: 403 }));
    await expectAsync(service.save('video', '720p', 'Video')).toBeRejectedWith(jasmine.objectContaining({ status: 403 }));
    expect(bytes).toEqual([]);
    expect(closed).toBeFalse();
  });
  it('uses a local blob download without navigating when Save As is unavailable', async () => {
    Object.defineProperty(window, 'showSaveFilePicker', { configurable: true, value: undefined });
    spyOn(HTMLAnchorElement.prototype, 'click');
    spyOn(URL, 'createObjectURL').and.returnValue('blob:local-video');
    expect(await service.save('video', '720p', 'Video')).toBe('started');
    expect(URL.createObjectURL).toHaveBeenCalled();
    expect(HTMLAnchorElement.prototype.click).toHaveBeenCalled();
    expect(location.pathname).not.toContain('download-file');
  });
});
