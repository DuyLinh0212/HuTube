import { HttpErrorResponse } from '@angular/common/http';
import { Component, inject, signal } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { ContentService, VideoCard } from '../../core/content.service';
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
export class ExplorePage {
  private readonly content = inject(ContentService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly i18n = inject(I18nService);

  readonly videos = signal<VideoCard[]>([]);
  readonly categories = signal<{ categoryId: string; name: string }[]>([]);
  readonly selectedCategoryId = signal('');
  readonly selectedSort = signal('newest');
  readonly loading = signal(true);
  readonly error = signal('');

  constructor() {
    const params = this.route.snapshot.queryParamMap;
    this.selectedCategoryId.set(params.get('categoryId') ?? '');
    this.selectedSort.set(params.get('sort') ?? 'newest');

    this.content.categories().subscribe({
      next: value => this.categories.set(value ?? []),
      error: () => {},
    });

    this.load();
  }

  load() {
    this.loading.set(true);
    const params = this.route.snapshot.queryParamMap;

    this.content
      .feed(
        'explore',
        1,
        20,
        this.selectedCategoryId() || undefined,
        params.get('q') || undefined,
        this.selectedSort(),
      )
      .subscribe({
        next: value => {
          this.videos.set(value.items ?? []);
          this.error.set('');
          this.loading.set(false);
        },
        error: (reason: unknown) => {
          this.videos.set([]);
          this.error.set(
            reason instanceof HttpErrorResponse && reason.status === 404
              ? ''
              : this.i18n.t('explore.error'),
          );
          this.loading.set(false);
        },
      });
  }

  changeSort(value: string) {
    this.selectedSort.set(value || 'newest');
    this.updateQuery();
    this.load();
  }

  changeCategory(value: string) {
    this.selectedCategoryId.set(value);
    this.updateQuery();
    this.load();
  }

  duration(value: number) {
    return String(Math.floor(value / 60)) + ':' + String(value % 60).padStart(2, '0');
  }

  private updateQuery() {
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: {
        sort: this.selectedSort(),
        categoryId: this.selectedCategoryId() || null,
      },
      queryParamsHandling: 'merge',
      replaceUrl: true,
    });
  }
}
