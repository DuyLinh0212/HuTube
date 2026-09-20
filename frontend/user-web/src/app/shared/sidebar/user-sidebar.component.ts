import { Component, EventEmitter, Input, OnInit, Output, inject, signal } from '@angular/core';
import { Router, RouterLink, RouterLinkActive } from '@angular/router';
import { catchError, forkJoin, of } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { ChannelDetail, ChannelService, SubscribedChannelResponse } from '../../core/channel.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-user-sidebar',
  imports: [RouterLink, RouterLinkActive, TranslatePipe],
  templateUrl: './user-sidebar.component.html',
  styleUrl: './user-sidebar.component.scss'
})
export class UserSidebarComponent implements OnInit {
  private channelService = inject(ChannelService);
  private router = inject(Router);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);

  @Input() open = false;
  @Input({ required: true }) collapsed = false;
  @Output() readonly collapsedChange = new EventEmitter<boolean>();
  @Output() readonly navigationClosed = new EventEmitter<void>();

  readonly subscribedChannels = signal<SubscribedChannelResponse[]>([]);

  ngOnInit() {
    if (this.auth.user()) {
      this.channelService.getSubscribedChannels().subscribe({
        next: channels => this.subscribedChannels.set(channels),
        error: () => this.subscribedChannels.set([])
      });
    }
  }

  toggleCollapsed() { this.collapsedChange.emit(!this.collapsed); }
  closeNavigation() { this.navigationClosed.emit(); }

  openMyChannel() {
    this.closeNavigation();
    forkJoin({
      channels: this.channelService.getAccessibleChannels().pipe(catchError(() => of([] as ChannelDetail[]))),
      invitations: this.channelService.getMyInvitations().pipe(catchError(() => of([])))
    }).subscribe(({ channels, invitations }) => {
      const ownedChannel = channels.find(channel => channel.isOwner);
      if (ownedChannel) {
        void this.router.navigate(['/channel', ownedChannel.handle]);
      } else if (channels[0]) {
        void this.router.navigate(['/studio/overview'], { queryParams: { channelId: channels[0].channelId } });
      } else if (invitations.length > 0) {
        void this.router.navigate(['/studio/invitations']);
      } else {
        void this.router.navigate(['/channel/create']);
      }
    });
  }
}
