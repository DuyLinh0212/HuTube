import { Component, ElementRef, EventEmitter, Output, inject } from '@angular/core';
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
  private readonly host = inject(ElementRef<HTMLElement>);

  onScroll() {
    const box = this.host.nativeElement.querySelector('.notification-list');
    if (box && box.scrollTop + box.clientHeight >= box.scrollHeight - 32 && this.notifications.hasMore()) {
      this.notifications.loadMore();
    }
  }

  open(item: AppNotification) {
    this.notifications.read(item);
    this.closed.emit();
    if (item.actionUrl) void this.router.navigateByUrl(item.actionUrl);
  }
}
