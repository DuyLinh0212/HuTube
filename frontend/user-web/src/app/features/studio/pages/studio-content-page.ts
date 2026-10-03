import { CommonModule } from '@angular/common';
import { AfterViewInit, Component, ElementRef, OnDestroy, OnInit, ViewChild, effect, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { ContentService, VideoDetail } from '../../../core/content.service';
import { StudioDataService } from '../../../core/studio-data.service';
import { I18nService } from '../../../core/i18n.service';
import { LocaleDatePipe } from '../../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../../core/locale-number.pipe';
import { TranslatePipe } from '../../../core/translate.pipe';

@Component({
  selector: 'app-studio-content-page',
  standalone: true,
  imports: [CommonModule, RouterLink, LocaleDatePipe, LocaleNumberPipe, TranslatePipe],
  templateUrl: './studio-content-page.html',
  styleUrl: './studio-content-page.scss',
})
export class StudioContentPage implements OnInit, AfterViewInit, OnDestroy {
  readonly data = inject(StudioDataService);
  readonly content = inject(ContentService);
  readonly i18n = inject(I18nService);

  readonly videos = signal<VideoDetail[]>([]);
  readonly total = signal(0);
  readonly loading = signal(false);
  readonly hasMore = signal(false);
  readonly error = signal('');
  readonly search = signal('');
  readonly visibilityFilter = signal('all');
  readonly statusFilter = signal('all');
  readonly updatingId = signal<string | null>(null);
  readonly deletingId = signal<string | null>(null);
  readonly pendingDelete = signal<VideoDetail | null>(null);
  readonly toastMessage = signal('');

  @ViewChild('loadMoreSentinel') private loadMoreSentinel?: ElementRef<HTMLDivElement>;

  private readonly pageSize = 20;
  private readonly pageReady = signal(false);
  private currentPage = 0;
  private activeChannelId: string | null = null;
  private requestGeneration = 0;
  private filterTimer?: ReturnType<typeof setTimeout>;
  private toastTimer?: ReturnType<typeof setTimeout>;
  private observer?: IntersectionObserver;

  constructor() {
    effect(() => {
      if (!this.pageReady()) return;
      const channels = this.data.accessibleChannels();
      const channelId = this.data.selectedChannelId();
      if (!channelId || !channels.some(channel => channel.channelId === channelId) || channelId === this.activeChannelId) return;
      this.activeChannelId = channelId;
      this.scheduleReload(0);
    });
  }

  ngOnInit() {
    this.pageReady.set(true);
  }

  ngAfterViewInit() {
    const sentinel = this.loadMoreSentinel?.nativeElement;
    if (!sentinel || typeof IntersectionObserver === 'undefined') return;
    this.observer = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) this.loadNextPage();
    }, { rootMargin: '320px 0px' });
    this.observer.observe(sentinel);
  }

  ngOnDestroy() {
    this.observer?.disconnect();
    if (this.filterTimer) clearTimeout(this.filterTimer);
    if (this.toastTimer) clearTimeout(this.toastTimer);
    this.requestGeneration++;
  }

  hasActiveFilters(): boolean {
    return !!this.search().trim() || this.visibilityFilter() !== 'all' || this.statusFilter() !== 'all';
  }

  onSearchInput(value: string) {
    this.search.set(value);
    this.scheduleReload(300);
  }

  onFilterChange() {
    this.scheduleReload(0);
  }

  clearFilters() {
    this.search.set('');
    this.visibilityFilter.set('all');
    this.statusFilter.set('all');
    this.scheduleReload(0);
  }

  loadNextPage() {
    if (this.loading() || !this.hasMore() || !this.activeChannelId) return;
    this.fetchPage(this.currentPage + 1, this.requestGeneration);
  }

  retryLoading() {
    if (!this.activeChannelId) return;
    const page = Math.max(1, this.currentPage + 1);
    this.error.set('');
    this.hasMore.set(false);
    this.fetchPage(page, this.requestGeneration);
  }

  changeVisibility(video: VideoDetail, newVisibility: string) {
    if (!this.data.hasPermission('video.edit') || newVisibility === video.visibility) return;

    this.updatingId.set(video.videoId);
    this.content.update(video.videoId, { visibility: newVisibility }).subscribe({
      next: updated => {
        this.videos.update(items => items.map(item => item.videoId === video.videoId
          ? { ...item, visibility: updated.visibility || newVisibility, moderationStatus: updated.moderationStatus, status: updated.status }
          : item));
        this.updatingId.set(null);

        if (newVisibility === 'public' && updated.moderationStatus !== 'approved') {
          this.showToast(this.i18n.t('studio.publicModerationToast', { title: video.title }));
        } else if (newVisibility === 'public') {
          this.showToast(this.i18n.t('studio.publicToast', { title: video.title }));
        } else if (newVisibility === 'unlisted') {
          this.showToast(this.i18n.t('studio.unlistedToast', { title: video.title }));
        } else {
          this.showToast(this.i18n.t('studio.privateToast', { title: video.title }));
        }

        if (this.visibilityFilter() !== 'all' && this.visibilityFilter() !== (updated.visibility || newVisibility)) {
          this.scheduleReload(0);
        }
      },
      error: () => {
        this.updatingId.set(null);
        this.showToast(this.i18n.t('studio.visibilityError'));
      },
    });
  }

  visibilityLabel(value: string): string {
    if (value === 'public') return this.i18n.t('ui.public');
    if (value === 'unlisted') return this.i18n.t('ui.unlisted');
    return this.i18n.t('ui.private');
  }

  formatDuration(value: number): string {
    const seconds = Math.max(0, Math.floor(value || 0));
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const remainder = seconds % 60;
    return hours
      ? `${hours}:${String(minutes).padStart(2, '0')}:${String(remainder).padStart(2, '0')}`
      : `${minutes}:${String(remainder).padStart(2, '0')}`;
  }

  moderationLabel(value: string | null | undefined, video: VideoDetail): string {
    if (value === 'approved' || (video.status === 'published' && video.visibility === 'public')) return this.i18n.t('ui.moderationApproved');
    if (value === 'pending' || video.visibility === 'public') return this.i18n.t('ui.moderationPending');
    if (value === 'reviewing') return this.i18n.t('ui.moderationReviewing');
    if (value === 'rejected') return this.i18n.t('ui.moderationRejected');
    return this.i18n.t('ui.moderationNotSubmitted');
  }

  thumbnailFailed(video: VideoDetail) {
    this.videos.update(items => items.map(item => item.videoId === video.videoId ? { ...item, thumbnailUrl: null } : item));
  }

  requestDelete(video: VideoDetail) {
    if (this.data.hasPermission('video.delete')) this.pendingDelete.set(video);
  }

  deletePendingVideo() {
    const video = this.pendingDelete();
    if (!video || !this.data.hasPermission('video.delete') || this.deletingId()) return;
    this.deletingId.set(video.videoId);
    this.content.deleteVideo(video.videoId).subscribe({
      next: () => {
        this.deletingId.set(null);
        this.pendingDelete.set(null);
        this.showToast(this.i18n.t('studio.videoDeleted'));
        this.scheduleReload(0);
      },
      error: () => {
        this.deletingId.set(null);
        this.showToast(this.i18n.t('studio.deleteVideoError'));
      }
    });
  }

  cancelDelete() {
    if (!this.deletingId()) this.pendingDelete.set(null);
  }

  private scheduleReload(delay: number) {
    if (this.filterTimer) clearTimeout(this.filterTimer);
    const generation = ++this.requestGeneration;
    this.loading.set(false);
    this.hasMore.set(false);
    this.filterTimer = setTimeout(() => this.loadFirstPage(generation), delay);
  }

  private loadFirstPage(generation: number) {
    if (generation !== this.requestGeneration) return;
    this.currentPage = 0;
    this.total.set(0);
    this.videos.set([]);
    this.error.set('');
    this.hasMore.set(false);
    if (!this.activeChannelId) return;
    this.fetchPage(1, generation);
  }

  private fetchPage(page: number, generation: number) {
    const channelId = this.activeChannelId;
    if (!channelId || generation !== this.requestGeneration) return;
    this.loading.set(true);
    const search = this.search().trim();
    const visibility = this.visibilityFilter() === 'all' ? '' : this.visibilityFilter();
    const status = this.statusFilter() === 'all' ? '' : this.statusFilter();
    this.content.managed(channelId, page, this.pageSize, search, visibility, status).subscribe({
      next: result => {
        if (generation !== this.requestGeneration) return;
        this.videos.update(items => page === 1 ? result.items : [...items, ...result.items]);
        this.currentPage = result.page;
        this.total.set(result.total);
        this.hasMore.set(result.page * result.pageSize < result.total);
        this.loading.set(false);
        this.error.set('');
      },
      error: () => {
        if (generation !== this.requestGeneration) return;
        this.loading.set(false);
        this.hasMore.set(false);
        this.error.set(this.i18n.t('studio.loadVideosError'));
      }
    });
  }

  private showToast(message: string) {
    this.toastMessage.set(message);
    if (this.toastTimer) clearTimeout(this.toastTimer);
    this.toastTimer = setTimeout(() => this.toastMessage.set(''), 5000);
  }
}
