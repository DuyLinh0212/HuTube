import { CommonModule } from '@angular/common';
import { Component, OnDestroy, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Observable, catchError, forkJoin, map, of, switchMap } from 'rxjs';
import { Category, ContentService, VideoDetail } from '../../../core/content.service';
import { I18nService } from '../../../core/i18n.service';
import { PlaylistService, PlaylistSummary } from '../../../core/playlist.service';
import { StudioDataService } from '../../../core/studio-data.service';
import { TranslatePipe } from '../../../core/translate.pipe';

@Component({
  selector: 'app-video-edit-page',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, TranslatePipe],
  templateUrl: './video-edit-page.html',
  styleUrl: './video-edit-page.scss'
})
export class VideoEditPage implements OnInit, OnDestroy {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly content = inject(ContentService);
  private readonly playlistService = inject(PlaylistService);
  readonly studio = inject(StudioDataService);
  private readonly i18n = inject(I18nService);

  readonly video = signal<VideoDetail | null>(null);
  readonly categories = signal<Category[]>([]);
  readonly playlists = signal<PlaylistSummary[]>([]);
  readonly loading = signal(true);
  readonly saving = signal(false);
  readonly error = signal('');
  readonly success = signal('');
  readonly thumbnailMode = signal<'keep' | 'auto' | 'custom'>('auto');
  readonly customThumbnail = signal<File | null>(null);
  readonly customPreview = signal('');

  title = '';
  description = '';
  categoryId = '';
  visibility = 'public';
  selectedPlaylistIds: string[] = [];
  private videoId = '';

  ngOnInit() {
    this.videoId = this.route.snapshot.paramMap.get('id') ?? '';
    this.studio.load();
    if (!this.videoId) {
      this.error.set(this.i18n.t('studioEdit.videoNotFound'));
      this.loading.set(false);
      return;
    }
    this.content.detail(this.videoId).subscribe({
      next: video => {
        this.video.set(video);
        this.title = video.title;
        this.description = video.description ?? '';
        this.categoryId = video.categoryId ?? '';
        this.visibility = video.visibility;
        this.thumbnailMode.set('keep');
        this.loading.set(false);
      },
      error: () => {
        this.error.set(this.i18n.t('studioEdit.loadError'));
        this.loading.set(false);
      }
    });
    this.content.categories().subscribe({
      next: categories => this.categories.set(categories ?? []),
      error: () => this.categories.set([])
    });
    this.playlistService.mine().subscribe({
      next: items => this.playlists.set(items),
      error: () => this.playlists.set([])
    });
  }

  ngOnDestroy() {
    const preview = this.customPreview();
    if (preview) URL.revokeObjectURL(preview);
  }

  selectThumbnail(event: Event) {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (!file) return;
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
      this.error.set(this.i18n.t('studioEdit.thumbnailTypeError'));
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      this.error.set(this.i18n.t('studioEdit.thumbnailSizeError'));
      return;
    }
    const previous = this.customPreview();
    if (previous) URL.revokeObjectURL(previous);
    this.customThumbnail.set(file);
    this.customPreview.set(URL.createObjectURL(file));
    this.thumbnailMode.set('custom');
    this.error.set('');
  }

  togglePlaylist(playlistId: string, event: Event) {
    const checked = (event.target as HTMLInputElement).checked;
    this.selectedPlaylistIds = checked
      ? [...new Set([...this.selectedPlaylistIds, playlistId])]
      : this.selectedPlaylistIds.filter(id => id !== playlistId);
  }

  save() {
    const current = this.video();
    if (!current || this.saving()) return;
    const cleanTitle = this.title.trim();
    if (!cleanTitle) {
      this.error.set(this.i18n.t('studioEdit.titleRequired'));
      return;
    }

    this.saving.set(true);
    this.error.set('');
    this.success.set('');
    this.content.update(this.videoId, {
      title: cleanTitle,
      description: this.description.trim(),
      visibility: this.visibility,
      categoryId: this.categoryId || null,
      clearCategory: !this.categoryId
    }).pipe(
      switchMap(updated => this.saveThumbnail(updated)),
      switchMap(updated => this.addToPlaylists(updated.videoId).pipe(map(() => updated)))
    ).subscribe({
      next: updated => {
        this.video.set(updated);
        this.title = updated.title;
        this.description = updated.description ?? '';
        this.categoryId = updated.categoryId ?? '';
        this.visibility = updated.visibility;
        this.saving.set(false);
        this.success.set(this.i18n.t('studioEdit.saved'));
        setTimeout(() => this.success.set(''), 4000);
      },
      error: error => {
        this.saving.set(false);
        this.error.set(error?.error?.message || this.i18n.t('studioEdit.saveError'));
      }
    });
  }

  private saveThumbnail(video: VideoDetail) {
    const mode = this.thumbnailMode();
    if (mode === 'keep') return of(video);
    if (mode === 'custom') return this.content.updateThumbnail(video.videoId, this.customThumbnail(), false);
    return this.content.updateThumbnail(video.videoId, null, true);
  }

  private addToPlaylists(videoId: string): Observable<void> {
    if (!this.selectedPlaylistIds.length) return of(void 0);
    return forkJoin(this.selectedPlaylistIds.map(playlistId =>
      this.playlistService.addVideo(playlistId, videoId).pipe(catchError(() => of(null)))
    )).pipe(map(() => void 0));
  }

  visibilityLabel(value: string) {
    if (value === 'public') return this.i18n.t('studio.public');
    if (value === 'unlisted') return this.i18n.t('playlists.unlisted');
    return this.i18n.t('playlists.private');
  }

  formatDuration(seconds: number) {
    const total = Math.max(0, Math.round(seconds));
    const minutes = Math.floor(total / 60);
    return `${minutes}:${String(total % 60).padStart(2, '0')}`;
  }

  thumbnailUrl() {
    return this.customPreview() || this.video()?.thumbnailUrl || '';
  }

  backToContent() { void this.router.navigate(['/studio/content']); }
}
