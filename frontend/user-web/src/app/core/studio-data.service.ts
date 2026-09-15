import { Injectable, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { ChannelDetail, ChannelService } from './channel.service';
import { ContentService, VideoDetail } from './content.service';
import { I18nService } from './i18n.service';

@Injectable({ providedIn: 'root' })
export class StudioDataService {
  private readonly channels = inject(ChannelService);
  private readonly content = inject(ContentService);
  private readonly router = inject(Router);
  private readonly i18n = inject(I18nService);
  private readonly storageKey = 'hutube.studio.channel-id';
  readonly channel = signal<ChannelDetail | null>(null);
  readonly accessibleChannels = signal<ChannelDetail[]>([]);
  readonly selectedChannelId = signal<string | null>(this.readSelectedId());
  readonly videos = signal<VideoDetail[]>([]);
  readonly loading = signal(false);
  readonly error = signal('');
  readonly views = computed(() => this.videos().reduce((sum, video) => sum + video.stats.views, 0));
  readonly likes = computed(() => this.videos().reduce((sum, video) => sum + video.stats.likes, 0));
  readonly comments = computed(() => this.videos().reduce((sum, video) => sum + video.stats.comments, 0));
  readonly watchSeconds = computed(() => this.videos().reduce((sum, video) => sum + video.stats.views * video.duration, 0));

  load(preferredChannelId?: string | null) {
    this.loading.set(true);
    this.error.set('');
    const requestedId = preferredChannelId ?? this.queryChannelId() ?? this.selectedChannelId();
    this.channels.getAccessibleChannels().subscribe({
      next: channels => {
        this.accessibleChannels.set(channels);
        const selected = channels.find(item => item.channelId === requestedId)
          ?? channels.find(item => item.isOwner)
          ?? channels[0];
        if (!selected) {
          this.channel.set(null);
          this.videos.set([]);
          this.selectedChannelId.set(null);
          this.loading.set(false);
          return;
        }
        this.setSelection(selected);
        this.loadContent(selected.channelId);
      },
      error: () => {
        this.accessibleChannels.set([]);
        this.channel.set(null);
        this.videos.set([]);
        this.error.set(this.i18n.t('studio.accessibleChannelsError'));
        this.loading.set(false);
      }
    });
  }

  selectChannel(channelId: string) {
    const selected = this.accessibleChannels().find(item => item.channelId === channelId);
    if (!selected || selected.channelId === this.selectedChannelId()) return;
    this.setSelection(selected);
    void this.router.navigate([], { queryParams: { channelId }, queryParamsHandling: 'merge', replaceUrl: true });
    this.loadContent(channelId);
  }

  hasPermission(permission: string): boolean {
    return this.channel()?.permissions.includes(permission) ?? false;
  }

  private loadContent(channelId: string) {
    this.loading.set(true);
    this.content.managed(channelId, 1, 50).subscribe({
      next: page => { this.videos.set(page.items); this.loading.set(false); },
      error: () => { this.error.set(this.i18n.t('studio.channelDataError')); this.loading.set(false); }
    });
  }

  private setSelection(channel: ChannelDetail) {
    this.channel.set(channel);
    this.selectedChannelId.set(channel.channelId);
    try { localStorage.setItem(this.storageKey, channel.channelId); } catch { /* storage is optional */ }
  }

  private readSelectedId(): string | null {
    try { return localStorage.getItem(this.storageKey); } catch { return null; }
  }

  private queryChannelId(): string | null {
    const query = this.router.url.split('?')[1]?.split('#')[0];
    if (!query) return null;
    return new URLSearchParams(query).get('channelId');
  }
}
