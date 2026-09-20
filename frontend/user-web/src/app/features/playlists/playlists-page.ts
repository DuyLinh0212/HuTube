import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Playlist, PlaylistService, PlaylistSummary } from '../../core/playlist.service';
import { ContentService, VideoCard, VideoDetail } from '../../core/content.service';
import { ChannelService } from '../../core/channel.service';
import { AuthService } from '../../core/auth.service';
import { switchMap } from 'rxjs';

@Component({
  selector: 'app-playlists-page',
  imports: [FormsModule, RouterLink],
  templateUrl: './playlists-page.html',
  styleUrl: './playlists-page.scss'
})
export class PlaylistsPage {
  private readonly service = inject(PlaylistService);
  private readonly content = inject(ContentService);
  private readonly channels = inject(ChannelService);
  readonly auth = inject(AuthService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  readonly lists = signal<PlaylistSummary[]>([]);
  readonly playlist = signal<Playlist | null>(null);
  readonly loading = signal(true);
  readonly error = signal('');
  readonly videoOptions = signal<Array<VideoCard | VideoDetail>>([]);
  readonly videoLoading = signal(false);
  readonly canManage = signal(false);
  name = '';
  description = '';
  visibility = 'private';
  videoSearch = '';
  channelHandle: string | null = null;
  channelId: string | null = null;
  playlistType = 'personal';
  busy = false;

  constructor() {
    this.route.paramMap.subscribe(params => {
      this.channelHandle = params.get('handle');
      this.playlistType = this.channelHandle ? 'channel' : 'personal';
      const id = params.get('id');
      if (id) this.loadDetail(id);
      else this.loadMine();
    });
  }

  loadMine() {
    this.loading.set(true);
    const request = this.channelHandle
      ? this.channels.getChannel(this.channelHandle).pipe(switchMap(channel => {
        this.channelId = channel.channelId;
        return this.service.channelMine(channel.channelId);
      }))
      : this.service.mine();
    request.subscribe({
      next: value => { this.lists.set(value); this.loading.set(false); },
      error: () => { this.error.set('Không thể tải playlist.'); this.loading.set(false); }
    });
  }

  loadDetail(id: string) {
    this.loading.set(true);
    this.service.get(id).subscribe({
      next: value => {
        this.playlist.set(value);
        this.canManage.set(this.auth.user()?.userId === value.userId);
        this.name = value.name;
        this.description = value.description ?? '';
        this.visibility = value.visibility;
        this.loading.set(false);
        if (this.canManage()) this.searchVideos();
      },
      error: () => { this.error.set('Không thể tải playlist hoặc playlist không khả dụng.'); this.loading.set(false); }
    });
  }

  searchVideos() {
    if (!this.playlist()) return;
    this.videoLoading.set(true);
    const query = this.videoSearch.trim();
    const request = this.playlistType === 'channel'
      ? this.channels.getMyChannel().pipe(switchMap(channel => this.content.managed(channel.channelId, 1, 50, query)))
      : this.content.search({ q: query || undefined, sort: 'newest', page: 1, pageSize: 50 });
    request.subscribe({
      next: value => {
        const existing = new Set(this.playlist()?.items.map(item => item.videoId));
        this.videoOptions.set(value.items.filter(video => !existing.has(video.videoId)));
        this.videoLoading.set(false);
      },
      error: () => {
        this.videoOptions.set([]);
        this.videoLoading.set(false);
        this.error.set(this.playlistType === 'channel'
          ? 'Không thể tải danh sách video của kênh.'
          : 'Không thể tải danh sách video công khai.');
      }
    });
  }

  create() {
    if (!this.name.trim() || this.busy) return;
    this.busy = true;
    this.service.create(this.name, this.description, this.visibility, this.playlistType).subscribe({
      next: value => { this.busy = false; void this.router.navigate(['/playlists', value.playlistId]); },
      error: () => { this.busy = false; this.error.set('Không thể tạo playlist.'); }
    });
  }

  save() {
    const value = this.playlist();
    if (!value || !this.canManage() || this.busy) return;
    this.busy = true;
    this.service.update(value.playlistId, this.name, this.description, this.visibility).subscribe({
      next: updated => { this.playlist.set(updated); this.busy = false; },
      error: () => { this.busy = false; this.error.set('Không thể lưu playlist.'); }
    });
  }

  deletePlaylist() {
    const value = this.playlist();
    if (!value || !this.canManage() || this.busy || !confirm('Xóa playlist này?')) return;
    this.busy = true;
    this.service.remove(value.playlistId).subscribe({
      next: () => void this.router.navigate(['/playlists']),
      error: () => { this.busy = false; this.error.set('Không thể xóa playlist.'); }
    });
  }

  add(videoId: string) {
    const value = this.playlist();
    if (!value || !this.canManage() || !videoId || this.busy) return;
    this.busy = true;
    this.service.addVideo(value.playlistId, videoId).subscribe({
      next: updated => { this.playlist.set(updated); this.busy = false; this.searchVideos(); },
      error: () => { this.busy = false; this.error.set('Video không hợp lệ hoặc đã có trong playlist.'); }
    });
  }

  playAll() {
    const value = this.playlist();
    if (!value) return;
    const index = value.items.findIndex(item => item.available);
    if (index < 0) {
      this.error.set('Playlist không có video khả dụng để phát.');
      return;
    }
    void this.router.navigate(['/watch', value.items[index].videoId], {
      queryParams: { playlist: value.playlistId, index }
    });
  }

  removeVideo(videoId: string) {
    const value = this.playlist();
    if (!value || !this.canManage() || this.busy) return;
    this.busy = true;
    this.service.removeVideo(value.playlistId, videoId).subscribe({
      next: () => this.loadDetail(value.playlistId),
      error: () => { this.busy = false; this.error.set('Không thể xóa video.'); }
    });
  }

  move(index: number, delta: number) {
    const value = this.playlist();
    if (!value || !this.canManage() || this.busy) return;
    const items = [...value.items];
    const target = index + delta;
    if (target < 0 || target >= items.length) return;
    [items[index], items[target]] = [items[target], items[index]];
    this.busy = true;
    this.service.reorder(value.playlistId, items.map(item => item.videoId)).subscribe({
      next: updated => { this.playlist.set(updated); this.busy = false; },
      error: () => { this.busy = false; this.error.set('Không thể lưu thứ tự.'); }
    });
  }
}
