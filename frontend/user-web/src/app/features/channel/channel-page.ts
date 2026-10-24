import { ResultNoticeComponent } from '@dalitu/ui/result-notice.component';
import { FeedbackService } from '@dalitu/ui/feedback.service';
import { NgTemplateOutlet } from '@angular/common';
import { Component, DestroyRef, ElementRef, HostListener, computed, effect, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { Subscription, catchError, finalize, forkJoin, of } from 'rxjs';
import { ChannelDetail, ChannelService } from '../../core/channel.service';
import { LoginPromptService } from '../../core/login-prompt.service';
import { RequireLoginDirective } from '../../shared/login-prompt/require-login.directive';
import { AuthService, errorMessage } from '../../core/auth.service';
import { ContentService, VideoCard, VideoDetail } from '../../core/content.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';
import { PlaylistItem, PlaylistService, PlaylistSummary } from '../../core/playlist.service';
import { NetworkStatusService } from '../../core/network/network-status.service';
import { ReportModalComponent } from '../../shared/report-modal/report-modal.component';
import { VideoPlaylistMenuComponent } from '../../shared/video-playlist-menu/video-playlist-menu.component';

export interface ChannelLink {
  platform?: 'facebook' | 'instagram' | 'tiktok' | 'x' | 'other';
  title: string;
  url: string;
}

type ChannelTab = 'home' | 'videos' | 'playlists';

@Component({
  selector: 'app-channel-page',
  imports: [ResultNoticeComponent, RequireLoginDirective, FormsModule, NgTemplateOutlet, LocaleDatePipe, LocaleNumberPipe, RouterLink, TranslatePipe, ReportModalComponent, VideoPlaylistMenuComponent],
  templateUrl: './channel-page.html',
  styleUrl: './channel-page.scss'
})
export class ChannelPage {
  private readonly feedback = inject(FeedbackService);
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private channelService = inject(ChannelService);
  private contentService = inject(ContentService);
  private playlistService = inject(PlaylistService);
  private auth = inject(AuthService);
  private readonly loginPrompt = inject(LoginPromptService);
  private networkStatus = inject(NetworkStatusService);
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
  readonly videos = signal<VideoCard[]>([]);
  readonly popularVideos = signal<VideoCard[]>([]);
  readonly videosLoading = signal(true);
  readonly videosError = signal(false);
  readonly popularError = signal(false);
  readonly playlistsLoading = signal(true);
  readonly playlistsError = signal(false);
  readonly featuredDescription = signal('');
  readonly videoSort = signal('newest');
  videoQuery = '';
  readonly videoPage = signal(1);
  readonly videoPageSize = signal(20);
  readonly videoPageCount = computed(() => Math.max(1, Math.ceil(this.videoTotal() / this.videoPageSize())));
  readonly videoResults = signal<VideoCard[]>([]);
  readonly videoResultsLoading = signal(false);
  readonly videoResultsError = signal(false);
  private videoRequestVersion = 0;
  readonly videoTotal = signal(0);
  readonly loadingMore = signal(false);
  readonly loadMoreError = signal(false);
  readonly featuredVideo = computed(() => this.popularVideos()[0] ?? null);
  readonly latestVideos = computed(() => this.videos().slice(0, 4));
  readonly popularPreview = computed(() => this.popularVideos().slice(1, 5));
  readonly featuredPlaylists = computed(() => this.playlists().filter(list => list.itemCount > 0).slice(0, 4));
  readonly tabVideos = this.videoResults;
  readonly playlists = signal<PlaylistSummary[]>([]);
  readonly playlistPreviewById = signal<Record<string, PlaylistItem[]>>({});
  readonly channelLinks = signal<ChannelLink[]>([]);
  readonly showInfoModal = signal(false);
  readonly shareCopied = signal(false);
  readonly reportModalOpen = signal(false);
  readonly reportMenuOpen = signal(false);
  readonly reportTargetId = signal('');
  readonly reportTargetTitle = signal('');
  private pendingHandle: string | null = null;
  private networkWasUnavailable = false;
  private channelRequests = new Subscription();
  private readonly destroyRef = inject(DestroyRef);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);

  readonly firstLink = computed(() => this.channelLinks()[0] ?? null);
  readonly otherLinksCount = computed(() => Math.max(0, this.channelLinks().length - 1));

  readonly totalViews = computed(() => {
    const vids = this.videos();
    return vids.reduce((acc, v) => acc + this.videoViews(v), 0);
  });

  constructor() {
    this.destroyRef.onDestroy(() => this.channelRequests.unsubscribe());
    this.route.queryParamMap.pipe(takeUntilDestroyed()).subscribe(params => {
      this.videoQuery = params.get('q') ?? '';
      this.videoSort.set(['newest', 'views', 'engagement', 'relevance'].includes(params.get('sort') ?? '') ? params.get('sort')! : 'newest');
      this.videoPageSize.set(params.get('pageSize') === '50' ? 50 : 20);
      const page = Number(params.get('page'));
      this.videoPage.set(Number.isSafeInteger(page) && page > 0 ? page : 1);
      const tab = params.get('tab');
      if (tab === 'home' || tab === 'videos' || tab === 'playlists') this.activeTab.set(tab);
      if (this.channel() && this.activeTab() === 'videos') this.loadVideos();
    });

    effect(() => {
      const unavailable = this.networkStatus.unavailable();
      const hasError = !!this.error();
      if (unavailable) {
        this.networkWasUnavailable = true;
      } else if (this.networkWasUnavailable && hasError && this.pendingHandle) {
        this.networkWasUnavailable = false;
        this.loadChannel(this.pendingHandle);
      }
    });

    this.auth.restore().pipe(takeUntilDestroyed()).subscribe({
      next: () => {
        this.authReady.set(true);
        if (this.pendingHandle) this.loadChannel(this.pendingHandle);
      },
      error: () => {
        this.authReady.set(true);
        if (this.pendingHandle) this.loadChannel(this.pendingHandle);
      }
    });

    this.route.paramMap.pipe(takeUntilDestroyed()).subscribe(params => {
      const handle = params.get('handle');
      if (handle) {
        const tab = this.route.snapshot.queryParamMap.get('tab');
        this.activeTab.set(tab === 'videos' || tab === 'playlists' ? tab : 'home');
        this.pendingHandle = handle;
        if (this.authReady()) this.loadChannel(handle);
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

  retryChannel() {
    if (this.pendingHandle) this.loadChannel(this.pendingHandle);
  }

  loadChannel(handle: string) {
    this.channelRequests.unsubscribe();
    this.channelRequests = new Subscription();
    this.loading.set(true);
    this.error.set('');
    this.subscriptionMessage.set('');
    this.videos.set([]);
    this.popularVideos.set([]);
    this.featuredDescription.set('');
    this.playlists.set([]);
    this.playlistPreviewById.set({});
    this.videosLoading.set(true);
    this.playlistsLoading.set(true);
    this.videosError.set(false);
    this.popularError.set(false);
    this.playlistsError.set(false);
    this.videoTotal.set(0);
    this.loadingMore.set(false);
    this.loadMoreError.set(false);

    this.channelRequests.add(this.channelService.getChannel(handle).pipe(finalize(() => this.loading.set(false))).subscribe({
      next: ch => {
        this.channel.set(ch);
        this.parseLinks(ch);
        this.channelRequests.add(this.playlistService.publicByChannel(ch.channelId)
          .pipe(finalize(() => this.playlistsLoading.set(false))).subscribe({
          next: lists => {
            this.playlists.set(lists);
            this.loadPlaylistPreviews(lists);
          },
          error: () => {
            this.playlistsError.set(true);
            this.playlists.set([]);
            this.playlistPreviewById.set({});
          }
        }));
        // A channel page is always a public surface, including when its owner is
        // viewing it. The manage endpoint also returns rejected, private, and
        // processing videos for Studio, so using it here would expose moderation
        // outcomes in the public catalogue. The search endpoint applies the
        // published + public + approved visibility contract on the server.
        this.channelRequests.add(forkJoin({
          latest: this.contentService.search({ channelId: ch.channelId, sort: 'newest', page: 1, pageSize: 50 })
            .pipe(catchError(() => { this.videosError.set(true); return of(null); })),
          popular: this.contentService.search({ channelId: ch.channelId, sort: 'views', page: 1, pageSize: 50 })
            .pipe(catchError(() => { this.popularError.set(true); return of(null); })),
        }).pipe(finalize(() => this.videosLoading.set(false))).subscribe(({ latest, popular }) => {
          this.videos.set(latest?.items ?? []);
          this.popularVideos.set(popular?.items ?? []);
          const featured = popular?.items[0];
          if (featured) {
            this.channelRequests.add(this.contentService.detail(featured.videoId).pipe(catchError(() => of(null)))
              .subscribe(detail => this.featuredDescription.set(detail?.description?.trim() ?? '')));
          }
        }));
        if (this.activeTab() === 'videos') this.loadVideos();

      },
      error: err => this.error.set(errorMessage(err, this.i18n) || this.i18n.t('channel.notFound'))
    }));
  }

  videoViews(video: VideoDetail | VideoCard): number {
    return 'stats' in video ? video.stats.views : video.views;
  }

  loadVideos() {
    const channel = this.channel();
    if (!channel) return;
    const version = ++this.videoRequestVersion;
    this.videoResultsLoading.set(true); this.videoResultsError.set(false);
    this.channelRequests.add(this.contentService.search({ channelId: channel.channelId, q: this.videoQuery, sort: this.videoSort(),
      page: this.videoPage(), pageSize: this.videoPageSize() }).pipe(finalize(() => {
        if (version === this.videoRequestVersion) this.videoResultsLoading.set(false);
      })).subscribe({
        next: result => { if (version === this.videoRequestVersion) { this.videoResults.set(result.items); this.videoTotal.set(result.total); } },
        error: () => { if (version === this.videoRequestVersion) { this.videoResults.set([]); this.videoTotal.set(0); this.videoResultsError.set(true); } }
      }));
  }

  filterVideos(pageSize = this.videoPageSize()) {
    void this.router.navigate([], { relativeTo: this.route, queryParamsHandling: 'merge', queryParams: {
      tab: 'videos', q: this.videoQuery || null, sort: this.videoSort(), page: 1, pageSize } });
  }

  changeVideoPage(page: number) {
    void this.router.navigate([], { relativeTo: this.route, queryParamsHandling: 'merge',
      queryParams: { tab: 'videos', page: Math.max(1, Math.min(page, this.videoPageCount())) } });
  }

  private loadPlaylistPreviews(playlists: PlaylistSummary[]) {
    if (playlists.every(list => Array.isArray(list.previewItems))) {
      this.playlistPreviewById.set(Object.fromEntries(playlists.map(list => [list.playlistId, list.previewItems!])));
      return;
    }
    const previewPlaylists = playlists.filter(playlist => playlist.itemCount > 0).slice(0, 12);
    this.playlistPreviewById.set({});
    if (!previewPlaylists.length) return;

    this.channelRequests.add(forkJoin(previewPlaylists.map(playlist =>
      this.playlistService.get(playlist.playlistId).pipe(catchError(() => of(null)))
    )).subscribe(details => {
      const previews: Record<string, PlaylistItem[]> = {};
      previewPlaylists.forEach((playlist, index) => {
        previews[playlist.playlistId] = details[index]?.items
          .filter(item => !!item.thumbnailUrl)
          .slice(0, 4) ?? [];
      });
      this.playlistPreviewById.set(previews);
    }));
  }

  playlistPreviewItems(playlist: PlaylistSummary): PlaylistItem[] {
    return this.playlistPreviewById()[playlist.playlistId] ?? [];
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
    this.host.nativeElement.querySelector('.channel-tabs-bar')?.scrollIntoView({ block: 'nearest' });
    void this.router.navigate([], { relativeTo: this.route, queryParamsHandling: 'merge', queryParams: { tab, sort: this.videoSort() } });
  }

  showAllVideos(sort: 'newest' | 'views') {
    this.videoSort.set(sort);
    this.setTab('videos');
  }

  loadMoreVideos() {
    const channel = this.channel();
    if (!channel || this.loadingMore()) return;
    const sort = this.videoSort();
    const list = sort === 'views' ? this.popularVideos : this.videos;
    this.loadingMore.set(true);
    this.loadMoreError.set(false);
    this.channelRequests.add(this.contentService.search({ channelId: channel.channelId, sort,
      page: Math.floor(list().length / 50) + 1, pageSize: 50 })
      .pipe(finalize(() => this.loadingMore.set(false))).subscribe({
        next: page => { list.update(videos => [...videos, ...page.items]); this.videoTotal.set(page.total); },
        error: () => this.loadMoreError.set(true),
      }));
  }

  formatDuration(value: number): string {
    const seconds = Math.max(0, Math.floor(value || 0));
    const minutes = Math.floor(seconds / 60);
    const remainder = String(seconds % 60).padStart(2, '0');
    return minutes >= 60 ? `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, '0')}:${remainder}` : `${minutes}:${remainder}`;
  }

  toggleSubscribe() {
    const ch = this.channel();
    if (!ch || this.subscriptionBusy() || this.subscriptionStatusLoading()) return;
    this.subscriptionMessage.set('');

    if (!this.auth.user()) {
      this.loginPrompt.require();
      return;
    }

    if (ch.isOwner) {
      this.feedback.warning(this.i18n.t('watch.cannotSubscribeSelf'));
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
        error: () => this.feedback.error(this.i18n.t('watch.unsubscribeError'))
      });
    } else {
      this.subscriptionBusy.set(true);
      this.channelService.subscribe(ch.channelId).pipe(finalize(() => this.subscriptionBusy.set(false))).subscribe({
        next: status => {
          this.isSubscribed.set(true);
          this.subscriptionNotificationsEnabled.set(status.notificationsEnabled);
          this.channel.update(c => c ? { ...c, subscriberCount: c.subscriberCount + 1 } : c);
        },
        error: () => this.feedback.error(this.i18n.t('watch.subscribeError'))
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
    this.feedback.info(this.i18n.t('channel.userHiddenFromChannel'));
  }

  openChannelReportModal(actionType: string = 'user') {
    const ch = this.channel();
    if (!ch) return;

    if (!this.auth.user()) {
      this.loginPrompt.require();
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
