import { AfterViewInit, Component, computed, ElementRef, inject, OnDestroy, signal, ViewChild } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { ContentService, LibraryVideo, WatchHistoryItem } from '../../core/content.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

type LibraryMode = 'history' | 'liked';

@Component({
  selector: 'app-library-page',
  imports: [LocaleDatePipe, LocaleNumberPipe, RouterLink, TranslatePipe],
  templateUrl: './library-page.html',
  styleUrl: './library-page.scss'
})
export class LibraryPage implements AfterViewInit, OnDestroy {
  private readonly route = inject(ActivatedRoute);
  private readonly content = inject(ContentService);
  readonly i18n = inject(I18nService);

  readonly mode: LibraryMode = this.route.snapshot.data['library'] === 'liked' ? 'liked' : 'history';
  readonly items = signal<Array<LibraryVideo | WatchHistoryItem>>([]);
  readonly loading = signal(true);
  readonly error = signal('');
  readonly page = signal(1);
  readonly pageSize = 20;
  readonly total = signal(0);
  readonly ratingFilter = signal<number | null>(null);
  readonly pageCount = computed(() => Math.max(1, Math.ceil(this.total() / this.pageSize)));
  readonly historyLoadingMore = signal(false);
  readonly historyWindowBefore = signal<string | null>(null);
  readonly historyWindowLoaded = signal(0);
  readonly historyWindowTotal = signal(0);
  readonly historyHasMore = signal(true);
  private historyObserver?: IntersectionObserver;
  @ViewChild('historySentinel') private historySentinel?: ElementRef<HTMLElement>;

  constructor() {
    this.load();
  }

  ngAfterViewInit() {
    this.attachHistoryObserver();
  }

  private attachHistoryObserver() {
    if (this.isLiked || this.historyObserver || !this.historySentinel?.nativeElement) return;
    this.historyObserver = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) this.loadMoreHistory();
    }, { rootMargin: '480px' });
    this.historyObserver.observe(this.historySentinel.nativeElement);
  }

  ngOnDestroy() {
    this.historyObserver?.disconnect();
  }

  get isLiked() {
    return this.mode === 'liked';
  }

  get title() {
    return this.i18n.t(this.isLiked ? 'nav.likedVideos' : 'nav.history');
  }

  load() {
    if (!this.isLiked) {
      this.page.set(1);
      const windowEnd = new Date().toISOString();
      this.historyWindowBefore.set(windowEnd);
      this.historyWindowLoaded.set(0);
      this.historyWindowTotal.set(0);
      this.historyHasMore.set(true);
      this.loadHistoryChunk(1, windowEnd, true);
      return;
    }
    this.loading.set(true);
    this.error.set('');
    const request = this.isLiked
      ? this.content.liked(this.ratingFilter(), this.page(), this.pageSize)
      : this.content.history(this.page(), this.pageSize);
    request.pipe(finalize(() => this.loading.set(false))).subscribe({
      next: result => {
        this.items.set(result.items ?? []);
        this.total.set(result.total ?? 0);
      },
      error: () => {
        this.items.set([]);
        this.total.set(0);
        this.error.set(this.i18n.t('library.loadError'));
      }
    });
  }

  private loadHistoryChunk(page: number, before: string | null, replace: boolean) {
    this.loading.set(replace);
    this.historyLoadingMore.set(!replace);
    this.error.set('');
    this.content.history(page, this.pageSize, before).pipe(finalize(() => {
      this.loading.set(false);
      this.historyLoadingMore.set(false);
    })).subscribe({
      next: result => {
        const incoming = result.items ?? [];
        this.items.update(current => replace ? incoming : [...current, ...incoming]);
        this.historyWindowBefore.set(before);
        this.historyWindowLoaded.update(count => replace ? incoming.length : count + incoming.length);
        this.historyWindowTotal.set(result.total ?? 0);
        if (!replace && incoming.length === 0) this.historyHasMore.set(false);
        queueMicrotask(() => this.attachHistoryObserver());
      },
      error: () => {
        if (replace) this.items.set([]);
        this.error.set(this.i18n.t('library.loadError'));
      }
    });
  }

  loadMoreHistory() {
    if (this.isLiked || !this.historyHasMore() || this.loading() || this.historyLoadingMore()) return;
    const loaded = this.historyWindowLoaded();
    const total = this.historyWindowTotal();
    if (total > 0 && loaded < total) {
      this.loadHistoryChunk(this.page() + 1, this.historyWindowBefore(), false);
      this.page.update(value => value + 1);
      return;
    }
    const currentWindowEnd = this.historyWindowBefore() ?? new Date().toISOString();
    const currentWindowEndMs = Date.parse(currentWindowEnd);
    if (!Number.isFinite(currentWindowEndMs)) {
      this.historyHasMore.set(false);
      return;
    }
    const nextWindowEnd = new Date(currentWindowEndMs - 30 * 24 * 60 * 60 * 1000).toISOString();
    this.page.set(1);
    this.historyWindowLoaded.set(0);
    this.historyWindowTotal.set(0);
    this.historyHasMore.set(true);
    this.loadHistoryChunk(1, nextWindowEnd, false);
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
    this.page.set(next);
    this.load();
  }

  duration(value: number) {
    const seconds = Math.max(0, Math.floor(value || 0));
    return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
  }

  progressLabel(item: LibraryVideo | WatchHistoryItem) {
    return `${Math.round(item.progress || 0)}%`;
  }

  ratingLabel(item: LibraryVideo | WatchHistoryItem) {
    return item.myRating ? `${item.myRating}/5 sao` : this.i18n.t('library.notRated');
  }
}
