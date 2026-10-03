import { CommonModule } from '@angular/common';
import { Component, OnDestroy, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Observable, catchError, forkJoin, map, of, switchMap, throwError } from 'rxjs';
import { Category, ContentService, VideoDetail } from '../../../core/content.service';
import { I18nService } from '../../../core/i18n.service';
import { PlaylistService, PlaylistSummary } from '../../../core/playlist.service';
import { PlanService } from '../../../core/plan.service';
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
  private readonly planService = inject(PlanService);
  readonly studio = inject(StudioDataService);
  private readonly i18n = inject(I18nService);

  readonly previewUrl = signal('');
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
  readonly canPromote = signal(false);
  readonly tags = signal<string[]>([]);
  readonly videoCards = signal<{ id: number; videoId: string; time: string }[]>([]);
  readonly publishedChannelVideos = () => {
    const channelId = this.video()?.channelId;
    const managedVideos = this.studio.videos().filter(item => item.channelId === channelId && item.videoId !== this.videoId
      && item.status === 'published' && item.moderationStatus === 'approved' && item.visibility === 'public' && Boolean(item.publishedAt));
    const knownIds = new Set(managedVideos.map(item => item.videoId));
    const existingCards = (this.video()?.videoCards ?? []).filter(card => !knownIds.has(card.videoId));
    return [...managedVideos, ...existingCards];
  };

  title = '';
  description = '';
  newTag = '';
  categoryId = '';
  visibility = 'public';
  promotionEnabled = false;
  selectedVideoCardId = '';
  newVideoCardTime = '';
  selectedPlaylistIds: string[] = [];
  private videoId = '';

  ngOnInit() {
    this.videoId = this.route.snapshot.paramMap.get('id') ?? '';
    this.planService.getMyPlan().subscribe({
      next: plan => this.canPromote.set(plan?.features?.['video_promotion'] === true),
      error: () => this.canPromote.set(false)
    });
    if (!this.videoId) {
      this.error.set(this.i18n.t('studioEdit.videoNotFound'));
      this.loading.set(false);
      return;
    }
    this.content.detail(this.videoId).subscribe({
      next: video => {
        this.video.set(video);
        this.studio.load(video.channelId);
        this.content.playback(video.videoId).subscribe({ next: playback => this.previewUrl.set(playback.renditions[0]?.url ?? ''), error: () => this.previewUrl.set('') });
        this.title = video.title;
        this.description = video.description ?? '';
        this.categoryId = video.categoryId ?? '';
        this.tags.set(video.tags ?? []);
        this.videoCards.set((video.videoCards ?? []).map((card, index) => ({ id: index + 1, videoId: card.videoId, time: this.formatCardTime(card.startSeconds) })));
        this.visibility = video.visibility;
        this.promotionEnabled = video.promotionEnabled ?? false;
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

  addTag() {
    const tag = this.newTag.trim().replace(/^#+/, '').toLowerCase().replace(/[^a-z0-9-]/g, '-').replace(/-+/g, '-').slice(0, 80);
    if (!tag || this.tags().includes(tag) || this.tags().length >= 20) return;
    this.tags.update(tags => [...tags, tag]);
    this.newTag = '';
  }

  removeTag(tag: string) {
    this.tags.update(tags => tags.filter(value => value !== tag));
  }

  private toSeconds(value: string): number {
    const match = value.trim().match(/^(\d+):([0-5]?\d)$/);
    return match ? Number(match[1]) * 60 + Number(match[2]) : -1;
  }

  private formatCardTime(seconds: number) {
    const total = Math.max(0, Math.floor(seconds));
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
  }

  videoCardTitle(videoId: string) { return this.publishedChannelVideos().find(item => item.videoId === videoId)?.title ?? this.video()?.videoCards?.find(item => item.videoId === videoId)?.title ?? ''; }
  videoCardThumbnail(videoId: string) { return this.publishedChannelVideos().find(item => item.videoId === videoId)?.thumbnailUrl ?? this.video()?.videoCards?.find(item => item.videoId === videoId)?.thumbnailUrl ?? ''; }
  isVideoCardAdded(videoId: string) { return this.videoCards().some(item => item.videoId === videoId); }
  isVideoCardValid(id: number) {
    const card = this.videoCards().find(item => item.id === id);
    if (!card) return false;
    const seconds = this.toSeconds(card.time);
    return seconds >= 0 && seconds < (this.video()?.duration ?? 0)
      && this.videoCards().filter(item => this.toSeconds(item.time) === seconds).length === 1;
  }
  updateVideoCardTime(id: number, time: string) { this.videoCards.update(cards => cards.map(item => item.id === id ? { ...item, time } : item)); }
  removeVideoCard(id: number) { this.videoCards.update(cards => cards.filter(item => item.id !== id)); }
  useCurrentTimeForVideoCard(id?: number) {
    const player = document.querySelector<HTMLVideoElement>('.video-preview video');
    if (!player) return;
    const time = this.formatCardTime(player.currentTime);
    if (id !== undefined) this.updateVideoCardTime(id, time);
    else this.newVideoCardTime = time;
  }
  addVideoCard() {
    const videoId = this.selectedVideoCardId;
    const seconds = this.toSeconds(this.newVideoCardTime || '0:00');
    if (!videoId || !this.publishedChannelVideos().some(item => item.videoId === videoId) || seconds < 0
      || seconds >= (this.video()?.duration ?? 0) || this.videoCards().length >= 5
      || this.videoCards().some(item => item.videoId === videoId || this.toSeconds(item.time) === seconds)) {
      this.error.set(this.i18n.t('upload.videoCardFieldsInvalid'));
      return;
    }
    this.videoCards.update(cards => [...cards, { id: Math.max(0, ...cards.map(item => item.id)) + 1, videoId, time: this.formatCardTime(seconds) }].sort((a, b) => this.toSeconds(a.time) - this.toSeconds(b.time)));
    this.selectedVideoCardId = '';
    this.newVideoCardTime = '';
    this.error.set('');
  }

  save() {
    const current = this.video();
    if (!current || this.saving()) return;
    const cleanTitle = this.title.trim();
    if (!cleanTitle) {
      this.error.set(this.i18n.t('studioEdit.titleRequired'));
      return;
    }
    const cards = this.videoCards();
    const eligibleIds = new Set(this.publishedChannelVideos().map(item => item.videoId));
    if (cards.length > 5 || cards.some(card => !eligibleIds.has(card.videoId) || !this.isVideoCardValid(card.id))
      || new Set(cards.map(card => card.videoId)).size !== cards.length) {
      this.error.set(this.i18n.t('upload.videoCardsInvalid'));
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
      clearCategory: !this.categoryId,
      tags: this.tags(),
      videoCards: cards.map(card => ({ videoId: card.videoId, startSeconds: this.toSeconds(card.time) })),
      ...(this.canPromote() ? { promotionEnabled: this.promotionEnabled } : {})
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
        this.promotionEnabled = updated.promotionEnabled ?? this.promotionEnabled;
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
      this.playlistService.addVideo(playlistId, videoId).pipe(catchError(error => error?.status === 409 && error?.error?.code === 'PLAYLIST_VIDEO_EXISTS'
        ? of(null) : throwError(() => ({ error: { message: this.i18n.t('studioEdit.partialSave') } }))))
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
