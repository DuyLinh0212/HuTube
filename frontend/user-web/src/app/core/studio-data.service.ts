import { Injectable, computed, inject, signal } from '@angular/core';
import { ChannelDetail, ChannelService } from './channel.service';
import { ContentService, VideoDetail } from './content.service';

@Injectable({ providedIn: 'root' })
export class StudioDataService {
  private readonly channels = inject(ChannelService);
  private readonly content = inject(ContentService);
  readonly channel = signal<ChannelDetail | null>(null);
  readonly videos = signal<VideoDetail[]>([]);
  readonly loading = signal(false);
  readonly error = signal('');
  readonly views = computed(() => this.videos().reduce((sum, video) => sum + video.stats.views, 0));
  readonly likes = computed(() => this.videos().reduce((sum, video) => sum + video.stats.likes, 0));
  readonly comments = computed(() => this.videos().reduce((sum, video) => sum + video.stats.comments, 0));
  readonly watchSeconds = computed(() => this.videos().reduce((sum, video) => sum + video.stats.views * video.duration, 0));

  load() {
    this.loading.set(true);
    this.channels.getMyChannel().subscribe({
      next: channel => {
        this.channel.set(channel);
        this.content.managed(channel.channelId, 1, 50).subscribe({
          next: page => { this.videos.set(page.items); this.loading.set(false); },
          error: () => { this.error.set('Không thể tải dữ liệu Studio.'); this.loading.set(false); }
        });
      },
      error: () => this.loading.set(false)
    });
  }
}
