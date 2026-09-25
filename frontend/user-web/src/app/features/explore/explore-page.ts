import { Component, ElementRef, OnDestroy, OnInit, ViewChild, inject, signal } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Subject, takeUntil } from 'rxjs';
import { ChannelService } from '../../core/channel.service';
import { CategoryRankingGroup, ContentService, FeaturedCreator, VideoCard } from '../../core/content.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-explore-page',
  imports: [RouterLink, LocaleDatePipe, LocaleNumberPipe, TranslatePipe],
  templateUrl: './explore-page.html',
  styleUrl: './explore-page.scss',
})
export class ExplorePage implements OnInit, OnDestroy {
  private readonly content = inject(ContentService);
  private readonly channelService = inject(ChannelService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly i18n = inject(I18nService);
  private readonly destroy$ = new Subject<void>();

  @ViewChild('trendingCarousel') trendingCarouselRef?: ElementRef<HTMLDivElement>;

  // Search & Filter State
  readonly videos = signal<VideoCard[]>([]);
  readonly total = signal(0);
  readonly loading = signal(false);
  readonly error = signal('');
  readonly hasSearchQuery = signal(false);

  readonly searchQuery = signal('');
  readonly selectedCategoryId = signal('');
  readonly selectedSort = signal('relevance');
  readonly selectedDuration = signal('');
  readonly selectedDateRange = signal('');
  readonly currentPage = signal(1);
  readonly pageSize = 20;

  // Explore Hub data from API
  readonly hubLoading = signal(false);
  readonly hubError = signal('');
  readonly rankingGroups = signal<CategoryRankingGroup[]>([]);
  readonly overallRankingVideos = signal<VideoCard[]>([]);
  readonly featuredCreators = signal<FeaturedCreator[]>([]);
  readonly trendingVideos = signal<VideoCard[]>([]);

  // Single-category top-12 view
  readonly categoryVideos = signal<VideoCard[]>([]);
  readonly categoryLoading = signal(false);
  readonly selectedGroupName = signal('');

  // Local subscribe state: channelId -> boolean
  private readonly subscribedMap = new Map<string, boolean>();

  // Active Category Tab in Showcase
  readonly activeCategoryTab = signal('bxh_tong');

  readonly categoryTabs = [
    { id: 'bxh_tong', label: 'BXH tổng' },
    { id: 'cong-nghe', label: 'Công nghệ' },
    { id: 'du-lich', label: 'Du lịch' },
    { id: 'am-nhac', label: 'Âm nhạc' },
    { id: 'am-thuc', label: 'Ẩm thực' },
    { id: 'giao-duc', label: 'Giáo dục' },
    { id: 'podcast', label: 'Podcast' },
    { id: 'the-thao', label: 'Thể thao' },
    { id: 'doi-song', label: 'Đời sống' },
    { id: 'phim-anh', label: 'Phim ảnh' },
    { id: 'lam-dep', label: 'Làm đẹp' },
  ];

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

  private readonly themeMap: Record<string, 'tech' | 'travel' | 'food' | 'music'> = {
    'cong-nghe': 'tech', 'du-lich': 'travel', 'am-thuc': 'food', 'am-nhac': 'music',
  };
  private readonly iconMap: Record<string, 'tag' | 'plane' | 'food' | 'music'> = {
    'cong-nghe': 'tag', 'du-lich': 'plane', 'am-thuc': 'food', 'am-nhac': 'music',
  };

  getTheme(slug: string): 'tech' | 'travel' | 'food' | 'music' {
    return this.themeMap[slug] ?? 'tech';
  }
  getIcon(slug: string): 'tag' | 'plane' | 'food' | 'music' {
    return this.iconMap[slug] ?? 'tag';
  }
  isCreatorSubscribed(channelId: string): boolean {
    return this.subscribedMap.get(channelId) ?? false;
  }

  get isSearchMode(): boolean {
    return !!(this.hasSearchQuery() || this.selectedCategoryId() || this.selectedDuration() || this.selectedDateRange());
  }
  get totalPages(): number {
    return Math.ceil(this.total() / this.pageSize);
  }
  get resultsLabel(): string {
    return this.i18n.t('explore.resultsCount').replace('{count}', this.total().toString());
  }

  ngOnInit() {
    this.route.queryParamMap.pipe(takeUntil(this.destroy$)).subscribe(params => {
      const q = params.get('q') ?? '';
      const categoryId = params.get('categoryId') ?? '';
      this.searchQuery.set(q);
      this.hasSearchQuery.set(!!q.trim());
      this.selectedCategoryId.set(categoryId);
      this.selectedSort.set(params.get('sort') ?? 'relevance');
      this.selectedDuration.set(params.get('duration') ?? '');
      this.selectedDateRange.set(params.get('dateRange') ?? '');
      this.currentPage.set(Number(params.get('page') ?? '1'));

      if (categoryId) {
        this.activeCategoryTab.set(categoryId);
      } else if (!q) {
        this.activeCategoryTab.set('bxh_tong');
      }

      if (this.isSearchMode) {
        this.loadSearch();
      }
    });

    this.loadHub();
  }

  ngOnDestroy() {
    this.destroy$.next();
    this.destroy$.complete();
  }

  loadHub() {
    this.hubLoading.set(true);
    this.hubError.set('');
    this.content.exploreHub().pipe(takeUntil(this.destroy$)).subscribe({
      next: hub => {
        this.rankingGroups.set(hub.rankings ?? []);
        this.featuredCreators.set(hub.creators ?? []);
        this.trendingVideos.set(hub.trending ?? []);

        if (hub.topVideos?.length) {
          this.overallRankingVideos.set(hub.topVideos.slice(0, 12));
          this.hubLoading.set(false);
          return;
        }

        // Older API instances do not expose topVideos yet. Use the public
        // search endpoint as a compatible global-ranking fallback instead of
        // rebuilding the list from per-category top-three results.
        this.content.search({ sort: 'views', page: 1, pageSize: 12 }).pipe(takeUntil(this.destroy$)).subscribe({
          next: result => {
            this.overallRankingVideos.set((result.items ?? []).slice(0, 12));
            this.hubLoading.set(false);
          },
          error: () => {
            this.overallRankingVideos.set([]);
            this.hubLoading.set(false);
          },
        });
      },
      error: () => {
        this.hubError.set('Không thể tải dữ liệu khám phá. Vui lòng thử lại.');
        this.hubLoading.set(false);
      },
    });
  }

  selectCategoryTab(tabId: string) {
    this.activeCategoryTab.set(tabId);
    if (tabId === 'bxh_tong') {
      this.categoryVideos.set([]);
      this.selectedGroupName.set('');
    } else {
      const group = this.rankingGroups().find(g => g.slug === tabId);
      this.selectedGroupName.set(group?.categoryName ?? tabId);
      this.categoryLoading.set(true);
      this.content.search({
        categoryId: group?.categoryId,
        sort: 'views',
        pageSize: 12,
      }).pipe(takeUntil(this.destroy$)).subscribe({
        next: result => {
          this.categoryVideos.set(result.items ?? []);
          this.categoryLoading.set(false);
        },
        error: () => this.categoryLoading.set(false),
      });
    }
  }

  toggleSubscribe(channelId: string, event: Event) {
    event.preventDefault();
    event.stopPropagation();
    this.subscribedMap.set(channelId, !this.subscribedMap.get(channelId));
    // Trigger signal re-render
    this.featuredCreators.update(list => [...list]);
  }

  scrollTrending(direction: 'left' | 'right') {
    if (!this.trendingCarouselRef?.nativeElement) return;
    const container = this.trendingCarouselRef.nativeElement;
    const card = container.querySelector<HTMLElement>('.trending-card');
    const scrollAmount = card ? card.offsetWidth + 16 : 300;
    container.scrollBy({ left: direction === 'left' ? -scrollAmount : scrollAmount, behavior: 'smooth' });
  }

  onImageError(event: Event) {
    const img = event.target as HTMLImageElement;
    if (img) {
      img.style.display = 'none';
      img.parentElement?.classList.add('has-fallback');
    }
  }

  submitSearch(event: Event) {
    event.preventDefault();
    this.searchQuery.set(this.searchQuery().trim());
    this.currentPage.set(1);
    void this.router.navigate(['/explore'], { queryParams: this.queryParams() });
  }

  loadSearch() {
    this.loading.set(true);
    this.content.search({
      q: this.searchQuery() || undefined,
      categoryId: this.selectedCategoryId() || undefined,
      sort: this.selectedSort() || undefined,
      duration: this.selectedDuration() || undefined,
      dateRange: this.selectedDateRange() || undefined,
      page: this.currentPage(),
      pageSize: this.pageSize,
    }).subscribe({
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

  changeSort(value: string) { this.selectedSort.set(value || 'relevance'); this.currentPage.set(1); this.updateQuery(); }
  changeDuration(value: string) { this.selectedDuration.set(value); this.currentPage.set(1); this.updateQuery(); }
  changeDateRange(value: string) { this.selectedDateRange.set(value); this.currentPage.set(1); this.updateQuery(); }

  clearAllFilters() {
    this.searchQuery.set('');
    this.selectedCategoryId.set('');
    this.selectedSort.set('relevance');
    this.selectedDuration.set('');
    this.selectedDateRange.set('');
    this.currentPage.set(1);
    this.activeCategoryTab.set('bxh_tong');
    void this.router.navigate(['/explore'], { queryParams: {} });
  }

  goToPage(page: number) {
    if (page < 1 || page > this.totalPages) return;
    this.currentPage.set(page);
    this.updateQuery();
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  duration(seconds: number): string {
    return String(Math.floor(seconds / 60)) + ':' + String(seconds % 60).padStart(2, '0');
  }

  private updateQuery() {
    void this.router.navigate([], { relativeTo: this.route, queryParams: this.queryParams() });
  }

  private queryParams() {
    return {
      q: this.searchQuery().trim() || null,
      sort: this.selectedSort() !== 'relevance' ? this.selectedSort() : null,
      categoryId: this.selectedCategoryId() || null,
      duration: this.selectedDuration() || null,
      dateRange: this.selectedDateRange() || null,
      page: this.currentPage() > 1 ? this.currentPage() : null,
    };
  }
}
