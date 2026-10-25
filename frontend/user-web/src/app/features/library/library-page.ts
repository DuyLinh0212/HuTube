import { ResultNoticeComponent } from '@dalitu/ui/result-notice.component';
import { AfterViewInit, Component, computed, ElementRef, inject, OnDestroy, signal, ViewChild } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { finalize } from 'rxjs';
import { ContentService, LibraryVideo, WatchHistoryItem } from '../../core/content.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

type LibraryMode = 'history' | 'liked';

type LibraryGroup = {
  key: string;
  label: string;
  items: Array<LibraryVideo | WatchHistoryItem>;
};

@Component({
  selector: 'app-library-page',
  imports: [ResultNoticeComponent, FormsModule, LocaleDatePipe, LocaleNumberPipe, RouterLink, TranslatePipe],
  templateUrl: './library-page.html',
  styleUrl: './library-page.scss'
})
export class LibraryPage implements AfterViewInit, OnDestroy {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly content = inject(ContentService);
  readonly i18n = inject(I18nService);

  readonly mode: LibraryMode = this.route.snapshot.data['library'] === 'liked' ? 'liked' : 'history';
  readonly items = signal<Array<LibraryVideo | WatchHistoryItem>>([]);
  readonly loading = signal(true);
  readonly error = signal('');
  readonly loadMoreError = signal(false);
  readonly loadingMore = signal(false);
  readonly page = signal(1);
  readonly pageSize = 20;
  readonly total = signal(0);
  readonly ratingFilter = signal<number | null>(null);
  historyQuery = '';
  historySort = 'newest';
  historyDateRange = 'all';
  private requestVersion = 0;
  private observer?: IntersectionObserver;
  private loadMoreSentinel?: HTMLElement;
  private historySearchTimer?: ReturnType<typeof setTimeout>;
  private loadingMoreInFlight = false;
  readonly pageCount = computed(() => Math.max(1, Math.ceil(this.total() / this.pageSize)));
  readonly hasMoreHistory = computed(() => !this.isLiked && this.page() * this.pageSize < this.total());
  readonly groups = computed<LibraryGroup[]>(() => {
    const items = this.items();
    if (this.isLiked) return items.length ? [{ key: 'liked', label: '', items }] : [];

    const grouped = new Map<string, Array<LibraryVideo | WatchHistoryItem>>();
    for (const item of items) {
      const date = new Date(item.activityAt);
      if (!Number.isFinite(date.getTime())) continue;
      const key = this.historyDayKey(date);
      const dayItems = grouped.get(key) ?? [];
      dayItems.push(item);
      grouped.set(key, dayItems);
    }

    const locale = this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US';
    return [...grouped.entries()].map(([key, dayItems]) => ({
      key,
      label: this.historyDayLabel(key, locale),
      items: dayItems
    }));
  });

  @ViewChild('historyLoadSentinel')
  set historyLoadSentinelRef(value: ElementRef<HTMLElement> | undefined) {
    this.loadMoreSentinel = value?.nativeElement;
    this.observeHistorySentinel();
  }

  constructor() {
    if (this.isLiked) this.load();
    else this.route.queryParamMap.subscribe(params => {
      this.historyQuery = params.get('q') ?? '';
      this.historySort = params.get('sort') === 'oldest' ? 'oldest' : 'newest';
      this.historyDateRange = ['today', 'week', 'month'].includes(params.get('dateRange') ?? '') ? params.get('dateRange')! : 'all';
      this.page.set(1);
      this.load();
    });
  }

  ngAfterViewInit() {
    if (typeof IntersectionObserver === 'undefined') {
      return;
    }
    this.observer = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) void this.loadMoreHistory();
    }, { rootMargin: '560px 0px' });
    this.observeHistorySentinel();
  }

  ngOnDestroy() {
    this.requestVersion++;
    if (this.historySearchTimer) clearTimeout(this.historySearchTimer);
    this.observer?.disconnect();
  }

  get isLiked() {
    return this.mode === 'liked';
  }

  get supportsIntersectionObserver() {
    return typeof IntersectionObserver !== 'undefined';
  }

  get title() {
    return this.i18n.t(this.isLiked ? 'nav.likedVideos' : 'nav.history');
  }

  load() {
    const version = ++this.requestVersion;
    this.loadingMoreInFlight = false;
    this.loadingMore.set(false);
    this.loadMoreError.set(false);
    this.loading.set(true);
    this.error.set('');
    const request = this.isLiked
      ? this.content.liked(this.ratingFilter(), this.page(), this.pageSize)
      : this.content.history(this.page(), this.pageSize, null, { q: this.historyQuery, sort: this.historySort, dateRange: this.historyDateRange });
    request.pipe(finalize(() => { if (version === this.requestVersion) this.loading.set(false); })).subscribe({
      next: result => {
        if (version !== this.requestVersion) return;
        this.items.set(result.items ?? []);
        this.total.set(result.total ?? 0);
      },
      error: () => {
        if (version !== this.requestVersion) return;
        this.items.set([]);
        this.total.set(0);
        this.error.set(this.i18n.t('library.loadError'));
      }
    });
  }

  filterHistory(debounce = false) {
    if (this.historySearchTimer) clearTimeout(this.historySearchTimer);
    const navigate = () => void this.router.navigate([], { relativeTo: this.route, queryParamsHandling: 'merge',
      queryParams: { q: this.historyQuery.trim() || null, sort: this.historySort, dateRange: this.historyDateRange, page: null } });
    if (debounce) this.historySearchTimer = setTimeout(navigate, 300);
    else navigate();
  }

  loadMoreHistory() {
    if (this.isLiked || this.loading() || this.loadingMoreInFlight || !this.hasMoreHistory()) return;
    const version = this.requestVersion;
    const nextPage = this.page() + 1;
    this.loadingMoreInFlight = true;
    this.loadMoreError.set(false);
    this.loadingMore.set(true);
    if (this.loadMoreSentinel) this.observer?.unobserve(this.loadMoreSentinel);

    this.content.history(nextPage, this.pageSize, null, {
      q: this.historyQuery, sort: this.historySort, dateRange: this.historyDateRange
    }).pipe(finalize(() => {
      if (version !== this.requestVersion) return;
      this.loadingMore.set(false);
      this.loadingMoreInFlight = false;
      this.observeHistorySentinel();
    })).subscribe({
      next: result => {
        if (version !== this.requestVersion) return;
        const current = this.items();
        const knownIds = new Set(current.map(item => item.videoId));
        const additions = (result.items ?? []).filter(item => !knownIds.has(item.videoId));
        this.items.set([...current, ...additions]);
        this.page.set(nextPage);
        this.total.set(result.items?.length ? (result.total ?? this.total()) : current.length);
      },
      error: () => {
        if (version !== this.requestVersion) return;
        this.loadMoreError.set(true);
      }
    });
  }

  private observeHistorySentinel() {
    if (this.observer && this.loadMoreSentinel && !this.loadingMore() && !this.loadMoreError() && this.hasMoreHistory()) {
      this.observer.observe(this.loadMoreSentinel);
    }
  }

  setRatingFilter(value: number | null) {
    if (this.ratingFilter() === value) return;
    this.ratingFilter.set(value);
    this.page.set(1);
    this.load();
  }

  goToPage(page: number) {
    const next = Math.max(1, Math.min(this.pageCount(), page));
    if (next === this.page()) return;
    if (!this.isLiked) {
      void this.router.navigate([], { relativeTo: this.route, queryParamsHandling: 'merge', queryParams: { page: next } });
    } else {
      this.page.set(next);
      this.load();
    }
  }

  duration(value: number) {
    const seconds = Math.max(0, Math.floor(value || 0));
    if (seconds >= 3600) return `${Math.floor(seconds / 3600)}:${String(Math.floor(seconds / 60) % 60).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
    return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
  }

  progressLabel(item: LibraryVideo | WatchHistoryItem) {
    return `${Math.round(item.progress || 0)}%`;
  }

  hasVisibilityChip(item: LibraryVideo | WatchHistoryItem) {
    const visibility = String(item.visibility ?? '').trim().toLowerCase();
    return visibility.length > 0 && visibility !== 'public' && visibility !== 'undefined' && visibility !== 'null';
  }

  private historyDayKey(date: Date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }

  private historyDayLabel(key: string, locale: string) {
    const [year, month, day] = key.split('-').map(Number);
    const date = new Date(year, month - 1, day);
    return new Intl.DateTimeFormat(locale, {
      weekday: 'long',
      day: 'numeric',
      month: 'long',
      year: 'numeric'
    }).format(date);
  }

  ratingLabel(item: LibraryVideo | WatchHistoryItem) {
    return item.myRating ? `${item.myRating}/5 sao` : this.i18n.t('library.notRated');
  }
}
