import { Injectable, signal } from '@angular/core';

@Injectable({ providedIn: 'root' })
export class PictureInPictureService {
  readonly active = signal(false);
  readonly entering = signal(false);

  private pipVideo: HTMLVideoElement | null = null;
  private sourcePlayer: HTMLVideoElement | null = null;
  private pendingTime = 0;
  private requestVersion = 0;

  supports(player: HTMLVideoElement | null | undefined): boolean {
    return !!document.pictureInPictureEnabled
      && !!player
      && !player.disablePictureInPicture
      && typeof player.requestPictureInPicture === 'function';
  }

  prepare(player: HTMLVideoElement): void {
    if (this.active()) return;
    const source = player.currentSrc || player.src;
    if (!source) return;
    const pipVideo = this.ensureVideo();
    pipVideo.disablePictureInPicture = player.disablePictureInPicture;
    if (pipVideo.src === source) return;
    pipVideo.src = source;
    pipVideo.load();
  }

  async enter(player: HTMLVideoElement): Promise<void> {
    if (this.entering() || this.active()) return;
    this.entering.set(true);
    const version = ++this.requestVersion;
    const pipVideo = this.ensureVideo();
    let resumeSource = false;
    try {
      if (!(player.currentSrc || player.src)) throw new Error('Picture-in-picture source is unavailable.');
      this.prepare(player);
      // Metadata can still be loading when the first click arrives. Complete
      // that same request instead of making the user click again.
      if (pipVideo.readyState < HTMLMediaElement.HAVE_METADATA) await this.waitForMetadata(pipVideo);
      if (version !== this.requestVersion) return;

      this.sourcePlayer = player;
      this.pendingTime = Number.isFinite(player.currentTime) ? player.currentTime : 0;
      pipVideo.poster = player.poster;
      pipVideo.muted = player.muted;
      pipVideo.volume = player.volume;
      pipVideo.playbackRate = player.playbackRate;
      this.applyPendingTime(pipVideo);
      resumeSource = !player.paused;
      player.pause();
      await pipVideo.requestPictureInPicture();
      if (version !== this.requestVersion) { await this.exit(); return; }
      if (resumeSource) await pipVideo.play();
      this.active.set(true);
    } catch (error) {
      await this.exit();
      if (resumeSource && player.isConnected) void player.play().catch(() => {});
      throw error;
    } finally {
      this.entering.set(false);
    }
  }

  async exit(): Promise<void> {
    ++this.requestVersion;
    const pipVideo = this.pipVideo;
    if (!pipVideo) return;
    if (this.isPictureInPictureActive(pipVideo)) {
      await document.exitPictureInPicture();
    } else {
      this.cleanupSource();
    }
    this.active.set(false);
  }

  private ensureVideo(): HTMLVideoElement {
    if (this.pipVideo) return this.pipVideo;

    const video = document.createElement('video');
    video.className = 'global-picture-in-picture-video';
    video.setAttribute('aria-hidden', 'true');
    video.setAttribute('playsinline', '');
    video.tabIndex = -1;
    video.preload = 'metadata';
    Object.assign(video.style, {
      position: 'fixed',
      top: '-10000px',
      left: '-10000px',
      width: '320px',
      height: '180px',
      opacity: '0.01',
      pointerEvents: 'none'
    });
    video.addEventListener('enterpictureinpicture', () => this.active.set(true));
    video.addEventListener('leavepictureinpicture', () => {
      this.active.set(false);
      this.syncSource();
      this.cleanupSource();
    });
    video.addEventListener('timeupdate', () => this.syncSourceTime());
    video.addEventListener('volumechange', () => this.syncSourceVolume());
    document.body.appendChild(video);
    this.pipVideo = video;
    return video;
  }

  private waitForMetadata(video: HTMLVideoElement): Promise<void> {
    if (video.readyState >= HTMLMediaElement.HAVE_METADATA) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const cleanup = () => {
        clearTimeout(timeout);
        video.removeEventListener('loadedmetadata', ready);
        video.removeEventListener('error', failed);
      };
      const ready = () => { cleanup(); resolve(); };
      const failed = () => { cleanup(); reject(new Error('Picture-in-picture source could not load.')); };
      const timeout = setTimeout(failed, 10_000);
      video.addEventListener('loadedmetadata', ready, { once: true });
      video.addEventListener('error', failed, { once: true });
    });
  }

  private applyPendingTime(video: HTMLVideoElement) {
    if (!Number.isFinite(this.pendingTime)) return;
    const duration = Number.isFinite(video.duration) ? video.duration : 0;
    video.currentTime = duration > 0 ? Math.min(this.pendingTime, duration) : this.pendingTime;
  }

  private syncSourceTime() {
    const source = this.sourcePlayer;
    const video = this.pipVideo;
    if (!source || !source.isConnected || !video || !Number.isFinite(video.currentTime)) return;
    if (Math.abs(source.currentTime - video.currentTime) > 0.25) source.currentTime = video.currentTime;
  }

  private syncSourceVolume() {
    const source = this.sourcePlayer;
    const video = this.pipVideo;
    if (!source || !source.isConnected || !video) return;
    source.muted = video.muted;
    source.volume = video.volume;
  }

  private syncSource() {
    this.syncSourceTime();
    this.syncSourceVolume();
    const source = this.sourcePlayer;
    const video = this.pipVideo;
    if (source && source.isConnected && video) {
      if (video.paused) source.pause();
      else void source.play();
    }
  }

  private cleanupSource() {
    this.sourcePlayer = null;
    this.pendingTime = 0;
    const video = this.pipVideo;
    if (!video || this.isPictureInPictureActive(video)) return;
    video.pause();
    video.removeAttribute('src');
    video.load();
  }

  private isPictureInPictureActive(video: HTMLVideoElement): boolean {
    return document.pictureInPictureElement === video || video.matches(':picture-in-picture');
  }
}
