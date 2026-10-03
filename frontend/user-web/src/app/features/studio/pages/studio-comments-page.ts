import { Component, ElementRef, OnDestroy, ViewChild, effect, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { Subscription } from 'rxjs';
import { CommentItem, ContentService } from '../../../core/content.service';
import { I18nService } from '../../../core/i18n.service';
import { StudioDataService } from '../../../core/studio-data.service';
import { LocaleDatePipe } from '../../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../../core/locale-number.pipe';
import { TranslatePipe } from '../../../core/translate.pipe';

interface StudioComment {
  comment: CommentItem;
}

type CommentStatus = 'visible' | 'hidden';
type CommentSort = 'newest' | 'oldest' | 'mostLiked';

@Component({
  selector: 'app-studio-comments-page',
  imports: [FormsModule, RouterLink, TranslatePipe, LocaleDatePipe, LocaleNumberPipe],
  templateUrl: './studio-comments-page.html',
  styleUrl: './studio-comments-page.scss',
})
export class StudioCommentsPage implements OnDestroy {
  private readonly content = inject(ContentService);
  readonly data = inject(StudioDataService);
  readonly i18n = inject(I18nService);
  private observer?: IntersectionObserver;
  private request?: Subscription;
  private requestGeneration = 0;
  private activeChannelId = '';
  private currentPage = 0;
  readonly pageSize = 20;
  readonly rows = signal<StudioComment[]>([]);
  readonly total = signal(0);
  readonly loading = signal(false);
  readonly loadingMore = signal(false);
  readonly hasMore = signal(false);
  readonly error = signal('');
  readonly actionError = signal('');
  readonly filter = signal<CommentStatus>('visible');
  readonly sort = signal<CommentSort>('newest');
  readonly replying = signal<string | null>(null);
  readonly busyCommentId = signal<string | null>(null);
  replyText = '';

  @ViewChild('loadMoreSentinel') set loadMoreSentinel(element: ElementRef<HTMLDivElement> | undefined) {
    this.observer?.disconnect();
    this.observer = undefined;
    if (typeof IntersectionObserver === 'undefined' || !element) return;
    this.observer = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) this.loadNextPage();
    }, { rootMargin: '360px 0px' });
    this.observer.observe(element.nativeElement);
  }

  constructor() {
    effect(() => {
      const channel = this.data.channel();
      if (!channel || channel.channelId === this.activeChannelId) return;
      this.activeChannelId = channel.channelId;
      this.filter.set('visible');
      this.sort.set('newest');
      this.loadPage(false);
    });
  }

  ngOnDestroy() {
    this.requestGeneration++;
    this.request?.unsubscribe();
    this.observer?.disconnect();
  }

  setFilter(status: CommentStatus) {
    if (status === this.filter()) return;
    this.filter.set(status);
    this.loadPage(false);
  }

  setSort(sort: CommentSort) {
    if (sort === this.sort()) return;
    this.sort.set(sort);
    this.loadPage(false);
  }

  loadNextPage() {
    if (!this.hasMore() || this.loading() || this.loadingMore()) return;
    this.loadPage(true);
  }

  retry() {
    this.loadPage(false);
  }

  private loadPage(append: boolean) {
    if (!this.activeChannelId || !this.data.hasPermission('comment.manage')) return;
    const generation = ++this.requestGeneration;
    this.request?.unsubscribe();
    const page = append ? this.currentPage + 1 : 1;
    if (append) {
      this.loadingMore.set(true);
    } else {
      this.currentPage = 0;
      this.rows.set([]);
      this.total.set(0);
      this.hasMore.set(false);
      this.loading.set(true);
      this.error.set('');
    }
    this.actionError.set('');

    this.request = this.content.managedComments(this.activeChannelId, this.filter(), page, this.pageSize, this.sort())
      .subscribe({
        next: result => {
          if (generation !== this.requestGeneration) return;
          const incoming = result.items.map(comment => ({ comment }));
          this.rows.update(current => append ? [...current, ...incoming] : incoming);
          this.currentPage = result.page;
          this.total.set(result.total);
          this.hasMore.set(result.page * result.pageSize < result.total);
          this.loading.set(false);
          this.loadingMore.set(false);
          this.error.set('');
        },
        error: () => {
          if (generation !== this.requestGeneration) return;
          this.loading.set(false);
          this.loadingMore.set(false);
          this.error.set(this.i18n.t('studio.commentsLoadError'));
        },
      });
  }

  toggleHidden(row: StudioComment) {
    if (this.busyCommentId()) return;
    this.busyCommentId.set(row.comment.commentId);
    this.actionError.set('');
    const shouldHide = row.comment.status !== 'hidden';
    this.content.hideComment(row.comment.commentId, shouldHide, this.i18n.t('studio.commentManagedReason'))
      .subscribe({
        next: comment => {
          this.busyCommentId.set(null);
          if (comment.status !== this.filter()) {
            this.rows.update(rows => rows.filter(item => item.comment.commentId !== comment.commentId));
            this.total.update(value => Math.max(0, value - 1));
            this.hasMore.set(this.currentPage * this.pageSize < this.total());
            return;
          }
          this.rows.update(rows => rows.map(item => item.comment.commentId === comment.commentId ? { comment } : item));
        },
        error: () => {
          this.busyCommentId.set(null);
          this.actionError.set(this.i18n.t('studio.commentActionError'));
        },
      });
  }

  remove(row: StudioComment) {
    if (this.busyCommentId()) return;
    this.busyCommentId.set(row.comment.commentId);
    this.actionError.set('');
    this.content.deleteComment(row.comment.commentId).subscribe({
      next: () => {
        this.busyCommentId.set(null);
        this.rows.update(rows => rows.filter(item => item.comment.commentId !== row.comment.commentId));
        const total = Math.max(0, this.total() - 1);
        this.total.set(total);
        this.hasMore.set(this.currentPage * this.pageSize < total);
      },
      error: () => {
        this.busyCommentId.set(null);
        this.actionError.set(this.i18n.t('studio.commentActionError'));
      },
    });
  }

  reply(row: StudioComment) {
    const text = this.replyText.trim();
    if (!text || this.busyCommentId()) return;
    this.busyCommentId.set(row.comment.commentId);
    this.actionError.set('');
    this.content.createComment(row.comment.videoId, text, row.comment.commentId).subscribe({
      next: () => {
        this.busyCommentId.set(null);
        this.replyText = '';
        this.replying.set(null);
        row.comment.replyCount++;
        if (this.filter() === 'visible') this.total.update(value => value + 1);
        this.rows.update(rows => [...rows]);
      },
      error: () => {
        this.busyCommentId.set(null);
        this.actionError.set(this.i18n.t('studio.commentActionError'));
      },
    });
  }
}
