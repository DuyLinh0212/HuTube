import { Component, EventEmitter, Input, Output, inject } from '@angular/core';
import { Router, RouterLink, RouterLinkActive } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { ChannelService } from '../../core/channel.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-user-sidebar',
  imports: [RouterLink, RouterLinkActive, TranslatePipe],
  templateUrl: './user-sidebar.component.html',
  styleUrl: './user-sidebar.component.scss'
})
export class UserSidebarComponent {
  private channelService = inject(ChannelService);
  private router = inject(Router);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);

  @Input() open = false;
  @Input({ required: true }) collapsed = false;
  @Output() readonly collapsedChange = new EventEmitter<boolean>();
  @Output() readonly navigationClosed = new EventEmitter<void>();

  toggleCollapsed() { this.collapsedChange.emit(!this.collapsed); }
  closeNavigation() { this.navigationClosed.emit(); }

  openMyChannel() {
    this.closeNavigation();
    this.channelService.getMyChannel().subscribe({
      next: ch => void this.router.navigate(['/channel', ch.handle]),
      error: () => void this.router.navigate(['/channel/create'])
    });
  }
}
