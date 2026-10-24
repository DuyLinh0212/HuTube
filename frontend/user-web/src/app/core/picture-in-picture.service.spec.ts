import { TestBed } from '@angular/core/testing';
import { PictureInPictureService } from './picture-in-picture.service';

describe('PictureInPictureService playback transfer', () => {
  let service: PictureInPictureService;
  let source: HTMLVideoElement;
  let pip: HTMLVideoElement;
  let ready: number;
  let current: Element | null;
  let paused: WeakMap<HTMLMediaElement, boolean>;
  let request: jasmine.Spy;
  let play: jasmine.Spy;
  let calls: string[];
  let descriptor: PropertyDescriptor | undefined;

  beforeEach(() => {
    paused = new WeakMap();
    calls = [];
    current = null;
    ready = 0;
    descriptor = Object.getOwnPropertyDescriptor(document, 'pictureInPictureElement');
    Object.defineProperty(document, 'pictureInPictureElement', { configurable: true, get: () => current });
    spyOn(HTMLMediaElement.prototype, 'load');
    spyOnProperty(HTMLMediaElement.prototype, 'paused').and.callFake(function (this: HTMLMediaElement) {
      return paused.get(this) ?? true;
    });
    spyOn(HTMLMediaElement.prototype, 'pause').and.callFake(function (this: HTMLMediaElement) {
      paused.set(this, true);
      calls.push(this === source ? 'source-pause' : 'pip-pause');
    });
    play = spyOn(HTMLMediaElement.prototype, 'play').and.callFake(function (this: HTMLMediaElement) {
      paused.set(this, false);
      calls.push(this === source ? 'source-play' : 'pip-play');
      return Promise.resolve();
    });
    source = document.createElement('video');
    source.src = 'https://media.test/video.mp4';
    source.currentTime = 23;
    source.volume = .4;
    source.playbackRate = 1.5;
    paused.set(source, false);
    document.body.appendChild(source);
    service = TestBed.inject(PictureInPictureService);
    service.prepare(source);
    pip = document.querySelector('.global-picture-in-picture-video')!;
    Object.defineProperty(pip, 'readyState', { configurable: true, get: () => ready });
    request = spyOn(pip, 'requestPictureInPicture').and.callFake(async () => {
      calls.push('pip-request');
      current = pip;
      pip.dispatchEvent(new Event('enterpictureinpicture'));
      return {} as PictureInPictureWindow;
    });
    spyOn(document, 'exitPictureInPicture').and.callFake(async () => {
      current = null;
      pip.dispatchEvent(new Event('leavepictureinpicture'));
    });
  });

  afterEach(async () => {
    await service.exit();
    source.remove();
    pip.remove();
    if (descriptor) Object.defineProperty(document, 'pictureInPictureElement', descriptor);
    else delete (document as unknown as Record<string, unknown>)['pictureInPictureElement'];
  });

  it('finishes the first click after metadata arrives and only plays the floating video', async () => {
    const entering = service.enter(source);
    await service.enter(source);
    expect(service.entering()).toBeTrue();
    expect(request).not.toHaveBeenCalled();
    ready = HTMLMediaElement.HAVE_METADATA;
    pip.dispatchEvent(new Event('loadedmetadata'));
    await entering;
    expect(request).toHaveBeenCalledTimes(1);
    expect(source.paused).toBeTrue();
    expect(pip.paused).toBeFalse();
    expect(pip.currentTime).toBe(23);
    expect(pip.volume).toBe(.4);
    expect(pip.playbackRate).toBe(1.5);
    expect(calls.indexOf('source-pause')).toBeLessThan(calls.indexOf('pip-play'));
    expect(service.active()).toBeTrue();
    expect(service.entering()).toBeFalse();
  });

  it('returns position and playing state to the main player when the window closes', async () => {
    ready = HTMLMediaElement.HAVE_METADATA;
    await service.enter(source);
    pip.currentTime = 41;
    pip.volume = .2;
    await service.exit();
    expect(source.currentTime).toBe(41);
    expect(source.volume).toBe(.2);
    expect(source.paused).toBeFalse();
    expect(pip.paused).toBeTrue();
    expect(service.active()).toBeFalse();
  });

  it('keeps a paused video paused when entering PiP', async () => {
    ready = HTMLMediaElement.HAVE_METADATA;
    paused.set(source, true);
    await service.enter(source);
    expect(play).not.toHaveBeenCalled();
    expect(pip.paused).toBeTrue();
  });

  it('leaves the main player running when loading metadata fails', async () => {
    const entering = service.enter(source);
    const assertion = expectAsync(entering).toBeRejected();
    pip.dispatchEvent(new Event('error'));
    await assertion;
    expect(request).not.toHaveBeenCalled();
    expect(source.paused).toBeFalse();
    expect(service.entering()).toBeFalse();
  });

  it('resumes the main player when the browser rejects PiP', async () => {
    ready = HTMLMediaElement.HAVE_METADATA;
    request.and.rejectWith(new Error('denied'));
    await expectAsync(service.enter(source)).toBeRejected();
    expect(source.paused).toBeFalse();
    expect(pip.paused).toBeTrue();
    expect(service.active()).toBeFalse();
  });

  it('cancels an unfinished entry when PiP is exited', async () => {
    const entering = service.enter(source);
    await service.exit();
    ready = HTMLMediaElement.HAVE_METADATA;
    pip.dispatchEvent(new Event('loadedmetadata'));
    await entering;
    expect(request).not.toHaveBeenCalled();
    expect(service.active()).toBeFalse();
  });
});
