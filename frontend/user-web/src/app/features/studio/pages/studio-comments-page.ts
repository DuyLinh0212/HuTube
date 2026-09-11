import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { forkJoin, switchMap } from 'rxjs';
import { ChannelService } from '../../../core/channel.service';
import { CommentItem, ContentService, VideoDetail } from '../../../core/content.service';

interface StudioComment { comment: CommentItem; video: VideoDetail; }

@Component({
  selector: 'app-studio-comments-page',
  imports: [FormsModule],
  template: `<main class="page">
    <h1>Bình luận</h1><p>Quản lý bình luận trên tất cả video của kênh.</p>
    <div class="filters">
      <button [class.active]="filter()==='visible'" (click)="filter.set('visible')">Đang hiển thị</button>
      <button [class.active]="filter()==='hidden'" (click)="filter.set('hidden')">Đã ẩn</button>
    </div>
    <section>
      @for(row of filtered(); track row.comment.commentId) {
        <article>
          <div class="avatar">{{row.comment.displayName.slice(0,1)}}</div>
          <div class="body">
            <p><strong>{{row.comment.displayName}}</strong> trên <b>{{row.video.title}}</b></p>
            <span>{{row.comment.content}}</span>
            <div>
              <button (click)="replying.set(row.comment.commentId)">Trả lời</button>
              <button (click)="toggleHidden(row)">{{row.comment.status==='hidden'?'Hiện lại':'Ẩn'}}</button>
              <button class="danger" (click)="remove(row)">Xóa</button>
            </div>
            @if(replying()===row.comment.commentId) {
              <form (ngSubmit)="reply(row)"><input name="reply" [(ngModel)]="replyText" placeholder="Nhập câu trả lời"/><button>Gửi</button></form>
            }
          </div>
        </article>
      } @empty { <p class="empty">Không có bình luận ở trạng thái này.</p> }
    </section>
  </main>`,
  styles: [`.page{max-width:1100px;margin:auto;padding:32px 24px}.page>p{color:var(--text-muted)}.filters{display:flex;gap:8px;margin:20px 0}.filters button,article button{padding:7px 11px;border:1px solid var(--line);border-radius:8px;background:var(--canvas);color:var(--ink);cursor:pointer}.filters .active{background:var(--primary);color:#fff}section{border:1px solid var(--line);border-radius:14px;background:var(--surface);overflow:hidden}article{display:flex;gap:12px;padding:16px;border-bottom:1px solid var(--line)}.avatar{display:grid;width:38px;height:38px;place-items:center;border-radius:50%;background:var(--primary-soft);color:var(--primary);font-weight:800}.body{flex:1}.body p{margin:0 0 6px;color:var(--text-muted);font-size:.78rem}.body span{display:block;margin-bottom:10px}.body>div{display:flex;gap:7px}.danger{color:var(--danger)!important}form{display:flex;gap:8px;margin-top:10px}form input{flex:1;padding:8px;border:1px solid var(--line);border-radius:8px;background:var(--canvas);color:var(--ink)}.empty{padding:24px;text-align:center;color:var(--text-muted)}`]
})
export class StudioCommentsPage {
  private readonly channels = inject(ChannelService);
  private readonly content = inject(ContentService);
  readonly rows = signal<StudioComment[]>([]);
  readonly filter = signal<'visible' | 'hidden'>('visible');
  readonly replying = signal<string | null>(null);
  replyText = '';

  constructor() {
    this.channels.getMyChannel().pipe(
      switchMap(channel => forkJoin({
        videos: this.content.managed(channel.channelId, 1, 100),
        comments: this.content.managedComments(channel.channelId, '', 1, 100)
      }))
    ).subscribe(({ videos, comments }) => {
      const byId = new Map(videos.items.map(video => [video.videoId, video]));
      this.rows.set(comments.items.flatMap(comment => {
        const video = byId.get(comment.videoId);
        return video ? [{ comment, video }] : [];
      }));
    });
  }

  filtered() { return this.rows().filter(row => row.comment.status === this.filter()); }

  toggleHidden(row: StudioComment) {
    this.content.hideComment(row.comment.commentId, row.comment.status !== 'hidden', 'Chủ kênh quản lý').subscribe(comment => {
      row.comment = comment;
      this.rows.update(value => [...value]);
    });
  }

  remove(row: StudioComment) {
    this.content.deleteComment(row.comment.commentId).subscribe(() => this.rows.update(value => value.filter(item => item !== row)));
  }

  reply(row: StudioComment) {
    if (!this.replyText.trim()) return;
    this.content.createComment(row.video.videoId, this.replyText.trim(), row.comment.commentId).subscribe(() => {
      this.replyText = '';
      this.replying.set(null);
    });
  }
}
