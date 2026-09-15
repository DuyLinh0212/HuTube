import { Component, computed, inject, signal } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { ChannelDetail, ChannelService } from '../../core/channel.service';
import { AuthService, errorMessage } from '../../core/auth.service';
import { ContentService, VideoDetail } from '../../core/content.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

export interface ChannelLink {
  platform?: 'facebook' | 'instagram' | 'tiktok' | 'x' | 'other';
  title: string;
  url: string;
}

type ChannelTab = 'home' | 'videos' | 'playlists';

@Component({
  selector: 'app-channel-page',
  imports: [LocaleDatePipe, LocaleNumberPipe, RouterLink, TranslatePipe],
  templateUrl: './channel-page.html',
  styleUrl: './channel-page.scss'
})
export class ChannelPage {
  private route = inject(ActivatedRoute);
  private channelService = inject(ChannelService);
  private contentService = inject(ContentService);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);

  readonly channel = signal<ChannelDetail | null>(null);
  readonly activeTab = signal<ChannelTab>('home');
  readonly loading = signal(true);
  readonly error = signal('');
  readonly isSubscribed = signal(false);
  readonly videos = signal<VideoDetail[]>([]);
  readonly channelLinks = signal<ChannelLink[]>([]);
  readonly showInfoModal = signal(false);
  readonly shareCopied = signal(false);

  readonly firstLink = computed(() => this.channelLinks()[0] ?? null);
  readonly otherLinksCount = computed(() => Math.max(0, this.channelLinks().length - 1));

  readonly totalViews = computed(() => {
    const vids = this.videos();
    return vids.reduce((acc, v) => acc + (v.stats?.views || 0), 0);
  });

  constructor() {
    this.route.paramMap.subscribe(params => {
      const handle = params.get('handle');
      if (handle) {
        this.loadChannel(handle);
      }
    });
  }

  loadChannel(handle: string) {
    this.loading.set(true);
    this.error.set('');

    this.channelService.getChannel(handle).pipe(finalize(() => this.loading.set(false))).subscribe({
      next: ch => {
        this.channel.set(ch);
        this.parseLinks(ch);
        if (ch.isOwner) {
          this.contentService.managed(ch.channelId, 1, 50).subscribe(page => this.videos.set(page.items));
        }
      },
      error: err => this.error.set(errorMessage(err, this.i18n) || this.i18n.t('channel.notFound'))
    });
  }

  private parseLinks(ch: ChannelDetail) {
    try {
      const settingsData = typeof ch.settings === 'string' ? JSON.parse(ch.settings || '{}') : (ch.settings || {});
      if (Array.isArray(settingsData?.links)) {
        this.channelLinks.set(settingsData.links.filter((l: any) => l.title && l.url).map((l: any) => ({ ...l, platform: this.platformFrom(l.url, l.platform) })));
        return;
      }
    } catch {}

    const local = localStorage.getItem('hutube_channel_links_' + ch.channelId);
    if (local) {
      try {
        const parsedLocal = JSON.parse(local);
        if (Array.isArray(parsedLocal)) {
          this.channelLinks.set(parsedLocal.filter((l: any) => l.title && l.url).map((l: any) => ({ ...l, platform: this.platformFrom(l.url, l.platform) })));
          return;
        }
      } catch {}
    }
    this.channelLinks.set([]);
  }

  setTab(tab: ChannelTab) {
    this.activeTab.set(tab);
  }

  toggleSubscribe() {
    this.isSubscribed.set(!this.isSubscribed());
  }

  openInfoModal() {
    this.showInfoModal.set(true);
  }

  closeInfoModal() {
    this.showInfoModal.set(false);
  }

  copyShareLink() {
    const ch = this.channel();
    if (!ch) return;
    const url = window.location.origin + '/channel/' + ch.handle;
    navigator.clipboard.writeText(url).then(() => {
      this.shareCopied.set(true);
      setTimeout(() => this.shareCopied.set(false), 2500);
    }).catch(() => {});
  }

  reportChannel() {
    alert(this.i18n.t('channel.reportSuccess'));
  }

  getBrandType(url: string, platform?: ChannelLink['platform']): 'facebook' | 'instagram' | 'tiktok' | 'twitter' | 'youtube' | 'generic' {
    if (platform === 'facebook' || platform === 'instagram' || platform === 'tiktok') return platform;
    if (platform === 'x') return 'twitter';
    const lower = url.toLowerCase();
    if (lower.includes('facebook.com') || lower.includes('fb.com')) return 'facebook';
    if (lower.includes('instagram.com')) return 'instagram';
    if (lower.includes('tiktok.com')) return 'tiktok';
    if (lower.includes('twitter.com') || lower.includes('x.com')) return 'twitter';
    if (lower.includes('youtube.com') || lower.includes('hutube.vn')) return 'youtube';
    return 'generic';
  }

  visibilityLabel(value: string): string {
    if (value === 'public') return this.i18n.t('ui.public');
    if (value === 'unlisted') return this.i18n.t('ui.unlisted');
    return this.i18n.t('ui.private');
  }

  private platformFrom(url: string, value?: string): ChannelLink['platform'] {
    if (value === 'facebook' || value === 'instagram' || value === 'tiktok' || value === 'x' || value === 'other') return value;
    const lower = String(url || '').toLowerCase();
    if (lower.includes('facebook.com') || lower.includes('fb.me')) return 'facebook';
    if (lower.includes('instagram.com')) return 'instagram';
    if (lower.includes('tiktok.com')) return 'tiktok';
    if (lower.includes('twitter.com') || lower.includes('x.com')) return 'x';
    return 'other';
  }

  formatUrl(url: string): string {
    if (!url) return '';
    if (/^https?:\/\//i.test(url)) return url;
    return 'https://' + url;
  }
}
