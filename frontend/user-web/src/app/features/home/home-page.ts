import { NgTemplateOutlet } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { AfterViewInit, Component, ElementRef, OnDestroy, ViewChild, inject, signal } from '@angular/core';
import { NavigationEnd, Router, RouterLink } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { catchError, filter, firstValueFrom, of } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { ContentService, VideoCard } from '../../core/content.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-home-page',
  imports: [NgTemplateOutlet, RouterLink, LocaleDatePipe, LocaleNumberPipe, TranslatePipe],
  templateUrl: './home-page.html',
  styleUrl: './home-page.scss',
})
export class HomePage implements AfterViewInit, OnDestroy {
  private static readonly RECOMMENDATION_CANDIDATE_COUNT = 50;
  private static readonly RECOMMENDATION_DISPLAY_COUNT = 20;
  private static readonly SUBSCRIPTION_DISPLAY_COUNT = 3;
  private static readonly FEED_BATCH_SIZE = 30;

  private readonly auth = inject(AuthService);
  private readonly content = inject(ContentService);
  private readonly i18n = inject(I18nService);
  private readonly router = inject(Router);
  private observer?: IntersectionObserver;
  private loadVersion = 0;
  private loadingMoreInFlight = false;
  private readonly displayedIds = new Set<string>();

  private subscriptionsPage = 1;
  private subscriptionsDone = false;
  private popularPage = 1;
  private popularDone = false;
  private randomDone = false;
  private randomEmptyAttempts = 0;
  private randomTotal = 0;

  private loadMoreSentinel?: ElementRef<HTMLElement>;

  @ViewChild('loadMoreSentinel')
  set loadMoreSentinelRef(value: ElementRef<HTMLElement> | undefined) {
    this.loadMoreSentinel = value;
    this.observeSentinel();
  }

  readonly recommendations = signal<VideoCard[]>([]);
  readonly subscriptionVideos = signal<VideoCard[]>([]);
  readonly popularVideos = signal<VideoCard[]>([]);
  readonly randomVideos = signal<VideoCard[]>([]);
  readonly loading = signal(true);
  readonly loadingMore = signal(false);
  readonly hasMore = signal(true);
  readonly error = signal('');

  constructor() {
    this.router.events
      .pipe(
        filter((event): event is NavigationEnd => event instanceof NavigationEnd),
        filter(event => event.urlAfterRedirects.split(/[?#]/, 1)[0] === '/home'),
        takeUntilDestroyed(),
      )
      .subscribe(() => void this.load());
  }

  ngAfterViewInit() {
    if (typeof IntersectionObserver === 'undefined') return;
    this.observer = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) void this.loadMore();
    }, { rootMargin: '640px 0px' });
    this.observeSentinel();
  }

  ngOnDestroy() {
    this.observer?.disconnect();
  }

  private observeSentinel() {
    if (this.observer && this.loadMoreSentinel) {
      this.observer.observe(this.loadMoreSentinel.nativeElement);
    }
  }

  async load() {
    const version = ++this.loadVersion;
    this.resetFeed();
    this.loading.set(true);
    try {
      // Home is public, so restore a cookie-backed session before the public
      // feed request; otherwise the first request could become anonymous and
      // miss personalized recommendations.
      if (!this.auth.user()) {
        await firstValueFrom(this.auth.restore().pipe(catchError(() => of(false))));
      }

      const value = await firstValueFrom(
        this.content.feed(
          'home',
          1,
          HomePage.RECOMMENDATION_CANDIDATE_COUNT,
          undefined,
          undefined,
          'popular',
        ),
      );
      if (version !== this.loadVersion) return;

      this.recommendations.set(
        this.addUnique(this.pickRecommendations(value.items ?? [], HomePage.RECOMMENDATION_DISPLAY_COUNT)),
      );
      this.error.set('');
    } catch (reason: unknown) {
      if (version !== this.loadVersion) return;
      this.error.set(
        reason instanceof HttpErrorResponse && reason.status === 404
          ? ''
          : this.i18n.t('home.error'),
      );
    } finally {
      if (version === this.loadVersion) this.loading.set(false);
    }
  }

  private async loadMore() {
    if (this.loading() || this.loadingMoreInFlight || !this.hasMore()) return;
    const version = this.loadVersion;
    this.loadingMoreInFlight = true;
    if (this.loadMoreSentinel) this.observer?.unobserve(this.loadMoreSentinel.nativeElement);
    this.loadingMore.set(true);

    try {
      while (version === this.loadVersion && this.hasMore()) {
        if (!this.subscriptionsDone) {
          const added = await this.loadSubscriptionPage(version);
          if (added > 0) break;
          continue;
        }
        if (!this.popularDone) {
          const added = await this.loadPopularPage(version);
          if (added > 0) break;
          continue;
        }
        if (!this.randomDone) {
          const added = await this.loadRandomBatch(version);
          if (added > 0) break;
          continue;
        }
        this.hasMore.set(false);
      }
    } finally {
      if (version === this.loadVersion) {
        this.loadingMore.set(false);
        // Re-observe after appending cards. If the sentinel is still inside
        // the root margin, IntersectionObserver will request the next batch.
        this.observeSentinel();
      }
      this.loadingMoreInFlight = false;
    }
  }

  private async loadSubscriptionPage(version: number): Promise<number> {
    const page = this.subscriptionsPage++;
    try {
      const result = await firstValueFrom(
        this.content.feed('subscriptions', page, HomePage.SUBSCRIPTION_DISPLAY_COUNT),
      );
      if (version !== this.loadVersion) return 0;
      const items = this.addUnique(result.items ?? []);
      if (items.length > 0) this.subscriptionVideos.update(current => [...current, ...items]);
      // The subscription section is intentionally limited to the three newest videos.
      this.subscriptionsDone = true;
      return items.length;
    } catch {
      // Guests and users without subscriptions simply continue to Popular.
      this.subscriptionsDone = true;
      return 0;
    }
  }

  private async loadPopularPage(version: number): Promise<number> {
    const page = this.popularPage++;
    try {
      const result = await firstValueFrom(
        this.content.feed(
          'explore',
          page,
          HomePage.FEED_BATCH_SIZE,
          undefined,
          undefined,
          'popular',
        ),
      );
      if (version !== this.loadVersion) return 0;
      const items = this.addUnique(result.items ?? []);
      if (items.length > 0) this.popularVideos.update(current => [...current, ...items]);
      if (!result.items?.length || page * result.pageSize >= result.total) this.popularDone = true;
      return items.length;
    } catch {
      this.popularDone = true;
      return 0;
    }
  }

  private async loadRandomBatch(version: number): Promise<number> {
    try {
      // Random ordering is generated server-side. Always request the first
      // batch because each request gets a fresh random sample; displayedIds
      // prevents duplicates across all feed sections.
      const result = await firstValueFrom(
        this.content.feed(
          'explore',
          1,
          HomePage.FEED_BATCH_SIZE,
          undefined,
          undefined,
          'random',
        ),
      );
      if (version !== this.loadVersion) return 0;
      this.randomTotal = result.total;
      const items = this.addUnique(result.items ?? []);
      if (items.length > 0) {
        this.randomEmptyAttempts = 0;
        this.randomVideos.update(current => [...current, ...items]);
      } else {
        this.randomEmptyAttempts++;
      }
      if (!result.items?.length || this.displayedIds.size >= this.randomTotal || this.randomEmptyAttempts >= 3) {
        this.randomDone = true;
      }
      return items.length;
    } catch {
      this.randomDone = true;
      return 0;
    }
  }

  private addUnique(items: VideoCard[]): VideoCard[] {
    return items.filter(item => {
      if (this.displayedIds.has(item.videoId)) return false;
      this.displayedIds.add(item.videoId);
      return true;
    });
  }

  private pickRandom<T>(items: T[], count: number): T[] {
    const shuffled = [...items];
    for (let index = shuffled.length - 1; index > 0; index -= 1) {
      const randomIndex = Math.floor(Math.random() * (index + 1));
      [shuffled[index], shuffled[randomIndex]] = [shuffled[randomIndex], shuffled[index]];
    }
    return shuffled.slice(0, count);
  }

  private pickRecommendations(items: VideoCard[], count: number): VideoCard[] {
    const promoted = items.filter(item => item.isPromoted).slice(0, count);
    const promotedIds = new Set(promoted.map(item => item.videoId));
    const organic = items.filter(item => !promotedIds.has(item.videoId));
    return [...promoted, ...this.pickRandom(organic, Math.max(0, count - promoted.length))];
  }

  private resetFeed() {
    this.recommendations.set([]);
    this.subscriptionVideos.set([]);
    this.popularVideos.set([]);
    this.randomVideos.set([]);
    this.error.set('');
    this.loadingMore.set(false);
    this.hasMore.set(true);
    this.displayedIds.clear();
    this.subscriptionsPage = 1;
    this.subscriptionsDone = false;
    this.popularPage = 1;
    this.popularDone = false;
    this.randomDone = false;
    this.randomEmptyAttempts = 0;
    this.randomTotal = 0;
  }

  duration(value: number) {
    return `${Math.floor(value / 60)}:${String(value % 60).padStart(2, '0')}`;
  }

}
