import { Component, ElementRef, HostListener, ViewChild, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { ChannelDetail, ChannelService } from '../../core/channel.service';
import { CommentItem, ContentService, Playback, Rendition, VideoCard, VideoDetail, ViolationType } from '../../core/content.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';
import { PlaylistItem, PlaylistService, PlaylistSummary } from '../../core/playlist.service';
import { ReportModalComponent } from '../../shared/report-modal/report-modal.component';

@Component({
  selector: 'app-watch-page',
  imports: [LocaleDatePipe, LocaleNumberPipe, FormsModule, RouterLink, TranslatePipe, ReportModalComponent],
  templateUrl: './watch-page.html',
  styleUrl: './watch-page.scss'
})
export class WatchPage {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly content = inject(ContentService);
  private readonly channels = inject(ChannelService);
  private readonly playlists = inject(PlaylistService);
  readonly i18n = inject(I18nService);
  readonly auth = inject(AuthService);

  readonly video = signal<VideoDetail | null>(null);
  readonly playback = signal<Playback | null>(null);
  readonly activeRendition = signal<Rendition | null>(null);
  readonly relatedVideos = signal<VideoCard[]>([]);
  readonly channel = signal<ChannelDetail | null>(null);
  readonly comments = signal<CommentItem[]>([]);
  readonly repliesByComment = signal<Record<string, CommentItem[]>>({});
  readonly expandedReplies = signal<Record<string, boolean>>({});
  readonly repliesLoading = signal<Record<string, boolean>>({});
  readonly quality = signal('');
  readonly speed = signal(1);
  readonly error = signal('');
  readonly loading = signal(true);
  readonly replyTo = signal<string | null>(null);
  readonly myChannelId = signal('');
  readonly violationTypes = signal<ViolationType[]>([]);
  readonly actionMessage = signal('');
  readonly autoplay = signal(true);
  readonly recommendationFilter = signal<'all' | 'related' | 'channel' | 'category'>('all');
  readonly isPlaying = signal(false);
  readonly muted = signal(false);
  readonly volume = signal(1);
  readonly currentTime = signal(0);
  readonly totalDuration = signal(0);
  readonly miniPlayer = signal(false);
  readonly pipActive = signal(false);
  readonly shareOpen = signal(false);
  readonly shareUrl = signal('');
  readonly downloadOptions = signal<Rendition[]>([]);
  readonly downloadOpen = signal(false);
  readonly downloadBusy = signal(false);
  readonly playlistPickerOpen = signal(false);
  readonly playlistOptions = signal<PlaylistSummary[]>([]);
  readonly playlistLoading = signal(false);
  readonly playlistAddingId = signal<string | null>(null);
  readonly addedPlaylistIds = signal<Record<string, boolean>>({});
  readonly subscribed = signal(false);
  readonly subscriptionNotificationsEnabled = signal(false);
  readonly subscriberCount = signal(0);
  readonly visibleRelatedVideos = computed(() => {
    return this.relatedVideos();
  });
  readonly speeds = [.25, .5, .75, 1, 1.25, 1.5, 1.75, 2];

  commentText = '';
  replyText = '';
  private readonly videoId: string;
  private lastSaved = 0;
  private pendingSeek: number | null = null;
  private resumeApplied = false;
  private continuePlaying = false;
  private autoPlayAttempted = false;
  private playlistQueue: PlaylistItem[] = [];
  private playlistIndex = -1;

  @ViewChild('player') playerRef?: ElementRef<HTMLVideoElement>;
  @ViewChild('playerStage') playerStageRef?: ElementRef<HTMLElement>;

  constructor() {
    this.videoId = this.route.snapshot.paramMap.get('id') ?? '';
    const playlistId = this.route.snapshot.queryParamMap.get('playlist');
    this.playlistIndex = Number(this.route.snapshot.queryParamMap.get('index') ?? -1);
    if (playlistId) {
      this.playlists.get(playlistId).subscribe({
        next: playlist => this.playlistQueue = playlist.items,
        error: () => this.playlistQueue = []
      });
    }
    // Restore the refresh-cookie session before loading the detail/comments.
    // Otherwise a hard refresh sends these public requests anonymously and the
    // API cannot include the current user's reaction, rating, or comment votes.
    this.auth.restore().subscribe({
      next: () => this.loadPageData(),
      error: () => this.loadPageData()
    });
  }

  private loadPageData() {
    this.channels.getMyChannel().subscribe({ next: channel => this.myChannelId.set(channel.channelId), error: () => {} });
    this.content.violationTypes().subscribe({ next: types => this.violationTypes.set(types), error: () => {} });

    this.content.detail(this.videoId).subscribe({
      next: video => {
        this.video.set(video);
        if (video.videoUrl) {
          this.setAutoplayRendition({ quality: this.i18n.t('watch.sourceQuality'), width: 0, height: 0, fileSize: video.fileSize, url: video.videoUrl });
        }
        this.channels.getChannel(video.channelHandle).subscribe({
          next: channel => {
            this.channel.set(channel);
            this.subscriberCount.set(channel.subscriberCount);
            if (this.auth.user()) {
              this.channels.getSubscriptionStatus(channel.channelId).subscribe({
                next: sub => {
                  this.subscribed.set(sub.status === 'active');
                  this.subscriptionNotificationsEnabled.set(sub.status === 'active' && sub.notificationsEnabled);
                },
                error: () => {
                  this.subscribed.set(false);
                  this.subscriptionNotificationsEnabled.set(false);
                }
              });
            }
          },
          error: () => {}
        });
        this.loading.set(false);
      },
      error: () => {
        this.error.set(this.i18n.t('watch.unavailableError'));
        this.loading.set(false);
      }
    });

    this.content.playback(this.videoId).subscribe({
      next: playback => {
        this.playback.set(playback);
        this.totalDuration.set(playback.duration);
        if (!this.resumeApplied && playback.resumeAtSeconds > 0) this.currentTime.set(playback.resumeAtSeconds);
        const best = playback.renditions.reduce<Rendition | null>((current, item) => !current || item.height > current.height ? item : current, null);
        if (best) {
          this.quality.set(best.quality);
          this.setAutoplayRendition(best);
        }
      },
      error: () => this.actionMessage.set(this.i18n.t('watch.playbackQualityError'))
    });

    this.content.comments(this.videoId).subscribe({
      next: value => {
        const items = value.items ?? [];
        this.comments.set(items);
        // Keep existing replies visible after navigating directly to a video.
        for (const comment of items.filter(item => item.replyCount > 0)) this.loadReplies(comment, true);
      },
      error: () => this.comments.set([])
    });
    this.content.feed('home', 1, 12).subscribe({
      next: value => this.relatedVideos.set((value.items ?? []).filter(item => item.videoId !== this.videoId).slice(0, 8)),
      error: () => this.relatedVideos.set([])
    });
  }

  changeQuality(value: string) {
    const player = this.playerRef?.nativeElement;
    const rendition = this.playback()?.renditions.find(item => item.quality === value);
    if (!rendition) return;
    if (player) {
      this.pendingSeek = player.currentTime;
      this.continuePlaying = !player.paused;
    }
    this.quality.set(value);
    this.activeRendition.set(rendition);
  }

  onMetadata() {
    const player = this.playerRef?.nativeElement;
    if (!player) return;
    this.totalDuration.set(Number.isFinite(player.duration) ? player.duration : this.playback()?.duration ?? 0);
    if (this.pendingSeek !== null) {
      player.currentTime = Math.min(this.pendingSeek, player.duration || this.pendingSeek);
      this.pendingSeek = null;
    } else if (!this.resumeApplied && (this.playback()?.resumeAtSeconds ?? 0) > 0) {
      player.currentTime = this.playback()!.resumeAtSeconds;
      this.resumeApplied = true;
    }
    player.playbackRate = this.speed();
    if (this.continuePlaying) {
      this.continuePlaying = false;
      void player.play();
    }
    if (!this.autoPlayAttempted) {
      this.autoPlayAttempted = true;
      this.tryAutoplay(player);
    }
    this.currentTime.set(player.currentTime);
  }

  private tryAutoplay(player: HTMLVideoElement) {
    void player.play().catch(() => {
      // Browsers commonly reject audible autoplay. A muted fallback still
      // starts the requested video without making sound unexpectedly.
      player.muted = true;
      this.muted.set(true);
      return player.play().catch(() => {
        this.actionMessage.set('Trình duyệt đang chặn tự động phát. Hãy bấm nút phát để xem video.');
      });
    });
  }

  private setAutoplayRendition(rendition: Rendition) {
    if (this.activeRendition()?.url !== rendition.url) {
      const player = this.playerRef?.nativeElement;
      if (player && Number.isFinite(player.currentTime)) {
        this.pendingSeek = player.currentTime;
        this.continuePlaying = !player.paused;
      }
      this.autoPlayAttempted = false;
    }
    this.activeRendition.set(rendition);
  }

  onPlayerError() {
    const player = this.playerRef?.nativeElement;
    const current = this.activeRendition();
    const lowerRendition = (this.playback()?.renditions ?? [])
      .filter(item => item.url !== current?.url && (current?.height ? item.height < current.height : true))
      .sort((a, b) => b.height - a.height)[0];

    if (lowerRendition) {
      if (player && Number.isFinite(player.currentTime)) this.pendingSeek = player.currentTime;
      this.continuePlaying = true;
      this.quality.set(lowerRendition.quality);
      this.setAutoplayRendition(lowerRendition);
      this.actionMessage.set(this.i18n.t('watch.lowerRenditionFallback'));
      return;
    }

    const source = this.video();
    if (source?.videoUrl && source.videoUrl !== current?.url) {
      if (player && Number.isFinite(player.currentTime)) this.pendingSeek = player.currentTime;
      this.continuePlaying = true;
      this.setAutoplayRendition({ quality: this.i18n.t('watch.sourceQuality'), width: 0, height: 0, fileSize: source.fileSize, url: source.videoUrl });
      this.actionMessage.set(this.i18n.t('watch.sourceFallback'));
      return;
    }
    this.actionMessage.set(this.i18n.t('watch.renditionError'));
  }

  changeSpeed(value: number | string) {
    const next = Number(value);
    this.speed.set(next);
    if (this.playerRef) this.playerRef.nativeElement.playbackRate = next;
  }

  togglePlayback() {
    const player = this.playerRef?.nativeElement;
    if (!player) return;
    if (player.paused) {
      void player.play().catch(() => this.actionMessage.set(this.i18n.t('watch.playError')));
    } else {
      player.pause();
    }
  }

  onPlaybackState(playing: boolean) {
    this.isPlaying.set(playing);
  }

  onEnded() {
    this.isPlaying.set(false);
    this.currentTime.set(this.totalDuration());
    if (!this.autoplay()) return;
    const next = this.playlistQueue.slice(this.playlistIndex + 1).find(item => item.available);
    if (next) {
      const nextIndex = this.playlistQueue.findIndex(item => item.playlistVideoId === next.playlistVideoId);
      const tree = this.router.createUrlTree(['/watch', next.videoId], {
        queryParams: { playlist: this.route.snapshot.queryParamMap.get('playlist'), index: nextIndex }
      });
      window.location.assign(this.router.serializeUrl(tree));
      return;
    }
    if (this.route.snapshot.queryParamMap.has('playlist')) return;
    const following = this.visibleRelatedVideos()[0];
    if (following) window.location.assign(this.router.serializeUrl(this.router.createUrlTree(['/watch', following.videoId])));
  }

  toggleMute() {
    const player = this.playerRef?.nativeElement;
    if (!player) return;
    player.muted = !player.muted;
    this.muted.set(player.muted);
  }

  setVolume(value: number | string) {
    const next = Math.max(0, Math.min(1, Number(value)));
    const player = this.playerRef?.nativeElement;
    if (!player) return;
    player.volume = next;
    player.muted = next === 0;
    this.volume.set(next);
    this.muted.set(player.muted);
  }

  ratingSelected(item: VideoDetail, star: number) {
    return (item.viewerState?.rating ?? 0) >= star;
  }

  seekFromSlider(value: number | string) {
    const next = Math.max(0, Number(value) || 0);
    const player = this.playerRef?.nativeElement;
    if (!player) return;
    player.currentTime = next;
    this.currentTime.set(next);
  }

  seekBy(seconds: number) {
    const player = this.playerRef?.nativeElement;
    if (!player) return;
    this.seekFromSlider(player.currentTime + seconds);
  }

  toggleFullscreen() {
    const element = this.playerStageRef?.nativeElement;
    if (!element) return;
    if (document.fullscreenElement) {
      void document.exitFullscreen();
    } else {
      void element.requestFullscreen();
    }
  }

  toggleMiniPlayer() {
    if (document.fullscreenElement) void document.exitFullscreen();
    this.miniPlayer.update(value => !value);
  }

  supportsPictureInPicture(): boolean {
    const player = this.playerRef?.nativeElement;
    return !!document.pictureInPictureEnabled && !!player && typeof player.requestPictureInPicture === 'function';
  }

  async togglePictureInPicture(): Promise<void> {
    const player = this.playerRef?.nativeElement;
    if (!this.supportsPictureInPicture() || !player) {
      this.actionMessage.set(this.i18n.t('watch.pictureInPictureUnsupported'));
      return;
    }

    try {
      if (document.pictureInPictureElement === player) await document.exitPictureInPicture();
      else await player.requestPictureInPicture();
    } catch {
      this.actionMessage.set(this.i18n.t('watch.pictureInPictureFailed'));
    }
  }

  seekTo(seconds: number) {
    const player = this.playerRef?.nativeElement;
    if (!player) return;
    player.currentTime = Math.max(0, Math.min(seconds, player.duration || seconds));
    if (player.paused) void player.play();
  }

  onProgress() {
    const player = this.playerRef?.nativeElement;
    if (!player) return;
    this.currentTime.set(player.currentTime);
    if (!this.auth.user() || Math.abs(player.currentTime - this.lastSaved) < 10) return;
    this.lastSaved = player.currentTime;
    this.content.progress(this.videoId, Math.floor(player.currentTime)).subscribe();
  }

  react(type: 'like' | 'dislike') {
    if (!this.requireAuthentication(this.i18n.t('watch.loginReaction'))) return;
    const item = this.video();
    if (!item) return;
    const next = item.viewerState?.reaction === type ? null : type;
    this.content.reactVideo(item.videoId, next).subscribe({
      next: result => this.video.set({
        ...item,
        stats: { ...item.stats, likes: result.likes, dislikes: result.dislikes },
        viewerState: { ...this.viewerState(item), reaction: result.myReaction as 'like' | 'dislike' | null }
      }),
      error: error => this.actionMessage.set(this.readError(error) || this.i18n.t('watch.interactionError'))
    });
  }

  rate(score: number | null) {
    if (!this.requireAuthentication(this.i18n.t('watch.loginRating'))) return;
    const item = this.video();
    if (!item) return;
    this.content.rate(item.videoId, score).subscribe({
      next: result => {
        this.video.set({
          ...item,
          stats: {
            ...item.stats,
            averageRating: result.average,
            ratingCount: result.count
          },
          viewerState: { ...this.viewerState(item), rating: result.myRating }
        });
        this.actionMessage.set(this.i18n.t('watch.ratingSaved'));
      },
      error: error => this.actionMessage.set(this.readError(error) || this.i18n.t('watch.loginRating'))
    });
  }

  share() {
    const item = this.video();
    if (!item) return;
    this.shareUrl.set(window.location.href);
    this.shareOpen.set(true);
    // A guest may share the public URL. Only authenticated viewers can persist
    // the share event because the API endpoint is protected.
    if (!this.auth.user()) {
      this.actionMessage.set(this.i18n.t('watch.shareReadyPublic'));
      return;
    }
    this.content.share(item.videoId).subscribe({
      next: result => {
        if (result?.url) this.shareUrl.set(this.absoluteUrl(result.url));
        this.actionMessage.set(this.i18n.t('watch.shareReady'));
      },
      error: () => {}
    });
  }

  openPlaylistPicker() {
    if (!this.requireAuthentication('Vui lòng đăng nhập để thêm video vào danh sách phát.')) return;
    this.playlistPickerOpen.set(true);
    this.playlistLoading.set(true);
    this.playlists.mine().pipe(finalize(() => this.playlistLoading.set(false))).subscribe({
      next: lists => this.playlistOptions.set(lists),
      error: () => this.actionMessage.set('Không thể tải danh sách phát của bạn.')
    });
  }

  closePlaylistPicker() {
    if (!this.playlistAddingId()) this.playlistPickerOpen.set(false);
  }

  addToPlaylist(playlist: PlaylistSummary) {
    const item = this.video();
    if (!item || this.playlistAddingId() || this.addedPlaylistIds()[playlist.playlistId]) return;
    this.playlistAddingId.set(playlist.playlistId);
    this.playlists.addVideo(playlist.playlistId, item.videoId).pipe(finalize(() => this.playlistAddingId.set(null))).subscribe({
      next: () => {
        this.addedPlaylistIds.update(ids => ({ ...ids, [playlist.playlistId]: true }));
        this.playlistOptions.update(lists => lists.map(list => list.playlistId === playlist.playlistId
          ? { ...list, itemCount: list.itemCount + 1 }
          : list));
        this.actionMessage.set(`Đã thêm video vào “${playlist.name}”.`);
        this.playlistPickerOpen.set(false);
      },
      error: () => this.actionMessage.set(`Không thể thêm video vào “${playlist.name}”. Có thể video đã có trong danh sách.`)
    });
  }

  copyShareLink() {
    const url = this.shareUrl() || window.location.href;
    if (!navigator.clipboard) {
      this.actionMessage.set(this.i18n.t('watch.copyHint'));
      return;
    }
    navigator.clipboard.writeText(url).then(() => {
      this.actionMessage.set(this.i18n.t('watch.shareCopied'));
      this.shareOpen.set(false);
    }).catch(() => this.actionMessage.set(this.i18n.t('watch.copyError')));
  }

  closeShare() {
    this.shareOpen.set(false);
  }

  private absoluteUrl(value: string) {
    try { return new URL(value, window.location.origin).toString(); }
    catch { return value; }
  }

  comment() {
    if (!this.requireAuthentication(this.i18n.t('watch.loginCommentAction'))) return;
    const item = this.video();
    const text = this.commentText.trim();
    if (!item || !text) return;
    this.content.createComment(item.videoId, text).subscribe({
      next: comment => {
        this.comments.update(items => [comment, ...items]);
        this.commentText = '';
        this.video.update(video => video ? { ...video, stats: { ...video.stats, comments: video.stats.comments + 1 } } : video);
      },
      error: error => this.actionMessage.set(this.readError(error) || this.i18n.t('watch.commentError'))
    });
  }

  repliesFor(commentId: string): CommentItem[] {
    return this.repliesByComment()[commentId] ?? [];
  }

  isRepliesOpen(commentId: string): boolean {
    return this.expandedReplies()[commentId] === true;
  }

  isRepliesLoading(commentId: string): boolean {
    return this.repliesLoading()[commentId] === true;
  }

  toggleReplies(comment: CommentItem) {
    if (this.isRepliesOpen(comment.commentId)) {
      this.expandedReplies.update(state => ({ ...state, [comment.commentId]: false }));
      return;
    }
    if (Object.prototype.hasOwnProperty.call(this.repliesByComment(), comment.commentId)) {
      this.expandedReplies.update(state => ({ ...state, [comment.commentId]: true }));
      return;
    }
    this.loadReplies(comment, true);
  }

  loadReplies(comment: CommentItem, expand = true) {
    if (this.isRepliesLoading(comment.commentId)) return;
    this.repliesLoading.update(state => ({ ...state, [comment.commentId]: true }));
    if (expand) this.expandedReplies.update(state => ({ ...state, [comment.commentId]: true }));
    this.content.replies(comment.commentId).subscribe({
      next: value => {
        this.repliesByComment.update(groups => ({ ...groups, [comment.commentId]: value.items ?? [] }));
        this.repliesLoading.update(state => ({ ...state, [comment.commentId]: false }));
      },
      error: error => {
        this.repliesLoading.update(state => ({ ...state, [comment.commentId]: false }));
        this.actionMessage.set(this.readError(error) || this.i18n.t('watch.noReplies'));
      }
    });
  }

  reply(comment: CommentItem) {
    if (!this.requireAuthentication(this.i18n.t('watch.loginReply'))) return;
    const text = this.replyText.trim();
    if (!text) return;
    this.content.createComment(comment.videoId, text, comment.commentId).subscribe({
      next: reply => {
        this.repliesByComment.update(groups => ({
          ...groups,
          [comment.commentId]: [...(groups[comment.commentId] ?? []), reply]
        }));
        this.expandedReplies.update(state => ({ ...state, [comment.commentId]: true }));
        this.comments.update(items => items.map(item => item.commentId === comment.commentId
          ? { ...item, replyCount: item.replyCount + 1 }
          : item));
        this.video.update(video => video ? { ...video, stats: { ...video.stats, comments: video.stats.comments + 1 } } : video);
        this.replyText = '';
        this.replyTo.set(null);
        this.actionMessage.set(this.i18n.t('watch.replySaved'));
      },
      error: error => this.actionMessage.set(this.readError(error) || this.i18n.t('watch.replyError'))
    });
  }

  reactComment(comment: CommentItem, type: 'like' | 'dislike') {
    if (!this.requireAuthentication(this.i18n.t('watch.loginCommentInteraction'))) return;
    const next = comment.myReaction === type ? null : type;
    this.content.reactComment(comment.commentId, next).subscribe({
      next: result => {
        const updated = {
          ...comment,
          myReaction: result.myReaction as 'like' | 'dislike' | null,
          likes: result.likes,
          dislikes: result.dislikes
        };
        this.replaceCommentInState(updated);
      },
      error: error => this.actionMessage.set(this.readError(error) || this.i18n.t('watch.loginCommentInteraction'))
    });
  }

  private replaceCommentInState(updated: CommentItem) {
    this.comments.update(items => items.map(item => item.commentId === updated.commentId ? updated : item));
    this.repliesByComment.update(groups => {
      const next: Record<string, CommentItem[]> = {};
      for (const [parentId, items] of Object.entries(groups)) {
        next[parentId] = items.map(item => item.commentId === updated.commentId ? updated : item);
      }
      return next;
    });
  }

  hide(comment: CommentItem) {
    if (!this.requireAuthentication(this.i18n.t('watch.loginCommentManage'))) return;
    this.content.hideComment(comment.commentId, comment.status !== 'hidden').subscribe({
      next: value => this.replaceCommentInState(value),
      error: error => this.actionMessage.set(this.readError(error) || this.i18n.t('watch.commentUpdateError'))
    });
  }

  remove(comment: CommentItem) {
    if (!this.requireAuthentication(this.i18n.t('watch.loginCommentDelete'))) return;
    if (!confirm(this.i18n.t('watch.deleteCommentConfirm'))) return;
    this.content.deleteComment(comment.commentId).subscribe({
      next: () => {
        const wasRoot = this.comments().some(item => item.commentId === comment.commentId);
        if (wasRoot) {
          this.comments.update(items => items.filter(item => item.commentId !== comment.commentId));
          this.repliesByComment.update(groups => {
            const next = { ...groups };
            delete next[comment.commentId];
            return next;
          });
        } else {
          this.repliesByComment.update(groups => Object.fromEntries(
            Object.entries(groups).map(([parentId, items]) => [parentId, items.filter(item => item.commentId !== comment.commentId)])
          ));
          this.comments.update(items => items.map(item => item.replyCount > 0 && this.repliesFor(item.commentId).some(reply => reply.commentId === comment.commentId)
            ? { ...item, replyCount: Math.max(0, item.replyCount - 1) }
            : item));
        }
        this.video.update(video => video ? { ...video, stats: { ...video.stats, comments: Math.max(0, video.stats.comments - 1) } } : video);
      },
      error: error => this.actionMessage.set(this.readError(error) || this.i18n.t('watch.commentUpdateError'))
    });
  }

  readonly reportModalOpen = signal(false);
  readonly reportTargetType = signal<'video' | 'channel' | 'comment'>('video');
  readonly reportTargetId = signal('');
  readonly reportTargetTitle = signal('');

  report(comment: CommentItem) {
    if (!this.auth.user()) {
      this.actionMessage.set(this.i18n.t('watch.loginReport'));
      return;
    }
    this.reportTargetType.set('comment');
    this.reportTargetId.set(comment.commentId);
    this.reportTargetTitle.set(`Bình luận của ${comment.displayName}`);
    this.reportModalOpen.set(true);
  }

  reportVideo() {
    if (!this.auth.user()) {
      this.actionMessage.set('Vui lòng đăng nhập để báo cáo video.');
      return;
    }
    const currentVideo = this.video();
    if (!currentVideo) return;
    this.reportTargetType.set('video');
    this.reportTargetId.set(currentVideo.videoId);
    this.reportTargetTitle.set(currentVideo.title);
    this.reportModalOpen.set(true);
  }

  onReportSubmitted() {
    this.actionMessage.set('Báo cáo vi phạm đã được gửi đến ban kiểm duyệt.');
    setTimeout(() => this.actionMessage.set(''), 4000);
  }

  openDownloads() {
    if (!this.requireAuthentication(this.i18n.t('watch.loginDownload'))) return;
    if (this.downloadOptions().length) {
      this.downloadOpen.update(value => !value);
      return;
    }
    if (this.downloadBusy()) return;
    this.downloadBusy.set(true);
    this.content.downloadOptions(this.videoId).pipe(finalize(() => this.downloadBusy.set(false))).subscribe({
      next: options => {
        this.downloadOptions.set(options ?? []);
        this.downloadOpen.set(true);
        if (!options?.length) this.actionMessage.set(this.i18n.t('watch.noDownloadQuality'));
      },
      error: error => this.actionMessage.set(this.readError(error) || this.i18n.t('watch.downloadUnsupported'))
    });
  }

  download(quality: string) {
    if (!this.requireAuthentication(this.i18n.t('watch.loginDownload'))) return;
    this.downloadBusy.set(true);
    this.content.createDownload(this.videoId, quality).pipe(finalize(() => this.downloadBusy.set(false))).subscribe({
      next: result => {
        this.downloadOpen.set(false);
        this.actionMessage.set(result.fileUrl ? this.i18n.t('watch.downloadCreatedWithLink') : this.i18n.t('watch.downloadCreated'));
        if (result.fileUrl) window.location.assign(result.fileUrl);
      },
      error: error => this.actionMessage.set(this.readError(error) || this.i18n.t('watch.downloadError'))
    });
  }

  setRecommendationFilter(filter: 'all' | 'related' | 'channel' | 'category') {
    this.recommendationFilter.set(filter);
    const current = this.video();
    if ((filter === 'channel' || filter === 'category') && current) {
      this.content.search({
        channelId: filter === 'channel' ? current.channelId : undefined,
        categoryId: filter === 'category' ? current.categoryId ?? undefined : undefined,
        sort: 'newest', page: 1, pageSize: 12
      }).subscribe({
        next: value => this.relatedVideos.set((value.items ?? []).filter(item => item.videoId !== current.videoId).slice(0, 8)),
        error: () => this.relatedVideos.set([])
      });
      return;
    }
    this.content.feed('home', 1, 12).subscribe({
      next: value => this.relatedVideos.set((value.items ?? []).filter(item => item.videoId !== this.videoId).slice(0, 8)),
      error: () => this.relatedVideos.set([])
    });
  }

  toggleAutoplay() {
    this.autoplay.update(value => !value);
  }

  isOwnComment(comment: CommentItem) { return comment.userId === this.auth.user()?.userId; }
  isOwner() { return this.video()?.channelId === this.myChannelId(); }

  initials(value: string | null | undefined) {
    const text = (value ?? '').trim();
    return text ? text.charAt(0).toUpperCase() : 'H';
  }

  visibilityLabel(value: string | null | undefined) {
    if (value === 'public') return this.i18n.t('ui.public');
    if (value === 'unlisted') return this.i18n.t('ui.unlisted');
    return this.i18n.t('ui.private');
  }

  languageLabel(value: string | null | undefined) {
    const code = (value ?? '').toLowerCase();
    if (code.startsWith('en')) return this.i18n.t('upload.languageEnglish');
    if (code.startsWith('ja')) return this.i18n.t('upload.languageJapanese');
    if (code.startsWith('vi')) return this.i18n.t('upload.languageVietnamese');
    return value || this.i18n.t('watch.defaultLanguage');
  }

  countLabel(key: 'watch.views' | 'watch.subscribers' | 'watch.chapterCountLabel' | 'watch.commentCount' | 'watch.recommendationViews' | 'watch.repliesCount', count: number) {
    return this.i18n.t(key, { count: this.i18n.formatNumber(count) });
  }

  ratingLabel(star: number) {
    return this.i18n.t('watch.ratingStar', { star: String(star) });
  }

  repliesLabel(count: number) {
    return this.countLabel('watch.repliesCount', count);
  }

  commentStatusLabel(hidden: boolean) {
    return this.i18n.t(hidden ? 'watch.show' : 'watch.hide');
  }

  duration(value: number) {
    const seconds = Math.max(0, Math.floor(value || 0));
    return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
  }

  formatBytes(bytes: number) {
    if (bytes >= 1024 ** 3) return `${this.i18n.formatNumber(bytes / 1024 ** 3, { maximumFractionDigits: 2 })} GB`;
    return `${this.i18n.formatNumber(bytes / 1024 ** 2, { maximumFractionDigits: 2 })} MB`;
  }

  private viewerState(item: VideoDetail) {
    return item.viewerState ?? { reaction: null, rating: null, resumeAtSeconds: 0, progress: 0 };
  }

  private readError(_error: any) {
    return '';
  }

  private requireAuthentication(message: string): boolean {
    if (this.auth.user()) return true;
    this.actionMessage.set(message);
    return false;
  }

  @HostListener('window:keydown', ['$event'])
  keys(event: KeyboardEvent) {
    if (event.key === 'Escape' && this.playlistPickerOpen()) {
      event.preventDefault();
      this.closePlaylistPicker();
      return;
    }
    if (event.key === 'Escape' && this.shareOpen()) {
      event.preventDefault();
      this.closeShare();
      return;
    }
    if (event.key === 'Escape' && this.downloadOpen()) {
      event.preventDefault();
      this.downloadOpen.set(false);
      return;
    }
    const target = event.target as HTMLElement | null;
    if (event.ctrlKey || event.metaKey || event.altKey || target?.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT', 'BUTTON'].includes(target?.tagName ?? '')) return;
    const player = this.playerRef?.nativeElement;
    if (!player) return;
    const key = event.key.toLowerCase();
    if (event.code === 'Space' || key === 'k') this.togglePlayback();
    else if (key === 'j' || event.key === 'ArrowLeft') this.seekBy(-10);
    else if (key === 'l' || event.key === 'ArrowRight') this.seekBy(10);
    else if (key === 'm') this.toggleMute();
    else if (key === 'f') this.toggleFullscreen();
    else if (key === 'i') this.toggleMiniPlayer();
    else return;
    event.preventDefault();
    event.stopPropagation();
  }

  toggleSubscribe() {
    const channel = this.channel();
    if (!channel) return;

    if (!this.auth.user()) {
      void this.router.navigate(['/login']);
      return;
    }

    if (this.myChannelId() === channel.channelId) {
      this.actionMessage.set(this.i18n.t('watch.cannotSubscribeSelf'));
      return;
    }

    if (this.subscribed()) {
      this.channels.unsubscribe(channel.channelId).subscribe({
        next: () => {
          this.subscribed.set(false);
          this.subscriptionNotificationsEnabled.set(false);
          this.subscriberCount.update(c => Math.max(0, c - 1));
        },
        error: () => this.actionMessage.set(this.i18n.t('watch.unsubscribeError'))
      });
    } else {
      this.channels.subscribe(channel.channelId).subscribe({
        next: sub => {
          this.subscribed.set(true);
          this.subscriptionNotificationsEnabled.set(sub.notificationsEnabled);
          this.subscriberCount.update(c => c + 1);
        },
        error: () => this.actionMessage.set(this.i18n.t('watch.subscribeError'))
      });
    }
  }

  toggleSubscriptionNotifications() {
    const channel = this.channel();
    if (!channel || !this.subscribed()) {
      this.actionMessage.set('Hãy đăng ký kênh trước khi bật thông báo.');
      return;
    }
    const enabled = !this.subscriptionNotificationsEnabled();
    this.channels.updateSubscriptionNotifications(channel.channelId, enabled).subscribe({
      next: response => this.subscriptionNotificationsEnabled.set(response.notificationsEnabled),
      error: () => this.actionMessage.set('Không thể cập nhật thông báo cho kênh này.')
    });
  }
}
