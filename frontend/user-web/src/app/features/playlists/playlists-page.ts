import { ResultNoticeComponent } from '@dalitu/ui/result-notice.component';
import { FeedbackService } from '@dalitu/ui/feedback.service';
import { Component, HostListener, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { catchError, forkJoin, of, switchMap } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { ChannelService } from '../../core/channel.service';
import { I18nService } from '../../core/i18n.service';
import { Playlist, PlaylistItem, PlaylistService, PlaylistSummary } from '../../core/playlist.service';
import { TranslatePipe } from '../../core/translate.pipe';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { PLAYLIST_LIBRARY_TRANSLATIONS } from './playlists.translations';

@Component({
  selector: 'app-playlists-page',
  imports: [ResultNoticeComponent, FormsModule, RouterLink, TranslatePipe, LocaleNumberPipe],
  templateUrl: './playlists-page.html',
  styleUrl: './playlists-page.scss'
})
export class PlaylistsPage {
  private readonly feedback = inject(FeedbackService);
  private readonly service = inject(PlaylistService);
  private readonly channels = inject(ChannelService);
  readonly auth = inject(AuthService);
  private readonly i18n = inject(I18nService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  readonly lists = signal<PlaylistSummary[]>([]);
  readonly listQuery = signal('');
  readonly listVisibility = signal('all');
  readonly listSort = signal('updated');
  readonly listPage = signal(1);
  readonly listPageSize = signal(20);
  readonly filteredLists = computed(() => {
    const normalize = (text: string) => text.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/đ/g, 'd').toLowerCase();
    const query = normalize(this.listQuery().trim());
    const items = this.lists().filter(item => (!query || normalize(item.name).includes(query)) &&
      (this.listVisibility() === 'all' || item.visibility === this.listVisibility()));
    return items.sort((a, b) => this.listSort() === 'name'
      ? a.name.localeCompare(b.name, this.i18n.currentLang(), { numeric: true, sensitivity: 'base' })
      : this.listSort() === 'videos' ? b.itemCount - a.itemCount
      : Date.parse(b.updatedAt) - Date.parse(a.updatedAt));
  });
  readonly listPageCount = computed(() => Math.max(1, Math.ceil(this.filteredLists().length / this.listPageSize())));
  readonly currentListPage = computed(() => Math.min(this.listPage(), this.listPageCount()));
  readonly visibleLists = computed(() => this.filteredLists().slice((this.currentListPage() - 1) * this.listPageSize(), this.currentListPage() * this.listPageSize()));
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
    this.i18n.registerTranslations(PLAYLIST_LIBRARY_TRANSLATIONS);
    this.route.queryParamMap.subscribe(params => {
      this.listQuery.set(params.get('q') ?? '');
      this.listVisibility.set(['public', 'unlisted', 'private'].includes(params.get('visibility') ?? '') ? params.get('visibility')! : 'all');
      this.listPageSize.set(params.get('pageSize') === '50' ? 50 : 20);
      this.listSort.set(['name', 'videos'].includes(params.get('sort') ?? '') ? params.get('sort')! : 'updated');
      const page = Number(params.get('page'));
      this.listPage.set(Number.isSafeInteger(page) && page > 0 ? page : 1);
    });
    this.route.paramMap.subscribe(params => {
      this.channelHandle = params.get('handle');
      const id = params.get('id');
      this.error.set('');
      if (id) this.loadDetail(id);
      else this.loadMine();
    });
  }

  filterLists(query = this.listQuery(), visibility = this.listVisibility(), pageSize = this.listPageSize()) {
    void this.router.navigate([], { relativeTo: this.route, queryParamsHandling: 'merge',
      queryParams: { q: query || null, visibility: visibility === 'all' ? null : visibility, page: 1, pageSize } });
  }

  changeListPage(page: number) {
    void this.router.navigate([], { relativeTo: this.route, queryParamsHandling: 'merge',
      queryParams: { page: Math.max(1, Math.min(this.listPageCount(), page)) } });
  }

  sortLists(sort: string) {
    void this.router.navigate([], { relativeTo: this.route, queryParamsHandling: 'merge',
      queryParams: { sort: sort === 'updated' ? null : sort, page: 1 } });
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
    if (lists.every(list => Array.isArray(list.previewItems))) {
      this.previewById.set(Object.fromEntries(lists.map(list => [list.playlistId,
        { ...list, createdAt: list.updatedAt, items: list.previewItems! }])));
      return;
    }
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
        if (this.canManage() && this.route.snapshot.queryParamMap.get('edit') === '1') this.openEditDialog();
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
      next: updated => { this.playlist.set(updated); this.busy = false; this.closeEditDialog(); },
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
    if (this.busy) return;
    this.editOpen.set(false);
    if (this.route.snapshot.queryParamMap.has('edit')) {
      void this.router.navigate([], { relativeTo: this.route, queryParamsHandling: 'merge',
        queryParams: { edit: null }, replaceUrl: true });
    }
  }

  async deletePlaylist(summary?: PlaylistSummary) {
    const value = summary ?? this.playlist();
    const canManage = summary ? summary.userId === this.auth.user()?.userId : this.canManage();
    if (!value || !canManage || this.busy || !(await this.feedback.confirm(this.i18n.t('playlists.deleteConfirm'), { tone: 'danger' }))) return;
    this.busy = true;
    this.service.remove(value.playlistId).subscribe({
      next: () => {
        this.busy = false;
        if (summary) this.lists.update(items => items.filter(item => item.playlistId !== value.playlistId));
        else void this.router.navigate(['/playlists']);
      },
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

  async removeVideo(videoId: string) {
    const value = this.playlist();
    if (!value || !this.canManage() || this.busy || !(await this.feedback.confirm(this.i18n.t('playlists.removeVideoConfirm'), { tone: 'danger' }))) return;
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
  coverUrl(list: PlaylistSummary): string | null { return list.coverUrl || this.previewItems(list).find(item => item.thumbnailUrl)?.thumbnailUrl || null; }
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
    document.querySelectorAll<HTMLDetailsElement>('.card-options[open]').forEach(menu => {
      menu.open = false;
      menu.querySelector<HTMLElement>('summary')?.focus();
    });
  }

  @HostListener('document:click', ['$event'])
  closeListMenus(event: MouseEvent) {
    const target = event.target;
    document.querySelectorAll<HTMLDetailsElement>('.card-options[open]').forEach(menu => {
      if (!(target instanceof Node) || !menu.contains(target)) menu.open = false;
    });
  }
}
