import { Component, OnDestroy, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Subject, debounceTime, distinctUntilChanged, takeUntil } from 'rxjs';
import { ContentService, VideoCard } from '../../core/content.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-explore-page',
  imports: [RouterLink, LocaleDatePipe, LocaleNumberPipe, TranslatePipe, FormsModule],
  templateUrl: './explore-page.html',
  styleUrl: './explore-page.scss',
})
export class ExplorePage implements OnInit, OnDestroy {
  private readonly content = inject(ContentService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly i18n = inject(I18nService);
  private readonly destroy$ = new Subject<void>();

  readonly videos = signal<VideoCard[]>([]);
  readonly categories = signal<{ categoryId: string; name: string }[]>([]);
  readonly total = signal(0);
  readonly loading = signal(true);
  readonly error = signal('');

  // Filter state
  readonly searchQuery = signal('');
  readonly selectedCategoryId = signal('');
  readonly selectedSort = signal('relevance');
  readonly selectedDuration = signal('');
  readonly selectedDateRange = signal('');
  readonly currentPage = signal(1);
  readonly pageSize = 20;

  readonly sortOptions = [
    { value: 'relevance', labelKey: 'explore.sortRelevance' },
    { value: 'newest', labelKey: 'explore.newest' },
    { value: 'views', labelKey: 'explore.sortViews' },
    { value: 'engagement', labelKey: 'explore.sortEngagement' },
  ];

  readonly durationOptions = [
    { value: '', labelKey: 'explore.durationAll' },
    { value: 'short', labelKey: 'explore.durationShort' },
    { value: 'medium', labelKey: 'explore.durationMedium' },
    { value: 'long', labelKey: 'explore.durationLong' },
  ];

  readonly dateOptions = [
    { value: '', labelKey: 'explore.dateAll' },
    { value: 'today', labelKey: 'explore.dateToday' },
    { value: 'this_week', labelKey: 'explore.dateThisWeek' },
    { value: 'this_month', labelKey: 'explore.dateThisMonth' },
    { value: 'this_year', labelKey: 'explore.dateThisYear' },
  ];

  get hasActiveFilters(): boolean {
    return !!(this.searchQuery() || this.selectedCategoryId() || this.selectedDuration() || this.selectedDateRange());
  }

  get totalPages(): number {
    return Math.ceil(this.total() / this.pageSize);
  }

  get resultsLabel(): string {
    return this.i18n.t('explore.resultsCount').replace('{count}', this.total().toString());
  }

  ngOnInit() {
    this.content.categories().subscribe({
      next: value => this.categories.set(value ?? []),
      error: () => {},
    });

    this.route.queryParamMap.pipe(takeUntil(this.destroy$)).subscribe(params => {
      this.searchQuery.set(params.get('q') ?? '');
      this.selectedCategoryId.set(params.get('categoryId') ?? '');
      this.selectedSort.set(params.get('sort') ?? 'relevance');
      this.selectedDuration.set(params.get('duration') ?? '');
      this.selectedDateRange.set(params.get('dateRange') ?? '');
      this.currentPage.set(Number(params.get('page') ?? '1'));
      this.load();
    });
  }

  ngOnDestroy() {
    this.destroy$.next();
    this.destroy$.complete();
  }

  load() {
    this.loading.set(true);

    this.content
      .search({
        q: this.searchQuery() || undefined,
        categoryId: this.selectedCategoryId() || undefined,
        sort: this.selectedSort() || undefined,
        duration: this.selectedDuration() || undefined,
        dateRange: this.selectedDateRange() || undefined,
        page: this.currentPage(),
        pageSize: this.pageSize,
      })
      .subscribe({
        next: value => {
          this.videos.set(value.items ?? []);
          this.total.set(value.total ?? 0);
          this.error.set('');
          this.loading.set(false);
        },
        error: () => {
          this.videos.set([]);
          this.total.set(0);
          this.error.set(this.i18n.t('explore.error'));
          this.loading.set(false);
        },
      });
  }

  changeSort(value: string) {
    this.selectedSort.set(value || 'relevance');
    this.currentPage.set(1);
    this.updateQuery();
  }

  changeCategory(value: string) {
    this.selectedCategoryId.set(value);
    this.currentPage.set(1);
    this.updateQuery();
  }

  changeDuration(value: string) {
    this.selectedDuration.set(value);
    this.currentPage.set(1);
    this.updateQuery();
  }

  changeDateRange(value: string) {
    this.selectedDateRange.set(value);
    this.currentPage.set(1);
    this.updateQuery();
  }

  clearAllFilters() {
    this.searchQuery.set('');
    this.selectedCategoryId.set('');
    this.selectedSort.set('relevance');
    this.selectedDuration.set('');
    this.selectedDateRange.set('');
    this.currentPage.set(1);
    this.updateQuery();
  }

  goToPage(page: number) {
    if (page < 1 || page > this.totalPages) return;
    this.currentPage.set(page);
    this.updateQuery();
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  duration(value: number) {
    return String(Math.floor(value / 60)) + ':' + String(value % 60).padStart(2, '0');
  }

  categoryLabel(id: string): string {
    return this.categories().find(c => c.categoryId === id)?.name ?? id;
  }

  private updateQuery() {
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: {
        q: this.searchQuery() || null,
        sort: this.selectedSort() !== 'relevance' ? this.selectedSort() : null,
        categoryId: this.selectedCategoryId() || null,
        duration: this.selectedDuration() || null,
        dateRange: this.selectedDateRange() || null,
        page: this.currentPage() > 1 ? this.currentPage() : null,
      },
      queryParamsHandling: 'merge',
    });
  }
}
