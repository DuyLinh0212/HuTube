import { Component, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { ChannelDetail, ChannelService } from '../../core/channel.service';
import { AuthService, errorMessage } from '../../core/auth.service';

type ChannelTab = 'home' | 'videos' | 'playlists' | 'about';

@Component({
  selector: 'app-channel-page',
  imports: [DatePipe, RouterLink],
  templateUrl: './channel-page.html',
  styleUrl: './channel-page.scss'
})
export class ChannelPage {
  private route = inject(ActivatedRoute);
  private channelService = inject(ChannelService);
  readonly auth = inject(AuthService);

  readonly channel = signal<ChannelDetail | null>(null);
  readonly activeTab = signal<ChannelTab>('home');
  readonly loading = signal(true);
  readonly error = signal('');
  readonly isSubscribed = signal(false);

  constructor() {
    this.route.paramMap.subscribe(params => {
      const handle = params.get('handle');
      if (handle) {
        this.loadChannel(handle);
      }
    });
  }

  loadChannel(handle: string) {
    this.loading.set(true);
    this.error.set('');

    this.channelService.getChannel(handle).pipe(finalize(() => this.loading.set(false))).subscribe({
      next: ch => this.channel.set(ch),
      error: err => this.error.set(errorMessage(err) || 'Không tìm thấy thông tin kênh.')
    });
  }

  setTab(tab: ChannelTab) {
    this.activeTab.set(tab);
  }

  toggleSubscribe() {
    this.isSubscribed.set(!this.isSubscribed());
  }
}
