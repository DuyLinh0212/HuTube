import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { StudioDataService } from '../../../core/studio-data.service';
import { ContentService, VideoDetail } from '../../../core/content.service';

@Component({
  selector: 'app-studio-content-page',
  standalone: true,
  imports: [CommonModule, RouterLink, DatePipe],
  template: `
    <main class="page">
      <header>
        <div>
          <h1>Nội dung kênh</h1>
          <p>Quản lý trạng thái xuất bản và thẩm định video của bạn.</p>
        </div>
        <a routerLink="/studio/upload" class="upload-btn">+ Tải video lên</a>
      </header>

      @if (toastMessage()) {
        <div class="toast-banner">
          <span>{{ toastMessage() }}</span>
          <button type="button" class="toast-close" (click)="toastMessage.set('')">✕</button>
        </div>
      }

      <div class="filter-bar">
        <label class="search">
          <input
            type="search"
            placeholder="Tìm kiếm theo tiêu đề video..."
            (input)="search.set($any($event.target).value)"
          />
        </label>
      </div>

      <div class="table">
        <table>
          <thead>
            <tr>
              <th>Video</th>
              <th>Chế độ hiển thị</th>
              <th>Trạng thái kiểm duyệt</th>
              <th>Ngày tạo</th>
              <th>Lượt xem</th>
              <th>Tương tác</th>
            </tr>
          </thead>
          <tbody>
            @for (v of filtered(); track v.videoId) {
              <tr>
                <td>
                  <a [routerLink]="['/watch', v.videoId]">{{ v.title }}</a>
                  <small>{{ v.duration }} giây · {{ v.tags.join(', ') }}</small>
                </td>
                <td>
                  <div class="visibility-cell">
                    <select
                      class="visibility-select"
                      [value]="v.visibility"
                      [disabled]="updatingId() === v.videoId"
                      (change)="changeVisibility(v, $any($event.target).value)"
                    >
                      <option value="public">🌐 Công khai</option>
                      <option value="unlisted">🔗 Không công khai</option>
                      <option value="private">🔒 Riêng tư</option>
                    </select>
                    @if (updatingId() === v.videoId) {
                      <span class="updating-spinner">Đang lưu…</span>
                    }
                  </div>
                </td>
                <td>
                  @if (v.moderationStatus === 'approved' || (v.status === 'published' && v.visibility === 'public')) {
                    <span class="badge badge-success">✓ Đã duyệt</span>
                  } @else if (v.moderationStatus === 'pending') {
                    <span class="badge badge-pending">⏳ Chờ duyệt</span>
                  } @else if (v.moderationStatus === 'reviewing') {
                    <span class="badge badge-reviewing">🔍 Đang thẩm định</span>
                  } @else if (v.moderationStatus === 'rejected') {
                    <span class="badge badge-danger">✕ Bị từ chối</span>
                  } @else if (v.visibility === 'public') {
                    <span class="badge badge-pending">⏳ Chờ duyệt</span>
                  } @else {
                    <span class="badge badge-muted">Chưa gửi duyệt</span>
                  }
                </td>
                <td>{{ v.createdAt | date:'dd/MM/yyyy' }}</td>
                <td>{{ v.stats.views }}</td>
                <td>{{ v.stats.likes }} thích · {{ v.stats.comments }} bình luận</td>
              </tr>
            } @empty {
              <tr>
                <td colspan="6" class="empty-cell">Chưa có video nào trong danh sách.</td>
              </tr>
            }
          </tbody>
        </table>
      </div>
    </main>
  `,
  styles: [`
    .page { max-width: 1240px; margin: auto; padding: 32px 24px; }
    header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; }
    header h1 { margin: 0 0 6px; font-size: 1.6rem; font-weight: 800; color: var(--ink); }
    header p { margin: 0; color: var(--text-muted); font-size: 0.85rem; }
    .upload-btn { display: inline-flex; align-items: center; padding: 10px 18px; border-radius: 9px; background: var(--primary); color: #fff; text-decoration: none; font-weight: 700; font-size: 0.82rem; }
    .toast-banner { display: flex; justify-content: space-between; align-items: center; padding: 12px 18px; border-radius: 10px; background: rgba(16, 185, 129, 0.14); color: #047857; font-weight: 600; font-size: 0.84rem; margin-bottom: 18px; border: 1px solid rgba(16, 185, 129, 0.25); }
    .toast-close { background: none; border: none; font-size: 1rem; cursor: pointer; color: #047857; padding: 0 4px; }
    .filter-bar { margin-bottom: 18px; }
    .search input { width: 320px; padding: 9px 14px; border: 1px solid var(--line); border-radius: 8px; background: var(--surface); color: var(--ink); font-size: 0.8rem; }
    .search input:focus { outline: none; border-color: var(--primary); }
    .table { overflow: auto; border: 1px solid var(--line); border-radius: 14px; background: var(--surface); box-shadow: 0 4px 14px -4px rgba(0,0,0,0.04); }
    table { width: 100%; border-collapse: collapse; }
    th, td { padding: 13px 16px; border-bottom: 1px solid var(--line); text-align: left; white-space: nowrap; font-size: 0.82rem; }
    th { background: var(--canvas); color: var(--text-muted); font-weight: 700; text-transform: uppercase; font-size: 0.72rem; letter-spacing: 0.04em; }
    td:first-child { display: grid; gap: 4px; min-width: 280px; }
    td a { color: var(--ink); font-weight: 700; text-decoration: none; }
    td a:hover { color: var(--primary); }
    small { color: var(--text-muted); font-size: 0.72rem; }
    .visibility-cell { display: flex; align-items: center; gap: 8px; }
    .visibility-select {
      padding: 6px 12px;
      border-radius: 8px;
      border: 1px solid var(--line);
      background: var(--surface);
      color: var(--ink);
      font-size: 0.8rem;
      font-weight: 600;
      cursor: pointer;
      outline: none;
      transition: all 0.2s ease;
    }
    .visibility-select:hover:not(:disabled) { border-color: var(--primary); }
    .visibility-select:focus { border-color: var(--primary); box-shadow: 0 0 0 2px var(--primary-soft); }
    .visibility-select:disabled { opacity: 0.6; cursor: not-allowed; }
    .updating-spinner { font-size: 0.72rem; color: var(--primary); font-weight: 600; }
    .empty-cell { text-align: center; padding: 40px 20px; color: var(--text-muted); }
    .badge { display: inline-flex; align-items: center; gap: 4px; padding: 4px 8px; border-radius: 6px; font-size: 0.7rem; font-weight: 700; }
    .badge-success { background: rgba(16, 185, 129, 0.12); color: #059669; }
    .badge-pending { background: rgba(217, 119, 6, 0.12); color: #d97706; }
    .badge-reviewing { background: rgba(37, 99, 235, 0.12); color: #2563eb; }
    .badge-danger { background: rgba(239, 68, 68, 0.12); color: #dc2626; }
    .badge-muted { background: rgba(100, 116, 139, 0.12); color: #64748b; }
  `]
})
export class StudioContentPage implements OnInit {
  readonly data = inject(StudioDataService);
  readonly content = inject(ContentService);
  readonly search = signal('');
  readonly updatingId = signal<string | null>(null);
  readonly toastMessage = signal<string>('');

  ngOnInit() {
    this.data.load();
  }

  filtered() {
    const q = this.search().toLowerCase();
    return this.data.videos().filter(v => v.title.toLowerCase().includes(q));
  }

  changeVisibility(video: VideoDetail, newVisibility: string) {
    if (newVisibility === video.visibility) return;
    const oldVisibility = video.visibility;
    this.updatingId.set(video.videoId);

    this.content.update(video.videoId, { visibility: newVisibility }).subscribe({
      next: updated => {
        video.visibility = updated.visibility || newVisibility;
        video.moderationStatus = updated.moderationStatus;
        video.status = updated.status;
        this.updatingId.set(null);

        if (newVisibility === 'public' && updated.moderationStatus !== 'approved') {
          this.toastMessage.set(`Đã chuyển video "${video.title}" sang Công khai và gửi vào Hàng đợi kiểm duyệt.`);
        } else if (newVisibility === 'public') {
          this.toastMessage.set(`Đã chuyển video "${video.title}" sang chế độ Công khai.`);
        } else if (newVisibility === 'unlisted') {
          this.toastMessage.set(`Đã chuyển video "${video.title}" sang chế độ Không công khai.`);
        } else {
          this.toastMessage.set(`Đã chuyển video "${video.title}" sang chế độ Riêng tư.`);
        }

        setTimeout(() => this.toastMessage.set(''), 5000);
      },
      error: err => {
        this.updatingId.set(null);
        this.toastMessage.set(err?.error?.detail || err?.error?.title || 'Không thể cập nhật chế độ hiển thị video.');
        setTimeout(() => this.toastMessage.set(''), 5000);
      }
    });
  }
}

