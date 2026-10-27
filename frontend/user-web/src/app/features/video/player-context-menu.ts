import { Component, DestroyRef, EventEmitter, HostListener, Input, Output, inject, signal } from '@angular/core';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';
import { Rendition } from '../../core/content.service';

@Component({
  selector: 'app-player-context-menu',
  imports: [TranslatePipe],
  templateUrl: './player-context-menu.html',
  styleUrl: './player-context-menu.scss',
})
export class PlayerContextMenu {
  @Input() videoId = '';
  @Input() player: HTMLVideoElement | null = null;
  @Input() rendition: Rendition | null = null;
  @Output() pip = new EventEmitter<void>();
  @Output() message = new EventEmitter<string>();

  private readonly i18n = inject(I18nService);
  readonly open = signal(false);
  readonly statsOpen = signal(false);
  readonly looping = signal(false);
  readonly position = signal({ x: 0, y: 0 });
  readonly stats = signal<{ label: string; value: string }[]>([]);
  private timer: ReturnType<typeof setInterval> | null = null;

  constructor() {
    this.i18n.registerTranslations({
      vi: {
        'playerMenu.loop': 'Vòng lặp', 'playerMenu.pip': 'Trình phát thu nhỏ',
        'playerMenu.url': 'Sao chép URL video', 'playerMenu.timeUrl': 'Sao chép URL tại thời điểm hiện tại',
        'playerMenu.embed': 'Sao chép mã nhúng', 'playerMenu.stats': 'Thống kê chi tiết',
        'playerMenu.close': 'Đóng thống kê', 'playerMenu.copied': 'Đã sao chép vào bộ nhớ tạm.',
        'playerMenu.copyError': 'Không thể sao chép. Vui lòng thử lại.',
        'playerMenu.id': 'Video ID', 'playerMenu.viewport': 'Khung hình', 'playerMenu.frames': 'Khung hình bị rớt / tổng',
        'playerMenu.resolution': 'Độ phân giải hiện tại', 'playerMenu.quality': 'Chất lượng nguồn',
        'playerMenu.volume': 'Âm lượng', 'playerMenu.buffer': 'Bộ đệm còn lại',
        'playerMenu.speed': 'Tốc độ phát', 'playerMenu.time': 'Thời điểm',
        'playerMenu.codec': 'Codec', 'playerMenu.color': 'Không gian màu', 'playerMenu.network': 'Ước tính kết nối',
      },
      en: {
        'playerMenu.loop': 'Loop', 'playerMenu.pip': 'Picture in picture',
        'playerMenu.url': 'Copy video URL', 'playerMenu.timeUrl': 'Copy video URL at current time',
        'playerMenu.embed': 'Copy embed code', 'playerMenu.stats': 'Detailed statistics',
        'playerMenu.close': 'Close statistics', 'playerMenu.copied': 'Copied to clipboard.',
        'playerMenu.copyError': 'Could not copy. Please try again.',
        'playerMenu.id': 'Video ID', 'playerMenu.viewport': 'Viewport', 'playerMenu.frames': 'Dropped / total frames',
        'playerMenu.resolution': 'Current resolution', 'playerMenu.quality': 'Source quality',
        'playerMenu.volume': 'Volume', 'playerMenu.buffer': 'Buffer ahead',
        'playerMenu.speed': 'Playback speed', 'playerMenu.time': 'Time',
        'playerMenu.codec': 'Codec', 'playerMenu.color': 'Color space', 'playerMenu.network': 'Estimated connection',
      },
    });
    inject(DestroyRef).onDestroy(() => this.stopTimer());
  }

  show(event: MouseEvent, stage: HTMLElement) {
    event.preventDefault();
    event.stopPropagation();
    if (!this.player) return;
    const rect = stage.getBoundingClientRect();
    this.position.set({
      x: Math.max(4, Math.min(event.clientX - rect.left, rect.width - Math.min(340, rect.width - 8))),
      y: Math.max(4, Math.min(event.clientY - rect.top, rect.height - Math.min(300, rect.height - 8))),
    });
    this.looping.set(this.player.loop);
    this.open.set(true);
  }

  @HostListener('document:click') closeMenu() { this.open.set(false); }
  @HostListener('document:keydown.escape') escape() { this.open.set(false); }

  toggleLoop() {
    if (this.player) {
      this.player.loop = !this.player.loop;
      this.looping.set(this.player.loop);
    }
    this.open.set(false);
  }

  async copy(kind: 'url' | 'time' | 'embed') {
    const path = kind === 'embed' ? '/embed/' : '/watch/';
    const url = new URL(path + encodeURIComponent(this.videoId), window.location.origin);
    if (kind === 'time') url.searchParams.set('t', String(Math.max(0, Math.floor(this.player?.currentTime ?? 0))));
    const value = kind === 'embed'
      ? `<iframe width="560" height="315" src="${url.href}" title="Dalitu video player" allow="fullscreen; picture-in-picture" allowfullscreen></iframe>`
      : url.href;
    this.open.set(false);
    try {
      await navigator.clipboard.writeText(value);
      this.message.emit(this.i18n.t('playerMenu.copied'));
    } catch {
      this.message.emit(this.i18n.t('playerMenu.copyError'));
    }
  }

  toggleStats() {
    this.open.set(false);
    this.statsOpen.update(value => !value);
    this.stopTimer();
    if (this.statsOpen()) {
      this.refreshStats();
      this.timer = setInterval(() => this.refreshStats(), 1000);
    }
  }

  closeStats() { this.statsOpen.set(false); this.stopTimer(); }
  private stopTimer() { if (this.timer) clearInterval(this.timer); this.timer = null; }

  private refreshStats() {
    const p = this.player;
    if (!p) return;
    const frameInfo = typeof p.getVideoPlaybackQuality === 'function' ? p.getVideoPlaybackQuality() : null;
    const downlink = (navigator as Navigator & { connection?: { downlink?: number } }).connection?.downlink;
    let buffer = 0;
    for (let i = 0; i < p.buffered.length; i++) {
      if (p.buffered.start(i) <= p.currentTime && p.buffered.end(i) >= p.currentTime)
        buffer = p.buffered.end(i) - p.currentTime;
    }
    this.stats.set([
      { label: 'playerMenu.id', value: this.videoId },
      { label: 'playerMenu.viewport', value: `${p.clientWidth} × ${p.clientHeight} @ ${window.devicePixelRatio.toFixed(2)}x` },
      { label: 'playerMenu.frames', value: frameInfo ? `${frameInfo.droppedVideoFrames} / ${frameInfo.totalVideoFrames}` : '—' },
      { label: 'playerMenu.resolution', value: p.videoWidth && p.videoHeight ? `${p.videoWidth} × ${p.videoHeight}` : '—' },
      { label: 'playerMenu.quality', value: this.rendition?.quality || '—' },
      { label: 'playerMenu.codec', value: '—' },
      { label: 'playerMenu.color', value: '—' },
      { label: 'playerMenu.network', value: typeof downlink === 'number' && Number.isFinite(downlink) ? `${downlink} Mbps` : '—' },
      { label: 'playerMenu.volume', value: p.muted ? '0%' : `${Math.round(p.volume * 100)}%` },
      { label: 'playerMenu.buffer', value: `${buffer.toFixed(1)} s` },
      { label: 'playerMenu.speed', value: `${p.playbackRate}x` },
      { label: 'playerMenu.time', value: new Date().toLocaleString() },
    ]);
  }
}
