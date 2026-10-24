import { Component, computed, inject, OnDestroy, signal } from '@angular/core';
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
  imports: [FormsModule, LocaleDatePipe, LocaleNumberPipe, RouterLink, TranslatePipe],
  templateUrl: './library-page.html',
  styleUrl: './library-page.scss'
})
export class LibraryPage implements OnDestroy {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
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
  historyQuery = '';
  historySort = 'newest';
  historyDateRange = 'all';
  private requestVersion = 0;
  readonly pageCount = computed(() => Math.max(1, Math.ceil(this.total() / this.pageSize)));
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
  constructor() {
    if (this.isLiked) this.load();
    else this.route.queryParamMap.subscribe(params => {
      this.historyQuery = params.get('q') ?? '';
      this.historySort = params.get('sort') === 'oldest' ? 'oldest' : 'newest';
      this.historyDateRange = ['today', 'week', 'month'].includes(params.get('dateRange') ?? '') ? params.get('dateRange')! : 'all';
      const page = Number(params.get('page'));
      this.page.set(Number.isSafeInteger(page) && page > 0 ? page : 1);
      this.load();
    });
  }

  ngOnDestroy() { this.requestVersion++; }

  get isLiked() {
    return this.mode === 'liked';
  }

  get title() {
    return this.i18n.t(this.isLiked ? 'nav.likedVideos' : 'nav.history');
  }

  load() {
    const version = ++this.requestVersion;
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

  filterHistory() {
    void this.router.navigate([], { relativeTo: this.route, queryParamsHandling: 'merge',
      queryParams: { q: this.historyQuery || null, sort: this.historySort, dateRange: this.historyDateRange, page: 1 } });
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
