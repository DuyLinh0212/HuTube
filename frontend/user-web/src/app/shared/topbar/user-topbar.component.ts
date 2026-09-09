import { Component, EventEmitter, OnInit, Output, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { ChannelDetail, ChannelService } from '../../core/channel.service';

@Component({
  selector: 'app-user-topbar',
  imports: [RouterLink],
  templateUrl: './user-topbar.component.html',
  styleUrl: './user-topbar.component.scss'
})
export class UserTopbarComponent implements OnInit {
  @Output() readonly menuOpened = new EventEmitter<void>();
  readonly auth = inject(AuthService);
  private channelService = inject(ChannelService);
  private router = inject(Router);

  readonly myChannel = signal<ChannelDetail | null>(null);

  ngOnInit() {
    this.channelService.getMyChannel().subscribe({
      next: ch => this.myChannel.set(ch),
      error: () => this.myChannel.set(null)
    });
  }

  onActionClick() {
    const ch = this.myChannel();
    if (ch) {
      void this.router.navigate(['/channel', ch.handle]);
    } else {
      void this.router.navigate(['/channel/create']);
    }
  }
}
