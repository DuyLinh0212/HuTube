import { Component, effect, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { catchError, forkJoin, map, of, switchMap } from 'rxjs';
import { CommentItem, ContentService, VideoDetail } from '../../../core/content.service';
import { I18nService } from '../../../core/i18n.service';
import { StudioDataService } from '../../../core/studio-data.service';
import { TranslatePipe } from '../../../core/translate.pipe';

interface StudioComment {
  comment: CommentItem;
  video: VideoDetail | null;
}

@Component({
  selector: 'app-studio-comments-page',
  imports: [FormsModule, TranslatePipe],
  templateUrl: './studio-comments-page.html',
  styleUrl: './studio-comments-page.scss',
})
export class StudioCommentsPage {
  private readonly content = inject(ContentService);
  readonly data = inject(StudioDataService);
  readonly i18n = inject(I18nService);
  private loadedChannelId = '';
  readonly rows = signal<StudioComment[]>([]);
  readonly loading = signal(false);
  readonly error = signal('');
  readonly filter = signal<'visible' | 'hidden'>('visible');
  readonly replying = signal<string | null>(null);
  replyText = '';

  constructor() {
    this.data.load();
    effect(() => {
      const channel = this.data.channel();
      if (!channel || channel.channelId === this.loadedChannelId) return;
      this.loadedChannelId = channel.channelId;
      this.loadComments(channel.channelId);
    });
  }

  private loadComments(channelId: string) {
    if (!this.data.hasPermission('comment.manage')) {
      this.rows.set([]);
      return;
    }
    this.loading.set(true);
    this.error.set('');
    this.content.managedComments(channelId, '', 1, 100).pipe(
      switchMap(comments => {
        const byId = new Map(this.data.videos().map(video => [video.videoId, video]));
        const missingIds = [...new Set(comments.items.map(comment => comment.videoId))]
          .filter(videoId => !byId.has(videoId));
        if (!missingIds.length) return of({ comments, byId });
        return forkJoin(missingIds.map(videoId => this.content.detail(videoId).pipe(catchError(() => of(null))))).pipe(
          map(videos => {
            videos.forEach(video => { if (video) byId.set(video.videoId, video); });
            return { comments, byId };
          })
        );
      })
    ).subscribe({
      next: ({ comments, byId }) => {
        this.rows.set(comments.items.map(comment => ({ comment, video: byId.get(comment.videoId) ?? null })));
        this.loading.set(false);
      },
      error: () => {
        this.rows.set([]);
        this.error.set('Không thể tải bình luận của kênh.');
        this.loading.set(false);
      }
    });
  }

  filtered() {
    return this.rows().filter(row => row.comment.status === this.filter());
  }

  toggleHidden(row: StudioComment) {
    this.content.hideComment(row.comment.commentId, row.comment.status !== 'hidden', this.i18n.t('studio.commentManagedReason'))
      .subscribe(comment => {
        row.comment = comment;
        this.rows.update(value => [...value]);
      });
  }

  remove(row: StudioComment) {
    this.content.deleteComment(row.comment.commentId)
      .subscribe(() => this.rows.update(value => value.filter(item => item !== row)));
  }

  reply(row: StudioComment) {
    if (!this.replyText.trim()) return;
    this.content.createComment(row.comment.videoId, this.replyText.trim(), row.comment.commentId)
      .subscribe(() => {
        this.replyText = '';
        this.replying.set(null);
      });
  }
}
