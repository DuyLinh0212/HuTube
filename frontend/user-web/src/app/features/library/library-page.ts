import { DatePipe, DecimalPipe } from '@angular/common';
import { Component, computed, inject, signal } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { ContentService, LibraryVideo } from '../../core/content.service';

type LibraryMode = 'history' | 'liked';

@Component({
  selector: 'app-library-page',
  imports: [DatePipe, DecimalPipe, RouterLink],
  templateUrl: './library-page.html',
  styleUrl: './library-page.scss'
})
export class LibraryPage {
  private readonly route = inject(ActivatedRoute);
  private readonly content = inject(ContentService);

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
    return this.isLiked ? 'Video đã thích' : 'Lịch sử xem';
  }

  get description() {
    return this.isLiked
      ? 'Những video bạn đã yêu thích, cùng điểm đánh giá riêng của bạn.'
      : 'Xem lại những video bạn đã mở gần đây.';
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
      error: error => {
        this.items.set([]);
        this.total.set(0);
        this.error.set(error?.error?.detail || 'Không thể tải thư viện video.');
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
    return item.myRating ? `${item.myRating}/5 sao` : 'Chưa đánh giá';
  }
}
