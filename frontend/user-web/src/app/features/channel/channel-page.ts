import { Component, HostListener, computed, effect, inject, signal } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { ChannelDetail, ChannelService } from '../../core/channel.service';
import { AuthService, errorMessage } from '../../core/auth.service';
import { ContentService, VideoCard, VideoDetail } from '../../core/content.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';
import { PlaylistService, PlaylistSummary } from '../../core/playlist.service';
import { ReportModalComponent } from '../../shared/report-modal/report-modal.component';

export interface ChannelLink {
  platform?: 'facebook' | 'instagram' | 'tiktok' | 'x' | 'other';
  title: string;
  url: string;
}

type ChannelTab = 'home' | 'videos' | 'playlists';

@Component({
  selector: 'app-channel-page',
  imports: [LocaleDatePipe, LocaleNumberPipe, RouterLink, TranslatePipe, ReportModalComponent],
  templateUrl: './channel-page.html',
  styleUrl: './channel-page.scss'
})
export class ChannelPage {
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private channelService = inject(ChannelService);
  private contentService = inject(ContentService);
  private playlistService = inject(PlaylistService);
  private auth = inject(AuthService);
  readonly i18n = inject(I18nService);

  readonly channel = signal<ChannelDetail | null>(null);
  readonly activeTab = signal<ChannelTab>('home');
  readonly loading = signal(true);
  readonly error = signal('');
  readonly isSubscribed = signal(false);
  readonly subscriptionNotificationsEnabled = signal(false);
  readonly subscriptionStatusLoading = signal(true);
  readonly subscriptionBusy = signal(false);
  readonly subscriptionMessage = signal('');
  readonly authReady = signal(false);
  readonly videos = signal<Array<VideoDetail | VideoCard>>([]);
  readonly playlists = signal<PlaylistSummary[]>([]);
  readonly channelLinks = signal<ChannelLink[]>([]);
  readonly showInfoModal = signal(false);
  readonly shareCopied = signal(false);
  readonly reportModalOpen = signal(false);
  readonly reportMenuOpen = signal(false);
  readonly reportTargetId = signal('');
  readonly reportTargetTitle = signal('');

  readonly firstLink = computed(() => this.channelLinks()[0] ?? null);
  readonly otherLinksCount = computed(() => Math.max(0, this.channelLinks().length - 1));

  readonly totalViews = computed(() => {
    const vids = this.videos();
    return vids.reduce((acc, v) => acc + this.videoViews(v), 0);
  });

  constructor() {
    this.auth.restore().subscribe({
      next: () => this.authReady.set(true),
      error: () => this.authReady.set(true)
    });

    this.route.paramMap.subscribe(params => {
      const handle = params.get('handle');
      if (handle) {
        this.loadChannel(handle);
      }
    });

    effect(onCleanup => {
      const channel = this.channel();
      const user = this.auth.user();
      const authReady = this.authReady();
      const channelLoading = this.loading();
      if (!channel || channelLoading || !authReady || !user || channel.isOwner) {
        this.isSubscribed.set(false);
        this.subscriptionNotificationsEnabled.set(false);
        this.subscriptionStatusLoading.set(!!channel && (channelLoading || !authReady));
        return;
      }

      this.subscriptionStatusLoading.set(true);
      const subscription = this.channelService.getSubscriptionStatus(channel.channelId).subscribe({
        next: status => {
          this.isSubscribed.set(status.status === 'active');
          this.subscriptionNotificationsEnabled.set(status.status === 'active' && status.notificationsEnabled);
          this.subscriptionStatusLoading.set(false);
        },
        error: () => {
          this.isSubscribed.set(false);
          this.subscriptionNotificationsEnabled.set(false);
          this.subscriptionStatusLoading.set(false);
        }
      });
      onCleanup(() => subscription.unsubscribe());
    });
  }

  loadChannel(handle: string) {
    this.loading.set(true);
    this.error.set('');
    this.subscriptionMessage.set('');

    this.channelService.getChannel(handle).pipe(finalize(() => this.loading.set(false))).subscribe({
      next: ch => {
        this.channel.set(ch);
        this.parseLinks(ch);
        this.playlistService.publicByChannel(ch.channelId).subscribe({
          next: lists => this.playlists.set(lists),
          error: () => this.playlists.set([])
        });
        // A channel page is always a public surface, including when its owner is
        // viewing it. The manage endpoint also returns rejected, private, and
        // processing videos for Studio, so using it here would expose moderation
        // outcomes in the public catalogue. The search endpoint applies the
        // published + public + approved visibility contract on the server.
        this.contentService.search({ channelId: ch.channelId, sort: 'newest', page: 1, pageSize: 50 })
          .subscribe(page => this.videos.set(page.items));

      },
      error: err => this.error.set(errorMessage(err, this.i18n) || this.i18n.t('channel.notFound'))
    });
  }

  videoViews(video: VideoDetail | VideoCard): number {
    return 'stats' in video ? video.stats.views : video.views;
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
    const ch = this.channel();
    if (!ch || this.subscriptionBusy() || this.subscriptionStatusLoading()) return;
    this.subscriptionMessage.set('');

    if (!this.auth.user()) {
      void this.router.navigate(['/login']);
      return;
    }

    if (ch.isOwner) {
      alert(this.i18n.t('watch.cannotSubscribeSelf'));
      return;
    }

    if (this.isSubscribed()) {
      this.subscriptionBusy.set(true);
      this.channelService.unsubscribe(ch.channelId).pipe(finalize(() => this.subscriptionBusy.set(false))).subscribe({
        next: () => {
          this.isSubscribed.set(false);
          this.subscriptionNotificationsEnabled.set(false);
          this.channel.update(c => c ? { ...c, subscriberCount: Math.max(0, c.subscriberCount - 1) } : c);
        },
        error: () => alert(this.i18n.t('watch.unsubscribeError'))
      });
    } else {
      this.subscriptionBusy.set(true);
      this.channelService.subscribe(ch.channelId).pipe(finalize(() => this.subscriptionBusy.set(false))).subscribe({
        next: status => {
          this.isSubscribed.set(true);
          this.subscriptionNotificationsEnabled.set(status.notificationsEnabled);
          this.channel.update(c => c ? { ...c, subscriberCount: c.subscriberCount + 1 } : c);
        },
        error: () => alert(this.i18n.t('watch.subscribeError'))
      });
    }
  }

  toggleSubscriptionNotifications() {
    const channel = this.channel();
    if (!channel || !this.isSubscribed() || this.subscriptionBusy()) return;
    const enabled = !this.subscriptionNotificationsEnabled();
    this.subscriptionMessage.set('');
    this.subscriptionBusy.set(true);
    this.channelService.updateSubscriptionNotifications(channel.channelId, enabled)
      .pipe(finalize(() => this.subscriptionBusy.set(false)))
      .subscribe({
        next: status => {
          this.subscriptionNotificationsEnabled.set(status.status === 'active' && status.notificationsEnabled);
          this.subscriptionMessage.set(this.i18n.t(enabled ? 'channel.notificationsEnabled' : 'channel.notificationsDisabled'));
        },
        error: error => this.subscriptionMessage.set(errorMessage(error, this.i18n) || this.i18n.t('channel.notificationsUpdateError'))
      });
  }

  openInfoModal() {
    this.showInfoModal.set(true);
  }

  closeInfoModal() {
    this.showInfoModal.set(false);
  }

  toggleReportMenu(event: MouseEvent) {
    event.stopPropagation();
    this.reportMenuOpen.update(v => !v);
  }

  hideUserFromMyChannel() {
    this.reportMenuOpen.set(false);
    alert('Đã ẩn người dùng khỏi kênh của bạn.');
  }

  openChannelReportModal(actionType: string = 'user') {
    const ch = this.channel();
    if (!ch) return;

    if (!this.auth.user()) {
      void this.router.navigate(['/login'], { queryParams: { returnUrl: `/channel/${ch.handle}` } });
      return;
    }

    this.reportMenuOpen.set(false);
    this.showInfoModal.set(false);
    this.reportTargetId.set(ch.channelId);
    this.reportTargetTitle.set(ch.name);
    this.reportModalOpen.set(true);
  }

  reportChannel() {
    this.openChannelReportModal('user');
  }

  @HostListener('document:click')
  onDocumentClick() {
    if (this.reportMenuOpen()) {
      this.reportMenuOpen.set(false);
    }
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
