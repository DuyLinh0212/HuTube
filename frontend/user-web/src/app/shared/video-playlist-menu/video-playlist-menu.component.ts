import { Component, HostListener, Input, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { PlaylistService, PlaylistSummary } from '../../core/playlist.service';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-video-playlist-menu',
  imports: [TranslatePipe],
  templateUrl: './video-playlist-menu.component.html',
  styleUrl: './video-playlist-menu.component.scss',
})
export class VideoPlaylistMenuComponent {
  @Input({ required: true }) videoId = '';

  readonly open = signal(false);
  readonly loading = signal(false);
  readonly addingId = signal<string | null>(null);
  readonly playlists = signal<PlaylistSummary[]>([]);
  readonly message = signal('');

  private readonly auth = inject(AuthService);
  private readonly playlistService = inject(PlaylistService);
  private readonly router = inject(Router);
  private readonly i18n = inject(I18nService);

  @HostListener('document:click')
  closeFromOutside(): void {
    this.open.set(false);
  }

  toggle(event: MouseEvent): void {
    event.preventDefault();
    event.stopPropagation();
    this.message.set('');
    if (!this.auth.user()) {
      void this.router.navigate(['/login'], {
        queryParams: { returnUrl: typeof location === 'undefined' ? '/home' : location.pathname + location.search },
      });
      return;
    }
    const next = !this.open();
    this.open.set(next);
    if (next && this.playlists().length === 0) void this.loadPlaylists();
  }

  async loadPlaylists(): Promise<void> {
    if (this.loading()) return;
    this.loading.set(true);
    try {
      this.playlists.set(await firstValueFrom(this.playlistService.mine()));
    } catch {
      this.message.set(this.i18n.t('watchPlaylist.loadError'));
    } finally {
      this.loading.set(false);
    }
  }

  async addToPlaylist(event: MouseEvent, playlist: PlaylistSummary): Promise<void> {
    event.preventDefault();
    event.stopPropagation();
    if (this.addingId()) return;
    this.addingId.set(playlist.playlistId);
    this.message.set('');
    try {
      await firstValueFrom(this.playlistService.addVideo(playlist.playlistId, this.videoId));
      this.message.set(this.i18n.t('watchPlaylist.added').replace('{name}', playlist.name));
    } catch {
      this.message.set(this.i18n.t('watchPlaylist.addError').replace('{name}', playlist.name));
    } finally {
      this.addingId.set(null);
    }
  }

  stop(event: MouseEvent): void {
    event.preventDefault();
    event.stopPropagation();
  }
}
