import { Component, HostListener, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { catchError, forkJoin, of, switchMap } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { ChannelService } from '../../core/channel.service';
import { I18nService } from '../../core/i18n.service';
import { Playlist, PlaylistItem, PlaylistService, PlaylistSummary } from '../../core/playlist.service';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-playlists-page',
  imports: [FormsModule, RouterLink, TranslatePipe],
  templateUrl: './playlists-page.html',
  styleUrl: './playlists-page.scss'
})
export class PlaylistsPage {
  private readonly service = inject(PlaylistService);
  private readonly channels = inject(ChannelService);
  readonly auth = inject(AuthService);
  private readonly i18n = inject(I18nService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  readonly lists = signal<PlaylistSummary[]>([]);
  readonly playlist = signal<Playlist | null>(null);
  readonly previewById = signal<Record<string, Playlist | null>>({});
  readonly loading = signal(true);
  readonly error = signal('');
  readonly canManage = signal(false);
  readonly copied = signal(false);
  readonly editOpen = signal(false);
  name = '';
  description = '';
  visibility = 'private';
  channelHandle: string | null = null;
  channelId: string | null = null;
  busy = false;

  constructor() {
    this.route.paramMap.subscribe(params => {
      this.channelHandle = params.get('handle');
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
      error: () => { this.error.set(this.i18n.t('playlists.loadError')); this.loading.set(false); }
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
    this.auth.restore().pipe(switchMap(() => this.service.get(id))).subscribe({
      next: value => {
        this.playlist.set(value);
        this.canManage.set(this.auth.user()?.userId === value.userId);
        this.name = value.name;
        this.description = value.description ?? '';
        this.visibility = value.visibility;
        this.loading.set(false);
      },
      error: () => { this.error.set(this.i18n.t('playlists.detailError')); this.loading.set(false); }
    });
  }

  create() {
    if (!this.name.trim() || this.busy) return;
    this.busy = true;
    this.service.create(this.name, this.description, this.visibility).subscribe({
      next: value => { this.busy = false; void this.router.navigate(['/playlists', value.playlistId]); },
      error: () => { this.busy = false; this.error.set(this.i18n.t('playlists.createError')); }
    });
  }

  save() {
    const value = this.playlist();
    if (!value || !this.canManage() || this.busy) return;
    this.busy = true;
    this.service.update(value.playlistId, this.name, this.description, this.visibility).subscribe({
      next: updated => { this.playlist.set(updated); this.busy = false; this.editOpen.set(false); },
      error: () => { this.busy = false; this.error.set(this.i18n.t('playlists.saveError')); }
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

  deletePlaylist() {
    const value = this.playlist();
    if (!value || !this.canManage() || this.busy || !confirm(this.i18n.t('playlists.deleteConfirm'))) return;
    this.busy = true;
    this.service.remove(value.playlistId).subscribe({
      next: () => void this.router.navigate(['/playlists']),
      error: () => { this.busy = false; this.error.set(this.i18n.t('playlists.deleteError')); }
    });
  }

  playAll() {
    const value = this.playlist();
    if (!value) return;
    const index = value.items.findIndex(item => item.available);
    if (index < 0) { this.error.set(this.i18n.t('playlists.noPlayableVideo')); return; }
    void this.router.navigate(['/watch', value.items[index].videoId], { queryParams: { playlist: value.playlistId, index } });
  }

  shuffle() {
    const value = this.playlist();
    if (!value) return;
    const available = value.items
      .map((item, index) => ({ item, index }))
      .filter(entry => entry.item.available);
    if (!available.length) { this.error.set(this.i18n.t('playlists.noPlayableVideo')); return; }
    const selected = available[Math.floor(Math.random() * available.length)];
    void this.router.navigate(['/watch', selected.item.videoId], {
      queryParams: { playlist: value.playlistId, index: selected.index, shuffle: true }
    });
  }

  removeVideo(videoId: string) {
    const value = this.playlist();
    if (!value || !this.canManage() || this.busy || !confirm(this.i18n.t('playlists.removeVideoConfirm'))) return;
    this.busy = true;
    this.service.removeVideo(value.playlistId, videoId).subscribe({
      next: () => this.loadDetail(value.playlistId),
      error: () => { this.busy = false; this.error.set(this.i18n.t('playlists.removeVideoError')); }
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
      error: () => { this.busy = false; this.error.set(this.i18n.t('playlists.reorderError')); }
    });
  }

  previewItems(list: PlaylistSummary): PlaylistItem[] { return this.previewById()[list.playlistId]?.items.slice(0, 4) ?? []; }
  heroItems(value: Playlist): PlaylistItem[] { return value.items.slice(0, 4); }
  totalDuration(items: PlaylistItem[]) { return items.reduce((total, item) => total + (item.duration || 0), 0); }
  formatDuration(seconds: number) { const total = Math.max(0, Math.round(seconds)); const hours = Math.floor(total / 3600); const minutes = Math.floor((total % 3600) / 60); const remainder = total % 60; return hours ? this.i18n.t('playlists.durationHoursMinutes', { hours, minutes }) : this.i18n.t('playlists.durationMinutesSeconds', { minutes, seconds: remainder }); }
  formatUpdatedAt(value: string) { return new Intl.DateTimeFormat(this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US', { day: '2-digit', month: '2-digit', year: 'numeric' }).format(new Date(value)); }
  visibilityLabel(value: string) { return this.i18n.t(value === 'public' ? 'studio.public' : value === 'unlisted' ? 'playlists.unlisted' : 'playlists.private'); }
  share() {
    void navigator.clipboard?.writeText(location.href).then(() => {
      this.copied.set(true);
      window.setTimeout(() => this.copied.set(false), 1800);
    });
  }
  focusCreateForm() { document.querySelector<HTMLInputElement>('#playlist-name')?.focus(); }
  listBackLink() { return this.channelHandle ? ['/channel', this.channelHandle] : ['/home']; }

  @HostListener('document:keydown.escape')
  closeDialogsOnEscape() {
    if (this.editOpen()) this.closeEditDialog();
  }
}
