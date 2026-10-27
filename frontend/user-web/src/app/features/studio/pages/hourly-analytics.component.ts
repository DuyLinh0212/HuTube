import { HttpClient } from '@angular/common/http';
import { Component, Input, effect, inject, signal } from '@angular/core';
import { I18nService } from '../../../core/i18n.service';
import { RuntimeConfig } from '../../../core/runtime-config';
import { StudioDataService } from '../../../core/studio-data.service';
import { TranslatePipe } from '../../../core/translate.pipe';

type HourlyMetric = 'views' | 'likes' | 'watchSeconds' | 'subscribers';
interface HourlyBucket { hour: number; views: number; likes: number; watchSeconds: number; subscribers: number; }
interface HourlyResponse { from: string; to: string; utcOffsetMinutes: number; hours: HourlyBucket[]; }

@Component({
  selector: 'app-hourly-analytics',
  imports: [TranslatePipe],
  templateUrl: './hourly-analytics.component.html',
  styleUrl: './hourly-analytics.component.scss',
})
export class HourlyAnalyticsComponent {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);
  private readonly data = inject(StudioDataService);
  private readonly i18n = inject(I18nService);
  private readonly video = signal('all');
  @Input() set videoId(value: string) { this.video.set(value || 'all'); }
  readonly days = signal(7);
  readonly loading = signal(false);
  readonly error = signal(false);
  readonly hours = signal<HourlyBucket[]>([]);
  readonly metrics: { key: HourlyMetric; label: string }[] = [
    { key: 'subscribers', label: 'hourly.subscribers' },
    { key: 'views', label: 'hourly.views' },
    { key: 'likes', label: 'hourly.likes' },
    { key: 'watchSeconds', label: 'hourly.watch' },
  ];
  readonly offset = -new Date().getTimezoneOffset();
  readonly timezone = `UTC${this.offset >= 0 ? '+' : '-'}${String(Math.floor(Math.abs(this.offset) / 60)).padStart(2, '0')}:${String(Math.abs(this.offset) % 60).padStart(2, '0')}`;
  private readonly retryVersion = signal(0);

  constructor() {
    this.i18n.registerTranslations({
      vi: {
        'hourly.title': 'Hoạt động theo khung giờ', 'hourly.desc': 'Tổng theo giờ trong ngày, tính theo múi giờ của thiết bị',
        'hourly.subscribers': 'Lượt đăng ký mới của kênh', 'hourly.views': 'Lượt xem được ghi nhận',
        'hourly.likes': 'Lượt thích mới', 'hourly.watch': 'Thời gian xem ước tính',
        'hourly.days': 'Khoảng thời gian', 'hourly.day1': '24 giờ qua', 'hourly.day7': '7 ngày qua', 'hourly.day30': '30 ngày qua',
        'hourly.note': 'Số liệu được ghi từ khi tính năng này hoạt động, không khôi phục được lịch sử trước đó. Lượt xem và thời gian xem dựa trên tiến trình của người dùng đã đăng nhập; thời gian xem là ước tính và có thể sai lệch khi tua, tạm dừng hoặc gián đoạn.',
        'hourly.channelNote': 'Lượt đăng ký tính cho cả kênh, kể cả khi chọn một video.',
        'hourly.loading': 'Đang tải dữ liệu theo giờ…', 'hourly.error': 'Không tải được dữ liệu theo giờ.', 'hourly.retry': 'Thử lại',
      },
      en: {
        'hourly.title': 'Activity by hour', 'hourly.desc': 'Totals by hour of day in your device time zone',
        'hourly.subscribers': 'New channel subscriptions', 'hourly.views': 'Recorded views',
        'hourly.likes': 'New likes', 'hourly.watch': 'Estimated watch time',
        'hourly.days': 'Time range', 'hourly.day1': 'Last 24 hours', 'hourly.day7': 'Last 7 days', 'hourly.day30': 'Last 30 days',
        'hourly.note': 'Data is recorded from the launch of this feature; earlier history cannot be recovered. Views and watch time use signed-in viewers’ saved progress. Watch time is estimated and may be inaccurate after seeking, pauses or interruptions.',
        'hourly.channelNote': 'Subscriptions apply to the entire channel even when a video is selected.',
        'hourly.loading': 'Loading hourly data…', 'hourly.error': 'Could not load hourly data.', 'hourly.retry': 'Retry',
      },
    });
    effect(onCleanup => {
      const channelId = this.data.selectedChannelId();
      const videoId = this.video();
      const days = this.days();
      this.retryVersion();
      if (!channelId) { this.hours.set([]); return; }
      this.loading.set(true);
      this.error.set(false);
      this.hours.set([]);
      const params: Record<string, string> = { days: String(days), utcOffsetMinutes: String(this.offset) };
      if (videoId !== 'all') params['videoId'] = videoId;
      const request = this.http.get<HourlyResponse>(`${this.config.apiBaseUrl}/studio/channels/${encodeURIComponent(channelId)}/hourly-analytics`, { params })
        .subscribe({
          next: result => { this.hours.set(result.hours); this.loading.set(false); },
          error: () => { this.error.set(true); this.loading.set(false); },
        });
      onCleanup(() => request.unsubscribe());
    });
  }

  retry() { this.retryVersion.update(value => value + 1); }
  total(key: HourlyMetric) { return this.hours().reduce((sum, hour) => sum + hour[key], 0); }
  height(key: HourlyMetric, value: number) {
    const max = Math.max(0, ...this.hours().map(hour => hour[key]));
    return value && max ? Math.max(4, value / max * 100) : 0;
  }
  format(key: HourlyMetric, value: number) {
    if (key === 'watchSeconds') {
      const minutes = value / 60;
      return `${this.i18n.formatNumber(minutes, { maximumFractionDigits: 1 })} ${this.i18n.currentLang() === 'vi' ? 'phút' : 'min'}`;
    }
    return this.i18n.formatNumber(value);
  }
  label(key: HourlyMetric, hour: HourlyBucket) {
    return `${String(hour.hour).padStart(2, '0')}:00–${String((hour.hour + 1) % 24).padStart(2, '0')}:00 · ${this.format(key, hour[key])}`;
  }
}
