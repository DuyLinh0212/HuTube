import { Component, ElementRef, EventEmitter, Output, ViewChild, effect, inject } from '@angular/core';
import { Router } from '@angular/router';
import { AppNotification, NotificationService } from '../../core/notification.service';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-notification-panel',
  imports: [LocaleDatePipe, TranslatePipe],
  templateUrl: './notification-panel.component.html',
  styleUrl: './notification-panel.component.scss',
})
export class NotificationPanelComponent {
  @Output() readonly closed = new EventEmitter<void>();
  readonly notifications = inject(NotificationService);
  private readonly router = inject(Router);
  @ViewChild('notificationList') private list?: ElementRef<HTMLElement>;
  private lastAutoFillPage = -1;
  private autoFillScheduled = false;

  constructor() {
    effect(() => {
      const loadedPage = this.notifications.loadedPage();
      const hasMore = this.notifications.hasMore();
      const loading = this.notifications.loading();
      if (loading || !hasMore || loadedPage === this.lastAutoFillPage) return;

      this.lastAutoFillPage = loadedPage;
      this.scheduleViewportFill();
    });
  }

  onScroll() {
    const box = this.list?.nativeElement;
    if (box && box.scrollTop + box.clientHeight >= box.scrollHeight - 96 && this.notifications.hasMore()) {
      this.notifications.loadMore();
    }
  }

  private scheduleViewportFill() {
    if (this.autoFillScheduled || typeof requestAnimationFrame === 'undefined') return;
    this.autoFillScheduled = true;
    requestAnimationFrame(() => {
      this.autoFillScheduled = false;
      const box = this.list?.nativeElement;
      if (!box || this.notifications.loading() || !this.notifications.hasMore()) return;

      // Keep fetching while the list is too short to scroll. This makes the
      // remaining pages reachable even when the first page doesn't fill the panel.
      if (box.scrollHeight <= box.clientHeight + 48) this.notifications.loadMore();
    });
  }

  open(item: AppNotification) {
    this.notifications.read(item);
    this.closed.emit();
    if (item.actionUrl) void this.router.navigateByUrl(item.actionUrl);
  }
}
