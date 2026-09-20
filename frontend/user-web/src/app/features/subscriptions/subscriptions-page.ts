import { HttpErrorResponse } from '@angular/common/http';
import { Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { ChannelService, SubscribedChannelResponse } from '../../core/channel.service';
import { ContentService, VideoCard } from '../../core/content.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-subscriptions-page',
  imports: [RouterLink, LocaleDatePipe, LocaleNumberPipe, TranslatePipe],
  templateUrl: './subscriptions-page.html',
  styleUrl: './subscriptions-page.scss'
})
export class SubscriptionsPage {
  private readonly content = inject(ContentService);
  private readonly channelService = inject(ChannelService);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);

  readonly channels = signal<SubscribedChannelResponse[]>([]);
  readonly videos = signal<VideoCard[]>([]);
  readonly loading = signal(true);
  readonly error = signal('');

  constructor() {
    this.load();
  }

  load() {
    if (!this.auth.user()) {
      this.auth.restore().subscribe({
        next: (authenticated) => {
          if (authenticated) {
            this.fetchData();
          } else {
            this.loading.set(false);
          }
        },
        error: () => this.loading.set(false)
      });
      return;
    }

    this.fetchData();
  }

  private fetchData() {
    this.loading.set(true);
    this.error.set('');

    // Load subscribed channels list
    this.channelService.getSubscribedChannels().subscribe({
      next: (channels) => this.channels.set(channels),
      error: () => this.channels.set([])
    });

    // Load videos feed from subscribed channels
    this.content.feed('subscriptions', 1, 40)
      .pipe(finalize(() => this.loading.set(false)))
      .subscribe({
        next: (res) => {
          this.videos.set(res.items ?? []);
        },
        error: (err: unknown) => {
          this.videos.set([]);
          if (err instanceof HttpErrorResponse && err.status === 404) {
            this.error.set('');
          } else {
            this.error.set(this.i18n.t('common.error'));
          }
        }
      });
  }

  duration(value: number): string {
    const hours = Math.floor(value / 3600);
    const minutes = Math.floor((value % 3600) / 60);
    const seconds = value % 60;
    if (hours > 0) {
      return `${hours}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
    }
    return `${minutes}:${String(seconds).padStart(2, '0')}`;
  }
}
