import { Component, HostListener, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { catchError, forkJoin, of, switchMap } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { ChannelService } from '../../core/channel.service';
import { ContentService, VideoCard, VideoDetail } from '../../core/content.service';
import { Playlist, PlaylistItem, PlaylistService, PlaylistSummary } from '../../core/playlist.service';

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
  readonly previewById = signal<Record<string, Playlist | null>>({});
  readonly loading = signal(true);
  readonly error = signal('');
  readonly videoOptions = signal<Array<VideoCard | VideoDetail>>([]);
  readonly videoLoading = signal(false);
  readonly canManage = signal(false);
  readonly copied = signal(false);
  readonly addVideoOpen = signal(false);
  readonly editOpen = signal(false);
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
      this.error.set('');
      if (id) this.loadDetail(id);
      else this.loadMine();
    });
  }

  loadMine() {
    this.loading.set(true);
    this.playlist.set(null);
    const request = this.channelHandle
      ? this.channels.getChannel(this.channelHandle).pipe(switchMap(channel => {
        this.channelId = channel.channelId;
        return this.service.channelMine(channel.channelId);
      }))
      : this.service.mine();
    request.subscribe({
      next: value => {
        this.lists.set(value);
        this.loading.set(false);
        this.loadPreviews(value);
      },
      error: () => { this.error.set('Không thể tải danh sách phát.'); this.loading.set(false); }
    });
  }

  private loadPreviews(lists: PlaylistSummary[]) {
    if (!lists.length) { this.previewById.set({}); return; }
    const requests = lists.slice(0, 12).map(list => this.service.get(list.playlistId).pipe(catchError(() => of(null))));
    forkJoin(requests).subscribe(details => {
      const previews: Record<string, Playlist | null> = {};
      lists.slice(0, 12).forEach((list, index) => previews[list.playlistId] = details[index]);
      this.previewById.set(previews);
    });
  }

  loadDetail(id: string) {
    this.loading.set(true);
    this.playlist.set(null);
    this.service.get(id).subscribe({
      next: value => {
        this.playlist.set(value);
        this.canManage.set(this.auth.user()?.userId === value.userId);
        this.name = value.name;
        this.description = value.description ?? '';
        this.visibility = value.visibility;
        this.loading.set(false);
      },
      error: () => { this.error.set('Không thể tải danh sách phát hoặc danh sách phát không khả dụng.'); this.loading.set(false); }
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
        this.error.set(this.playlistType === 'channel' ? 'Không thể tải video của kênh.' : 'Không thể tải danh sách video công khai.');
      }
    });
  }

  create() {
    if (!this.name.trim() || this.busy) return;
    this.busy = true;
    this.service.create(this.name, this.description, this.visibility, this.playlistType).subscribe({
      next: value => { this.busy = false; void this.router.navigate(['/playlists', value.playlistId]); },
      error: () => { this.busy = false; this.error.set('Không thể tạo danh sách phát.'); }
    });
  }

  save() {
    const value = this.playlist();
    if (!value || !this.canManage() || this.busy) return;
    this.busy = true;
    this.service.update(value.playlistId, this.name, this.description, this.visibility).subscribe({
      next: updated => { this.playlist.set(updated); this.busy = false; this.editOpen.set(false); },
      error: () => { this.busy = false; this.error.set('Không thể lưu danh sách phát.'); }
    });
  }

  openEditDialog() {
    const value = this.playlist();
    if (!value || !this.canManage()) return;
    this.name = value.name;
    this.description = value.description ?? '';
    this.visibility = value.visibility;
    this.editOpen.set(true);
  }

  closeEditDialog() {
    if (!this.busy) this.editOpen.set(false);
  }

  openAddVideoDialog() {
    if (!this.canManage()) return;
    this.addVideoOpen.set(true);
    this.searchVideos();
    window.setTimeout(() => document.querySelector<HTMLInputElement>('#playlist-video-search')?.focus());
  }

  closeAddVideoDialog() {
    if (!this.busy) this.addVideoOpen.set(false);
  }

  deletePlaylist() {
    const value = this.playlist();
    if (!value || !this.canManage() || this.busy || !confirm('Xóa danh sách phát này?')) return;
    this.busy = true;
    this.service.remove(value.playlistId).subscribe({
      next: () => void this.router.navigate(['/playlists']),
      error: () => { this.busy = false; this.error.set('Không thể xóa danh sách phát.'); }
    });
  }

  add(videoId: string) {
    const value = this.playlist();
    if (!value || !this.canManage() || !videoId || this.busy) return;
    this.busy = true;
    this.service.addVideo(value.playlistId, videoId).subscribe({
      next: updated => { this.playlist.set(updated); this.busy = false; this.searchVideos(); },
      error: () => { this.busy = false; this.error.set('Video không hợp lệ hoặc đã có trong danh sách phát.'); }
    });
  }

  playAll() {
    const value = this.playlist();
    if (!value) return;
    const index = value.items.findIndex(item => item.available);
    if (index < 0) { this.error.set('Danh sách phát chưa có video khả dụng để phát.'); return; }
    void this.router.navigate(['/watch', value.items[index].videoId], { queryParams: { playlist: value.playlistId, index } });
  }

  shuffle() {
    const value = this.playlist();
    if (!value) return;
    const available = value.items
      .map((item, index) => ({ item, index }))
      .filter(entry => entry.item.available);
    if (!available.length) { this.error.set('Danh sách phát chưa có video khả dụng để phát.'); return; }
    const selected = available[Math.floor(Math.random() * available.length)];
    void this.router.navigate(['/watch', selected.item.videoId], {
      queryParams: { playlist: value.playlistId, index: selected.index, shuffle: true }
    });
  }

  removeVideo(videoId: string) {
    const value = this.playlist();
    if (!value || !this.canManage() || this.busy) return;
    this.busy = true;
    this.service.removeVideo(value.playlistId, videoId).subscribe({
      next: () => this.loadDetail(value.playlistId),
      error: () => { this.busy = false; this.error.set('Không thể xóa video khỏi danh sách phát.'); }
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
      error: () => { this.busy = false; this.error.set('Không thể lưu thứ tự video.'); }
    });
  }

  previewItems(list: PlaylistSummary): PlaylistItem[] { return this.previewById()[list.playlistId]?.items.slice(0, 4) ?? []; }
  heroItems(value: Playlist): PlaylistItem[] { return value.items.slice(0, 4); }
  totalDuration(items: PlaylistItem[]) { return items.reduce((total, item) => total + (item.duration || 0), 0); }
  formatDuration(seconds: number) { const total = Math.max(0, Math.round(seconds)); const hours = Math.floor(total / 3600); const minutes = Math.floor((total % 3600) / 60); const remainder = total % 60; return hours ? `${hours} giờ ${minutes} phút` : `${minutes} phút ${remainder} giây`; }
  formatUpdatedAt(value: string) { return new Intl.DateTimeFormat('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric' }).format(new Date(value)); }
  visibilityLabel(value: string) { return value === 'public' ? 'Công khai' : value === 'unlisted' ? 'Không công khai' : 'Riêng tư'; }
  playlistTypeLabel(value: string) { return value === 'channel' ? 'Danh sách phát của kênh' : 'Bộ sưu tập cá nhân'; }
  share() {
    void navigator.clipboard?.writeText(location.href).then(() => {
      this.copied.set(true);
      window.setTimeout(() => this.copied.set(false), 1800);
    });
  }
  focusCreateForm() { document.querySelector<HTMLInputElement>('#playlist-name')?.focus(); }
  focusAddVideo() { this.openAddVideoDialog(); }
  listBackLink() { return this.channelHandle ? ['/channel', this.channelHandle] : ['/home']; }

  @HostListener('document:keydown.escape')
  closeDialogsOnEscape() {
    if (this.editOpen()) this.closeEditDialog();
    else if (this.addVideoOpen()) this.closeAddVideoDialog();
  }
}
