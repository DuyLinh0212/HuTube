import { Component, ElementRef, EventEmitter, Output, inject } from '@angular/core';
import { Router } from '@angular/router';
import { DatePipe } from '@angular/common';
import { NotificationService, AppNotification } from '../../core/notification.service';

@Component({
  selector: 'app-notification-panel',
  imports: [DatePipe],
  template: `
    <section class="notification-panel" aria-label="Danh sách thông báo">
      <header><strong>Thông báo</strong><button type="button" (click)="notifications.readAll()">Đánh dấu đã đọc</button></header>
      <div class="notification-list" (scroll)="onScroll()">
        @for (item of notifications.items(); track item.notificationId) {
          <button type="button" class="notification-item" [class.unread]="!item.isRead" (click)="open(item)">
            <span class="notification-dot" aria-hidden="true"></span>
            <span><strong>{{ item.title }}</strong><small>{{ item.content }}</small><time>{{ item.createdAt | date:'short' }}</time></span>
          </button>
        } @empty { <p class="empty">Chưa có thông báo.</p> }
        @if (notifications.loading()) { <p class="empty">Đang tải…</p> }
      </div>
    </section>
  `,
  styles: [`
    .notification-panel{position:absolute;right:48px;top:calc(100% + 10px);z-index:120;width:min(390px,calc(100vw - 24px));border:1px solid var(--line);border-radius:16px;background:var(--surface);box-shadow:0 20px 48px -12px rgba(0,0,0,.35);overflow:hidden}
    header{display:flex;justify-content:space-between;align-items:center;padding:14px 16px;border-bottom:1px solid var(--line)} header button{border:0;background:transparent;color:var(--primary);font-size:.75rem;cursor:pointer}
    .notification-list{max-height:390px;overflow:auto}.notification-item{display:flex;width:100%;gap:10px;padding:13px 16px;border:0;border-bottom:1px solid var(--line);background:transparent;color:var(--text-body);text-align:left;cursor:pointer}.notification-item:hover,.notification-item.unread{background:var(--primary-soft)}
    .notification-item>span:last-child{display:grid;gap:3px;min-width:0}.notification-item strong{color:var(--ink);font-size:.82rem}.notification-item small{overflow:hidden;color:var(--text-muted);font-size:.75rem;text-overflow:ellipsis;white-space:nowrap}.notification-item time{color:var(--text-muted);font-size:.66rem}.notification-dot{width:7px;height:7px;margin-top:5px;border-radius:50%;background:transparent;flex:none}.unread .notification-dot{background:var(--primary)}.empty{padding:24px;text-align:center;color:var(--text-muted);font-size:.8rem}
  `]
})
export class NotificationPanelComponent {
  @Output() readonly closed = new EventEmitter<void>();
  readonly notifications = inject(NotificationService);
  private readonly router = inject(Router);
  private readonly host = inject(ElementRef<HTMLElement>);
  onScroll() { const box = this.host.nativeElement.querySelector('.notification-list'); if (box && box.scrollTop + box.clientHeight >= box.scrollHeight - 32 && this.notifications.hasMore()) this.notifications.loadMore(); }
  open(item: AppNotification) { this.notifications.read(item); this.closed.emit(); if (item.actionUrl) void this.router.navigateByUrl(item.actionUrl); }
}
