import { Component, effect, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { forkJoin } from 'rxjs';
import { CommentItem, ContentService, VideoDetail } from '../../../core/content.service';
import { I18nService } from '../../../core/i18n.service';
import { StudioDataService } from '../../../core/studio-data.service';
import { TranslatePipe } from '../../../core/translate.pipe';

interface StudioComment {
  comment: CommentItem;
  video: VideoDetail;
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
    forkJoin({
      videos: this.content.managed(channelId, 1, 100),
      comments: this.content.managedComments(channelId, '', 1, 100),
    }).subscribe(({ videos, comments }) => {
      const byId = new Map(videos.items.map(video => [video.videoId, video]));
      this.rows.set(comments.items.flatMap(comment => {
        const video = byId.get(comment.videoId);
        return video ? [{ comment, video }] : [];
      }));
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
    this.content.createComment(row.video.videoId, this.replyText.trim(), row.comment.commentId)
      .subscribe(() => {
        this.replyText = '';
        this.replying.set(null);
      });
  }
}
