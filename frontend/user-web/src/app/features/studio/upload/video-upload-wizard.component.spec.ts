import { signal } from '@angular/core';
import { ComponentFixture, TestBed, fakeAsync, flushMicrotasks } from '@angular/core/testing';
import { Router } from '@angular/router';
import { of, Subject } from 'rxjs';
import { AuthService } from '../../../core/auth.service';
import { ContentService, UploadPreflight } from '../../../core/content.service';
import { I18nService } from '../../../core/i18n.service';
import { PlaylistService } from '../../../core/playlist.service';
import { StudioDataService } from '../../../core/studio-data.service';
import { UploadStateService } from '../../../core/upload-state.service';
import { VideoUploadWizardComponent } from './video-upload-wizard.component';

describe('Upload wizard accepted file navigation', () => {
  let fixture: ComponentFixture<VideoUploadWizardComponent>;
  let wizard: VideoUploadWizardComponent;
  let content: jasmine.SpyObj<ContentService>;
  let response: Subject<UploadPreflight>;
  let metadata: jasmine.Spy;
  let thumbnails: jasmine.Spy;
  const allowed: UploadPreflight = {
    allowed: true, maxUploadSize: 1e9, maxDuration: 3600, maxQuality: '1080p',
    storageLimit: 1e9, storageUsed: 0, storageRemaining: 1e9,
  };

  beforeEach(() => {
    response = new Subject();
    content = jasmine.createSpyObj('content', ['categories', 'preflight']);
    content.categories.and.returnValue(of([]));
    content.preflight.and.returnValue(response);
    TestBed.configureTestingModule({ providers: [
      { provide: ContentService, useValue: content },
      { provide: AuthService, useValue: { user: signal(null) } },
      { provide: I18nService, useValue: { t: (key: string) => key } },
      { provide: StudioDataService, useValue: {
        load: () => undefined, channel: signal({ channelId: 'channel' }), videos: signal([]),
      } },
      { provide: PlaylistService, useValue: { mine: () => of([]) } },
      { provide: UploadStateService, useValue: {
        state: signal({ phase: 'idle', progress: 0 }), reset: () => undefined,
      } },
      { provide: Router, useValue: {} },
    ] });
    TestBed.overrideComponent(VideoUploadWizardComponent, { set: { template: '', imports: [] } });
    spyOn(window, 'scrollTo');
    spyOn(HTMLMediaElement.prototype, 'load');
    fixture = TestBed.createComponent(VideoUploadWizardComponent);
    wizard = fixture.componentInstance;
    fixture.detectChanges();
    metadata = spyOn<any>(wizard, 'loadVideoMetadata').and.callFake((video: HTMLVideoElement) => {
      Object.defineProperties(video, {
        duration: { value: 15 }, videoWidth: { value: 1920 }, videoHeight: { value: 1080 },
      });
      return Promise.resolve();
    });
    thumbnails = spyOn<any>(wizard, 'generateThumbnails').and.returnValue(Promise.resolve());
  });

  afterEach(() => fixture.destroy());

  function select(name = 'video.mp4', type = 'video/mp4') {
    const input = { files: [new File(['video'], name, { type })], value: name };
    wizard.selectVideo({ target: input } as unknown as Event);
  }

  it('waits for preparation and server acceptance, then opens details automatically', fakeAsync(() => {
    select();
    expect(wizard.currentStep()).toBe(1);
    flushMicrotasks();
    expect(wizard.preflightLoading()).toBeTrue();
    expect(wizard.currentStep()).toBe(1);
    response.next(allowed);
    expect(wizard.currentStep()).toBe(2);
    expect(wizard.videoTitle).toBe('video');
    expect(window.scrollTo as jasmine.Spy).toHaveBeenCalledWith({ top: 0, behavior: 'smooth' });
  }));

  it('handles immediate acceptance without advancing before preparation finishes', fakeAsync(() => {
    content.preflight.and.callFake(() => {
      expect(wizard.isPreparing()).toBeTrue();
      expect(wizard.currentStep()).toBe(1);
      return of(allowed);
    });
    select(); flushMicrotasks();
    expect(wizard.isPreparing()).toBeFalse();
    expect(wizard.currentStep()).toBe(2);
  }));

  it('requires quality reduction confirmation and a new accepted check', fakeAsync(() => {
    select(); flushMicrotasks();
    response.next({ ...allowed, allowed: false, maxQuality: '720p' });
    expect(wizard.qualityLimitPrompt()).toBe('720p');
    expect(wizard.currentStep()).toBe(1);
    const reduced = new Subject<UploadPreflight>();
    content.preflight.and.returnValue(reduced);
    wizard.acceptQualityReduction();
    expect(wizard.currentStep()).toBe(1);
    reduced.next({ ...allowed, maxQuality: '720p' });
    expect(wizard.currentStep()).toBe(2);
  }));

  it('stays on file selection when the server denies the file', fakeAsync(() => {
    select(); flushMicrotasks();
    response.next({ ...allowed, allowed: false });
    expect(wizard.currentStep()).toBe(1);
    expect(wizard.preflightError()).toBeTruthy();
  }));

  it('stays on file selection when the acceptance request fails', fakeAsync(() => {
    select(); flushMicrotasks(); response.error({ status: 500 });
    expect(wizard.currentStep()).toBe(1);
    expect(wizard.preflightError()).toBeTruthy();
  }));

  it('rejects unsupported or unreadable files without calling preflight', fakeAsync(() => {
    select('document.txt', 'text/plain');
    expect(wizard.hasFile()).toBeFalse();
    metadata.and.returnValue(Promise.reject(new Error('Invalid video')));
    select(); flushMicrotasks();
    expect(wizard.currentStep()).toBe(1);
    expect(wizard.uploadError()).toBe('upload.metadataError');
    expect(content.preflight).not.toHaveBeenCalled();
  }));

  it('ignores acceptance after cancellation', fakeAsync(() => {
    select(); flushMicrotasks(); wizard.cancelFile(); response.next(allowed);
    expect(wizard.currentStep()).toBe(1);
    expect(wizard.hasFile()).toBeFalse();
    expect(wizard.preflight()).toBeNull();
  }));

  it('ignores the previous file response while the replacement is being prepared', fakeAsync(() => {
    select(); flushMicrotasks();
    const replacement = new Subject<UploadPreflight>();
    content.preflight.and.returnValue(replacement);
    select('replacement.mp4');
    response.next(allowed);
    expect(wizard.preflight()).toBeNull();
    expect(wizard.currentStep()).toBe(1);
    flushMicrotasks(); replacement.next(allowed);
    expect(wizard.currentStep()).toBe(2);
    expect(wizard.selectedFileName()).toBe('replacement.mp4');
  }));

  it('allows returning to step 1 without advancing again on subsequent checks', fakeAsync(() => {
    select(); flushMicrotasks(); response.next(allowed);
    wizard.setStep(1);
    wizard.onSourceQualityChange('720p'); response.next(allowed);
    expect(wizard.currentStep()).toBe(1);
    wizard.nextStep();
    expect(wizard.currentStep()).toBe(2);
  }));

  it('does not start a request when cancelled during preparation', fakeAsync(() => {
    let finish!: () => void;
    thumbnails.and.returnValue(new Promise<void>(resolve => { finish = resolve; }));
    select(); flushMicrotasks(); wizard.cancelFile(); finish(); flushMicrotasks();
    expect(content.preflight).not.toHaveBeenCalled();
    expect(wizard.currentStep()).toBe(1);
  }));

  it('ignores acceptance after leaving the wizard', fakeAsync(() => {
    select(); flushMicrotasks(); fixture.destroy(); response.next(allowed);
    expect(wizard.currentStep()).toBe(1);
  }));
});
