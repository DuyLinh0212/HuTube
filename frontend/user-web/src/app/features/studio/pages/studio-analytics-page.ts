import { Component, OnInit, OnDestroy, computed, inject, signal, effect } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Subscription } from 'rxjs';
import { ContentService, CommentSentimentStats, VideoDetail } from '../../../core/content.service';
import { StudioDataService } from '../../../core/studio-data.service';
import { I18nService } from '../../../core/i18n.service';
import { LocaleNumberPipe } from '../../../core/locale-number.pipe';
import { TranslatePipe } from '../../../core/translate.pipe';

type MetricKey = 'views' | 'likes' | 'comments' | 'watchDuration' | 'rating';

interface AnalyticsMetric {
  key: MetricKey;
  labelKey: string;
  radarLabelKey: string;
  value: number;
  display: string;
  ratio: number;
}

@Component({
  selector: 'app-studio-analytics-page',
  imports: [LocaleNumberPipe, TranslatePipe, RouterLink],
  templateUrl: './studio-analytics-page.html',
  styleUrl: './studio-analytics-page.scss',
})
export class StudioAnalyticsPage implements OnInit, OnDestroy {
  readonly data = inject(StudioDataService);
  private readonly content = inject(ContentService);
  private readonly i18n = inject(I18nService);
  private sentimentSub?: Subscription;
  private lastChannelId: string | null = null;
  private readonly sentimentCache = new Map<string, { timestamp: number; stats: CommentSentimentStats }>();
  readonly selectedVideoId = signal('all');
  readonly selectedVideo = computed(() => {
    const id = this.selectedVideoId();
    if (id === 'all') return null;
    return this.data.videos().find(video => video.videoId === id) ?? null;
  });
  readonly isAllVideos = computed(() => this.selectedVideoId() === 'all');
  readonly videoCount = computed(() => this.data.videos().length);
  readonly sentimentStats = signal<CommentSentimentStats | null>(null);
  readonly loadingSentiment = signal(false);

  readonly emotionLabels: Record<string, { label: string; icon: string; color: string }> = {
    Enjoyment: { label: 'Thích thú', icon: '😊', color: '#10b981' },
    Sadness: { label: 'Buồn bã', icon: '😢', color: '#6366f1' },
    Surprise: { label: 'Ngạc nhiên', icon: '😲', color: '#f59e0b' },
    Other: { label: 'Khác', icon: '💬', color: '#94a3b8' },
    Fear: { label: 'Sợ hãi', icon: '😨', color: '#8b5cf6' },
    Anger: { label: 'Giận dữ', icon: '😡', color: '#ef4444' },
    Disgust: { label: 'Ghê tởm', icon: '🤢', color: '#ec4899' },
  };

  constructor() {
    effect(() => {
      const channel = this.data.channel();
      const currentChannelId = channel?.channelId ?? null;
      if (this.lastChannelId !== null && this.lastChannelId !== currentChannelId) {
        this.selectedVideoId.set('all');
      }
      this.lastChannelId = currentChannelId;

      const videoId = this.selectedVideoId();
      if (!channel?.channelId) {
        this.sentimentStats.set(null);
        return;
      }
      this.loadSentiment(channel.channelId, videoId);
    }, { allowSignalWrites: true });
  }

  loadSentiment(channelId: string, videoId: string) {
    const cacheKey = `${channelId}:${videoId}`;
    const cached = this.sentimentCache.get(cacheKey);
    const now = Date.now();
    if (cached && now - cached.timestamp < 60_000) {
      this.sentimentStats.set(cached.stats);
      this.loadingSentiment.set(false);
      return;
    }

    this.sentimentSub?.unsubscribe();
    this.loadingSentiment.set(true);
    this.sentimentSub = this.content.getCommentSentimentStats(channelId, videoId).subscribe({
      next: stats => {
        this.sentimentCache.set(cacheKey, { timestamp: Date.now(), stats });
        this.sentimentStats.set(stats);
        this.loadingSentiment.set(false);
      },
      error: () => {
        this.loadingSentiment.set(false);
      }
    });
  }

  getEmotionList(counts: Record<string, number> | undefined) {
    return Object.keys(this.emotionLabels).map(emotion => ({
      key: emotion,
      count: counts?.[emotion] ?? 0,
      label: this.emotionLabels[emotion].label,
      icon: this.emotionLabels[emotion].icon,
      color: this.emotionLabels[emotion].color
    })).sort((a, b) => b.count - a.count);
  }

  readonly topVideos = computed(() => [...this.data.videos()]
    .sort((left, right) => right.stats.views - left.stats.views || right.stats.likes - left.stats.likes || left.title.localeCompare(right.title))
    .slice(0, 5));

  readonly metrics = computed<AnalyticsMetric[]>(() => {
    const videos = this.data.videos();
    const selected = this.selectedVideo();
    const totalViews = videos.reduce((sum, video) => sum + video.stats.views, 0);
    const totalLikes = videos.reduce((sum, video) => sum + video.stats.likes, 0);
    const totalComments = videos.reduce((sum, video) => sum + video.stats.comments, 0);
    const totalWatchSeconds = videos.reduce((sum, video) => sum + (video.stats.watchSeconds ?? 0), 0);
    const ratedVideos = videos.filter(video => video.stats.averageRating !== null && video.stats.ratingCount > 0);
    const totalRatings = ratedVideos.reduce((sum, video) => sum + video.stats.averageRating! * video.stats.ratingCount, 0);
    const ratingCount = ratedVideos.reduce((sum, video) => sum + video.stats.ratingCount, 0);
    const values: Record<MetricKey, number> = {
      views: selected ? selected.stats.views : videos.length ? totalViews / videos.length : 0,
      likes: selected ? selected.stats.likes : videos.length ? totalLikes / videos.length : 0,
      comments: selected ? selected.stats.comments : videos.length ? totalComments / videos.length : 0,
      watchDuration: selected
        ? selected.stats.views ? (selected.stats.watchSeconds ?? 0) / selected.stats.views : 0
        : totalViews ? totalWatchSeconds / totalViews : 0,
      rating: selected
        ? selected.stats.averageRating ?? 0
        : ratingCount ? totalRatings / ratingCount : 0,
    };
    const maxima: Record<MetricKey, number> = {
      views: Math.max(0, ...videos.map(video => video.stats.views)),
      likes: Math.max(0, ...videos.map(video => video.stats.likes)),
      comments: Math.max(0, ...videos.map(video => video.stats.comments)),
      watchDuration: Math.max(0, ...videos.map(video => video.stats.views
        ? (video.stats.watchSeconds ?? 0) / video.stats.views : 0)),
      rating: 5,
    };
    const labels: Record<MetricKey, string> = {
      views: selected ? 'studio.viewsCount' : 'studio.averageViews',
      likes: selected ? 'studio.likes' : 'studio.averageLikes',
      comments: selected ? 'studio.commentsCount' : 'studio.averageComments',
      watchDuration: 'studio.averageViewDuration',
      rating: 'studio.averageRating',
    };
    const radarLabels: Record<MetricKey, string> = {
      views: 'studio.analyticsAxisViews',
      likes: 'studio.analyticsAxisLikes',
      comments: 'studio.analyticsAxisComments',
      watchDuration: 'studio.analyticsAxisDuration',
      rating: 'studio.analyticsAxisRating',
    };
    return (Object.keys(values) as MetricKey[]).map(key => {
      const hasRating = selected
        ? selected.stats.ratingCount > 0 && selected.stats.averageRating !== null
        : ratingCount > 0;
      return {
        key,
        labelKey: labels[key],
        radarLabelKey: radarLabels[key],
        value: values[key],
        display: key === 'watchDuration' ? this.formatDuration(values[key])
          : key === 'rating' ? hasRating ? `${values[key].toFixed(2)} / 5` : '—'
          : this.formatNumber(values[key]),
        ratio: maxima[key] ? Math.min(1, values[key] / maxima[key]) : 0,
      };
    });
  });

  readonly radarAxes = computed(() => this.metrics().map((metric, index) => {
    const angle = -Math.PI / 2 + index * (Math.PI * 2 / 5);
    const labelRadius = 153;
    const labelX = 220 + Math.cos(angle) * labelRadius;
    return {
      ...metric,
      x: 220 + Math.cos(angle) * 108,
      y: 158 + Math.sin(angle) * 108,
      labelX,
      labelY: 158 + Math.sin(angle) * labelRadius,
      anchor: Math.abs(labelX - 220) < 12 ? 'middle' : labelX < 220 ? 'end' : 'start',
    };
  }));
  readonly radarValuePoints = computed(() => this.metrics().map((metric, index) => {
    const angle = -Math.PI / 2 + index * (Math.PI * 2 / 5);
    const radius = Math.max(metric.ratio > 0 ? 4 : 0, metric.ratio * 108);
    return `${(220 + Math.cos(angle) * radius).toFixed(1)},${(158 + Math.sin(angle) * radius).toFixed(1)}`;
  }).join(' '));
  readonly radarGrid = [0.25, 0.5, 0.75, 1].map(scale => Array.from({ length: 5 }, (_, index) => {
    const angle = -Math.PI / 2 + index * (Math.PI * 2 / 5);
    return `${(220 + Math.cos(angle) * 108 * scale).toFixed(1)},${(158 + Math.sin(angle) * 108 * scale).toFixed(1)}`;
  }).join(' '));

  ngOnInit() {
    if (!this.data.videos().length || !this.data.channel()) {
      this.data.load();
    }
  }

  ngOnDestroy() {
    this.sentimentSub?.unsubscribe();
  }

  selectVideo(videoId: string) {
    this.selectedVideoId.set(videoId);
  }

  topVideoWidth(video: VideoDetail): number {
    const highestViews = this.topVideos()[0]?.stats.views ?? 0;
    return highestViews ? Math.max(3, video.stats.views / highestViews * 100) : 0;
  }

  formatDuration(seconds: number): string {
    if (!Number.isFinite(seconds) || seconds <= 0) return '0:00';
    const total = Math.round(seconds);
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const remainder = total % 60;
    return hours
      ? `${hours}:${String(minutes).padStart(2, '0')}:${String(remainder).padStart(2, '0')}`
      : `${minutes}:${String(remainder).padStart(2, '0')}`;
  }

  private formatNumber(value: number): string {
    return new Intl.NumberFormat(this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US', { maximumFractionDigits: 1 }).format(value);
  }
}
