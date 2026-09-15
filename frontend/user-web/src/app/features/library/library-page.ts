import { Component, computed, inject, signal } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { ContentService, LibraryVideo } from '../../core/content.service';
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
export class LibraryPage {
  private readonly route = inject(ActivatedRoute);
  private readonly content = inject(ContentService);
  readonly i18n = inject(I18nService);

  readonly mode: LibraryMode = this.route.snapshot.data['library'] === 'liked' ? 'liked' : 'history';
  readonly items = signal<LibraryVideo[]>([]);
  readonly loading = signal(true);
  readonly error = signal('');
  readonly page = signal(1);
  readonly pageSize = 20;
  readonly total = signal(0);
  readonly ratingFilter = signal<number | null>(null);
  readonly pageCount = computed(() => Math.max(1, Math.ceil(this.total() / this.pageSize)));

  constructor() {
    this.load();
  }

  get isLiked() {
    return this.mode === 'liked';
  }

  get title() {
    return this.i18n.t(this.isLiked ? 'nav.likedVideos' : 'nav.history');
  }

  load() {
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

  progressLabel(item: LibraryVideo) {
    return `${Math.round(item.progress || 0)}%`;
  }

  ratingLabel(item: LibraryVideo) {
    return item.myRating ? `${item.myRating}/5 sao` : this.i18n.t('library.notRated');
  }
}
