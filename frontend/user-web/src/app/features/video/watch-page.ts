import { DatePipe, DecimalPipe } from '@angular/common';
import { Component, ElementRef, HostListener, ViewChild, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { ChannelDetail, ChannelService } from '../../core/channel.service';
import { CommentItem, ContentService, Playback, Rendition, VideoCard, VideoDetail, ViolationType } from '../../core/content.service';

@Component({
  selector: 'app-watch-page',
  imports: [DatePipe, DecimalPipe, FormsModule, RouterLink],
  templateUrl: './watch-page.html',
  styleUrl: './watch-page.scss'
})
export class WatchPage {
  private readonly route = inject(ActivatedRoute);
  private readonly content = inject(ContentService);
  private readonly channels = inject(ChannelService);
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
  readonly shareOpen = signal(false);
  readonly shareUrl = signal('');
  readonly visibleRelatedVideos = computed(() => {
    const items = this.relatedVideos();
    const current = this.video();
    if (this.recommendationFilter() === 'channel' && current) {
      const sameChannel = items.filter(item => item.channelId === current.channelId);
      return sameChannel.length ? sameChannel : items;
    }
    return items;
  });
  readonly speeds = [.25, .5, .75, 1, 1.25, 1.5, 1.75, 2];

  commentText = '';
  replyText = '';
  private readonly videoId: string;
  private lastSaved = 0;
  private pendingSeek: number | null = null;
  private resumeApplied = false;
  private continuePlaying = false;

  @ViewChild('player') playerRef?: ElementRef<HTMLVideoElement>;
  @ViewChild('playerStage') playerStageRef?: ElementRef<HTMLElement>;

  constructor() {
    this.videoId = this.route.snapshot.paramMap.get('id') ?? '';
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
          this.activeRendition.set({ quality: 'Nguồn', width: 0, height: 0, fileSize: video.fileSize, url: video.videoUrl });
        }
        this.channels.getChannel(video.channelHandle).subscribe({ next: channel => this.channel.set(channel), error: () => {} });
        this.loading.set(false);
      },
      error: () => {
        this.error.set('Video không khả dụng hoặc bạn không có quyền xem video này.');
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
          this.activeRendition.set(best);
        }
      },
      error: () => this.actionMessage.set('Không tải được các bản chất lượng cao hơn. Video nguồn vẫn có thể phát.')
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
    this.currentTime.set(player.currentTime);
  }

  onPlayerError() {
    this.actionMessage.set('Không thể phát bản chất lượng này. Hãy thử chọn chất lượng khác.');
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
      void player.play().catch(() => this.actionMessage.set('Không thể phát video ở thời điểm này.'));
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
    const item = this.video();
    if (!item) return;
    const next = item.viewerState?.reaction === type ? null : type;
    this.content.reactVideo(item.videoId, next).subscribe({
      next: result => this.video.set({
        ...item,
        stats: { ...item.stats, likes: result.likes, dislikes: result.dislikes },
        viewerState: { ...this.viewerState(item), reaction: result.myReaction as 'like' | 'dislike' | null }
      }),
      error: error => this.actionMessage.set(this.readError(error) || 'Vui lòng đăng nhập để tương tác với video.')
    });
  }

  rate(score: number | null) {
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
        this.actionMessage.set('Đã cập nhật đánh giá của bạn.');
      },
      error: error => this.actionMessage.set(this.readError(error) || 'Vui lòng đăng nhập để đánh giá video.')
    });
  }

  share() {
    const item = this.video();
    if (!item) return;
    this.shareUrl.set(window.location.href);
    this.shareOpen.set(true);
    this.content.share(item.videoId).subscribe({
      next: result => {
        if (result?.url) this.shareUrl.set(this.absoluteUrl(result.url));
        this.actionMessage.set('Liên kết video đã sẵn sàng để chia sẻ.');
      },
      error: () => {}
    });
  }

  copyShareLink() {
    const url = this.shareUrl() || window.location.href;
    if (!navigator.clipboard) {
      this.actionMessage.set('Hãy sao chép liên kết trong ô bên trên.');
      return;
    }
    navigator.clipboard.writeText(url).then(() => {
      this.actionMessage.set('Đã sao chép liên kết video.');
      this.shareOpen.set(false);
    }).catch(() => this.actionMessage.set('Không thể sao chép tự động. Hãy sao chép liên kết thủ công.'));
  }

  closeShare() {
    this.shareOpen.set(false);
  }

  private absoluteUrl(value: string) {
    try { return new URL(value, window.location.origin).toString(); }
    catch { return value; }
  }

  comment() {
    const item = this.video();
    const text = this.commentText.trim();
    if (!item || !text) return;
    this.content.createComment(item.videoId, text).subscribe({
      next: comment => {
        this.comments.update(items => [comment, ...items]);
        this.commentText = '';
        this.video.update(video => video ? { ...video, stats: { ...video.stats, comments: video.stats.comments + 1 } } : video);
      },
      error: error => this.actionMessage.set(this.readError(error) || 'Không thể gửi bình luận.')
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
        this.actionMessage.set(this.readError(error) || 'Không thể tải câu trả lời.');
      }
    });
  }

  reply(comment: CommentItem) {
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
        this.actionMessage.set('Đã gửi câu trả lời.');
      },
      error: error => this.actionMessage.set(this.readError(error) || 'Không thể gửi câu trả lời.')
    });
  }

  reactComment(comment: CommentItem, type: 'like' | 'dislike') {
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
      error: error => this.actionMessage.set(this.readError(error) || 'Vui lòng đăng nhập để tương tác.')
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
    this.content.hideComment(comment.commentId, comment.status !== 'hidden').subscribe({
      next: value => this.replaceCommentInState(value),
      error: error => this.actionMessage.set(this.readError(error) || 'Không thể cập nhật bình luận.')
    });
  }

  remove(comment: CommentItem) {
    if (!confirm('Xóa bình luận này?')) return;
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
      error: error => this.actionMessage.set(this.readError(error) || 'Không thể xóa bình luận.')
    });
  }

  report(comment: CommentItem) {
    const types = this.violationTypes();
    if (!this.auth.user()) {
      this.actionMessage.set('Vui lòng đăng nhập để báo cáo bình luận.');
      return;
    }
    if (!types.length) {
      this.actionMessage.set('Hiện chưa có loại vi phạm để gửi báo cáo.');
      return;
    }
    const choices = types.map(type => `${type.code}: ${type.name}`).join('\n');
    const code = prompt(`Chọn mã vi phạm:\n${choices}`, types[0].code)?.trim().toLowerCase();
    if (!code) return;
    const type = types.find(item => item.code.toLowerCase() === code);
    if (!type) {
      this.actionMessage.set('Mã vi phạm không hợp lệ.');
      return;
    }
    const description = prompt('Mô tả thêm (không bắt buộc):', '') ?? '';
    this.content.reportComment(comment.commentId, type.violationTypeId, description).subscribe({
      next: () => this.actionMessage.set('Đã gửi báo cáo bình luận.'),
      error: () => this.actionMessage.set('Không thể gửi báo cáo. Vui lòng thử lại.')
    });
  }

  setRecommendationFilter(filter: 'all' | 'related' | 'channel' | 'category') {
    this.recommendationFilter.set(filter);
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

  duration(value: number) {
    const seconds = Math.max(0, Math.floor(value || 0));
    return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
  }

  private viewerState(item: VideoDetail) {
    return item.viewerState ?? { reaction: null, rating: null, resumeAtSeconds: 0, progress: 0 };
  }

  private readError(error: any) {
    return error?.error?.detail || error?.error?.title || error?.message || '';
  }

  @HostListener('window:keydown', ['$event'])
  keys(event: KeyboardEvent) {
    if (event.key === 'Escape' && this.shareOpen()) {
      event.preventDefault();
      this.closeShare();
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
}
