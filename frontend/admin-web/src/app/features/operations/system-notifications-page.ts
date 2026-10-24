import { Component, OnDestroy, OnInit, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Subscription, interval } from 'rxjs';
import { TranslatePipe } from '../../core/translate.pipe';
import { I18nService } from '../../core/i18n.service';
import { AuthService } from '../../core/auth.service';
import { AdminOperationsService, ApiTrafficBucket, SystemActivity, SystemOverview, SystemServiceStatus, SystemSignal } from './operations.service';

type MonitorTab = 'live' | 'alerts';
type MetricFormat = 'integer' | 'percent';

interface MetricCard {
  key: string;
  label: [string, string];
  value: number | null;
  format: MetricFormat;
  unit: [string, string];
  tone: 'blue' | 'green' | 'red' | 'purple' | 'orange';
}

interface UnintegratedSource {
  vi: string;
  en: string;
}

const SERVICE_CATALOG: SystemServiceStatus[] = [
  { key: 'api', status: 'unmonitored', detail: 'Chưa nhận dữ liệu kiểm tra từ API.', responseTimeMs: null },
  { key: 'database', status: 'unmonitored', detail: 'Chưa nhận dữ liệu kiểm tra từ API.', responseTimeMs: null },
  { key: 'redis', status: 'unmonitored', detail: 'Backend chưa kết nối Redis hoặc chưa cấu hình health check.', responseTimeMs: null },
  { key: 'vercel', status: 'unmonitored', detail: 'Chưa nhận dữ liệu kiểm tra frontend trên Vercel.', responseTimeMs: null },
  { key: 'ec2', status: 'unmonitored', detail: 'Chưa nhận được số đo RAM host từ EC2.', responseTimeMs: null },
  { key: 'storage', status: 'unmonitored', detail: 'Chưa nhận dữ liệu kiểm tra Cloudflare R2.', responseTimeMs: null },
  { key: 'signalr', status: 'unmonitored', detail: 'Chưa nhận dữ liệu kiểm tra SignalR.', responseTimeMs: null },
];

@Component({
  selector: 'app-system-notifications-page',
  imports: [RouterLink, TranslatePipe],
  templateUrl: './system-notifications-page.html',
  styleUrl: './system-notifications-page.scss',
})
export class SystemNotificationsPage implements OnInit, OnDestroy {
  private readonly operations = inject(AdminOperationsService);
  private readonly auth = inject(AuthService);
  private refreshTimer?: Subscription;

  readonly i18n = inject(I18nService);
  readonly overview = signal<SystemOverview | null>(null);
  readonly loading = signal(true);
  readonly error = signal(false);
  readonly activeTab = signal<MonitorTab>('live');
  readonly activeFilter = signal('all');
  readonly visibleServices = computed<SystemServiceStatus[]>(() => {
    const reported = this.overview()?.services ?? [];
    const knownKeys = new Set(SERVICE_CATALOG.map(service => service.key));
    const known = SERVICE_CATALOG.map(fallback => reported.find(item => item.key.toLowerCase() === fallback.key) ?? fallback);
    return [...known, ...reported.filter(item => !knownKeys.has(item.key.toLowerCase()))];
  });
  readonly unintegratedSources = computed<UnintegratedSource[]>(() => {
    const data = this.overview();
    if (!data) return [];
    const sources: UnintegratedSource[] = [];
    const redis = this.visibleServices().find(service => service.key === 'redis');
    if (!redis || redis.status === 'unmonitored') {
      sources.unshift({
        vi: 'Health check Redis cần cấu hình UPSTASH_REDIS_REST_URL và UPSTASH_REDIS_REST_TOKEN.',
        en: 'Redis health checks require UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN.',
      });
    }
    if (!data.r2StorageUsage || data.r2StorageUsage.status !== 'available') {
      sources.push({
        vi: data.r2StorageUsage?.detail ?? 'Chưa đọc được dung lượng Cloudflare R2; kiểm tra quyền Cloudflare Analytics và cấu hình bucket.',
        en: 'Cloudflare R2 storage is unavailable. Check Cloudflare Analytics permissions and bucket configuration.',
      });
    }
    if (!data.neonUsage || data.neonUsage.status !== 'available') {
      const detail = data.neonUsage?.detail;
      const needsApiKey = detail?.includes('NEON_API_KEY') ?? true;
      const isProviderError = data.neonUsage?.status === 'error';
      sources.push({
        vi: detail ?? 'Usage Neon cần NEON_API_KEY, NEON_ORG_ID và NEON_PROJECT_ID.',
        en: isProviderError
          ? 'Neon metrics could not be read. Check database connectivity, API key permissions, and the organization/project IDs.'
          : needsApiKey
          ? 'Neon usage requires NEON_API_KEY, NEON_ORG_ID, and NEON_PROJECT_ID.'
          : 'This Neon plan does not provide consumption history through the API; database size and connections remain measured.',
      });
    }
    if (!data?.redisUsage || data.redisUsage.status !== 'available') {
      sources.push({
        vi: data?.redisUsage?.detail ?? 'Quota Upstash cần UPSTASH_EMAIL, UPSTASH_API_KEY và UPSTASH_REDIS_DATABASE_ID.',
        en: 'Upstash usage is unavailable. Check UPSTASH_EMAIL, UPSTASH_API_KEY, UPSTASH_REDIS_DATABASE_ID, and the Developer API key permissions.',
      });
    }
    if (!data?.ec2Memory || data.ec2Memory.status !== 'available') {
      sources.push({
        vi: data?.ec2Memory?.detail ?? 'RAM máy EC2 cần API chạy trên Linux và đọc được /proc/meminfo.',
        en: 'EC2 host memory requires the API to run on Linux with access to /proc/meminfo.',
      });
    }
    return sources;
  });
  readonly visibleSignals = computed(() => {
    const filter = this.activeFilter();
    const signals = this.overview()?.signals ?? [];
    return filter === 'all' ? signals : signals.filter(item => item.category === filter);
  });
  readonly triggeredSignals = computed(() => (this.overview()?.signals ?? []).filter(item => item.isTriggered));
  readonly metrics = computed<MetricCard[]>(() => {
    const data = this.overview();
    if (!data) return [];
    const traffic = data.apiTraffic;
    const live = data.liveMetrics;
    return [
      { key: 'requests', label: ['Request trong phút này', 'Requests this minute'], value: traffic.requestsThisMinute, format: 'integer', unit: ['request', 'requests'], tone: 'blue' },
      { key: 'sessions', label: ['Phiên còn hiệu lực', 'Valid sessions'], value: live.activeSessions, format: 'integer', unit: ['phiên', 'sessions'], tone: 'green' },
      { key: 'server-errors', label: ['Tỷ lệ lỗi 5xx · 15 phút', '5xx error rate · 15 min'], value: traffic.requestsLast15Minutes ? traffic.serverErrorRateLast15Minutes : null, format: 'percent', unit: ['', ''], tone: 'red' },
      { key: 'failed-payments', label: ['Thanh toán lỗi · 24 giờ', 'Failed payments · 24 h'], value: live.failedPaymentsLast24Hours, format: 'integer', unit: ['giao dịch', 'transactions'], tone: 'purple' },
      { key: 'processing-videos', label: ['Video đang xử lý', 'Videos processing'], value: live.videosProcessing, format: 'integer', unit: ['video', 'videos'], tone: 'orange' },
      { key: 'alerts', label: ['Tín hiệu vượt ngưỡng', 'Signals over threshold'], value: data.activeAlertCount, format: 'integer', unit: ['tín hiệu', 'signals'], tone: data.criticalAlertCount ? 'red' : 'blue' },
    ];
  });

  ngOnInit(): void {
    this.load();
    this.refreshTimer = interval(60_000).subscribe(() => this.load(true));
  }

  ngOnDestroy(): void { this.refreshTimer?.unsubscribe(); }

  load(silent = false): void {
    if (!silent) {
      this.loading.set(true);
      this.error.set(false);
    }
    this.operations.getSystemOverview().subscribe({
      next: overview => { this.overview.set(overview); this.loading.set(false); this.error.set(false); },
      error: () => { this.error.set(true); this.loading.set(false); },
    });
  }

  setTab(tab: MonitorTab): void { this.activeTab.set(tab); }
  setFilter(filter: string): void { this.activeFilter.set(filter); }
  activeCount(): number { return this.overview()?.activeAlertCount ?? 0; }
  criticalCount(): number { return this.overview()?.criticalAlertCount ?? 0; }
  warningCount(): number {
    return (this.overview()?.signals ?? []).filter(item => item.isTriggered && item.severity === 'warning').length;
  }
  normalCount(): number { return (this.overview()?.signals ?? []).filter(item => !item.isTriggered).length; }

  tx(vietnamese: string, english: string): string {
    return this.i18n.currentLang() === 'vi' ? vietnamese : english;
  }

  formatNumber(value: number | null | undefined, fractionDigits = 0): string {
    if (value == null || !Number.isFinite(value)) return '—';
    return new Intl.NumberFormat(this.locale(), { maximumFractionDigits: fractionDigits, minimumFractionDigits: fractionDigits }).format(value);
  }

  formatBytes(value: number | null | undefined): string {
    if (value == null || !Number.isFinite(value) || value < 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    let amount = value;
    let unitIndex = 0;
    while (amount >= 1000 && unitIndex < units.length - 1) {
      amount /= 1000;
      unitIndex++;
    }
    const fractionDigits = unitIndex === 0 ? 0 : amount >= 100 ? 2 : amount >= 10 ? 1 : 2;
    return `${this.formatNumber(amount, fractionDigits)} ${units[unitIndex]}`;
  }

  activityTime(value: string): string {
    return this.formatDateTime(value, { dateStyle: 'short', timeStyle: 'short' });
  }

  providerStatus(status: string): string {
    const labels: Record<string, [string, string]> = {
      available: ['Đã đo', 'Measured'],
      partial: ['Đo một phần', 'Partly measured'],
      unmonitored: ['Chờ cấu hình', 'Configuration needed'],
      error: ['Lỗi kết nối/API', 'API or connection error'],
    };
    const [vi, en] = labels[status] ?? [status, status];
    return this.tx(vi, en);
  }

  activitySeverity(status: string): string {
    return status === 'error' || status === 'critical' ? 'critical'
      : status === 'warning' ? 'warning' : 'normal';
  }

  activityCategory(category: string): string {
    const labels: Record<string, [string, string]> = {
      upload: ['Upload', 'Upload'], payment: ['Thanh toán', 'Payment'],
      incident: ['Sự cố', 'Incident'], admin: ['Quản trị', 'Admin'], system: ['Hệ thống', 'System'],
    };
    const [vi, en] = labels[category] ?? [category, category];
    return this.tx(vi, en);
  }

  activityItems(items: SystemActivity[] | null | undefined): SystemActivity[] {
    return items ?? [];
  }

  formatMetric(metric: MetricCard): string {
    const value = this.formatNumber(metric.value, metric.format === 'percent' ? 1 : 0);
    return metric.format === 'percent' && metric.value != null ? value + '%' : value;
  }

  metricUnit(metric: MetricCard): string {
    const [vi, en] = metric.unit;
    return this.tx(vi, en);
  }

  statusLabel(status: string): string {
    const labels: Record<string, [string, string]> = {
      healthy: ['Hoạt động', 'Operational'],
      warning: ['Cảnh báo', 'Warning'],
      error: ['Lỗi kết nối', 'Connection error'],
      checking: ['Đang kiểm tra', 'Checking'],
      unmonitored: ['Chưa tích hợp kiểm tra', 'Health check not integrated'],
    };
    const [vi, en] = labels[status] ?? [status, status];
    return this.tx(vi, en);
  }

  serviceName(key: string): string {
    const names: Record<string, [string, string]> = {
      api: ['Backend API', 'Backend API'],
      database: ['Neon PostgreSQL', 'Neon PostgreSQL'],
      redis: ['Redis · Upstash', 'Redis · Upstash'],
      vercel: ['Vercel · frontend', 'Vercel · frontend'],
      ec2: ['AWS EC2 · API server', 'AWS EC2 · API server'],
      storage: ['Cloudflare R2', 'Cloudflare R2'],
      signalr: ['SignalR', 'SignalR'],
    };
    const [vi, en] = names[key] ?? [key, key];
    return this.tx(vi, en);
  }

  severityLabel(severity: string): string {
    const labels: Record<string, [string, string]> = {
      critical: ['Nghiêm trọng', 'Critical'], warning: ['Cảnh báo', 'Warning'], normal: ['Bình thường', 'Normal'],
    };
    const [vi, en] = labels[severity] ?? [severity, severity];
    return this.tx(vi, en);
  }

  categoryLabel(category: string): string {
    const labels: Record<string, [string, string]> = {
      runtime: ['Vận hành', 'Runtime'], security: ['Bảo mật', 'Security'],
      moderation: ['Kiểm duyệt', 'Moderation'], payments: ['Thanh toán', 'Payments'],
    };
    const [vi, en] = labels[category] ?? [category, category];
    return this.tx(vi, en);
  }

  signalSeverityClass(item: SystemSignal): string {
    return item.severity === 'critical' ? 'critical' : item.severity === 'warning' ? 'warning' : 'normal';
  }

  serviceIcon(key: string): string {
    // Use provider marks; SignalR is represented by its published .NET package icon.
    return ({
      api: '/assets/logo-mark.webp',
      database: '/assets/brands/neon.svg',
      redis: '/assets/brands/upstash.webp',
      vercel: '/assets/brands/vercel.svg',
      storage: '/assets/brands/cloudflare.webp',
      signalr: '/assets/brands/signalr.webp',
    } as Record<string, string>)[key.toLowerCase()] ?? '/assets/logo-mark.webp';
  }

  signalTitle(item: SystemSignal): string { return this.i18n.t('operations.signal.' + this.signalKey(item) + '.title'); }

  signalDescription(item: SystemSignal): string {
    const count = this.formatNumber(item.currentValue);
    const value = item.key === 'memory' ? this.formatNumber(item.currentValue, 1) : count;
    return this.i18n.t('operations.signal.' + this.signalKey(item) + '.description', { count, value });
  }

  signalValue(item: SystemSignal): string {
    return this.formatNumber(item.currentValue, 1) + ' ' + item.unit;
  }

  signalThreshold(item: SystemSignal): string {
    return this.i18n.t('operations.threshold') + ' ' + this.formatNumber(item.threshold, 1) + ' ' + item.unit;
  }

  signalPercent(item: SystemSignal): number {
    return item.threshold > 0 ? Math.min(100, item.currentValue / item.threshold * 100) : 0;
  }

  canOpen(item: SystemSignal): boolean {
    if (!item.actionUrl) return false;
    const requiredPermission: Record<string, string> = {
      '/users': 'user.view', '/moderation/reports': 'report.view',
      '/moderation/videos': 'moderation.view_queue', '/payments': 'payment.view', '/system/logs': 'audit.view',
    };
    const permission = requiredPermission[item.actionUrl];
    return !permission || this.auth.hasPermission(permission);
  }

  signalOf(data: SystemOverview, key: string): SystemSignal | null {
    return data.signals.find(item => item.key === key) ?? null;
  }

  sampledAt(): string {
    const value = this.overview()?.sampledAt;
    return this.formatDateTime(value, { dateStyle: 'medium', timeStyle: 'short' });
  }

  collectedSince(): string {
    const value = this.overview()?.apiTraffic.collectedSince;
    return this.formatDateTime(value, { dateStyle: 'medium', timeStyle: 'short' });
  }

  r2SampledAt(value: string | null | undefined): string {
    return this.formatDateTime(value, { dateStyle: 'medium', timeStyle: 'short' });
  }

  bucketLabel(bucket: ApiTrafficBucket): string {
    return this.formatDateTime(bucket.bucketStart, { hour: '2-digit' });
  }

  bucketTooltip(bucket: ApiTrafficBucket): string {
    const start = this.formatDateTime(bucket.bucketStart, { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' });
    if (!bucket.isObserved) return start + ' · ' + this.tx('Chưa có dữ liệu từ instance này', 'Not observed by this instance');
    return start + ' · ' + this.formatNumber(bucket.requests) + ' ' + this.tx('request', 'requests')
      + ' · ' + this.formatNumber(bucket.serverErrors) + ' 5xx';
  }

  barHeight(bucket: ApiTrafficBucket, metric: 'requests' | 'serverErrors'): number {
    if (!bucket.isObserved) return 0;
    const observed = this.overview()?.apiTraffic.hourly.filter(item => item.isObserved) ?? [];
    const maximum = Math.max(0, ...observed.map(item => item[metric] ?? 0));
    const value = bucket[metric];
    if (maximum === 0 || value == null || value === 0) return 0;
    return Math.max(2, value / maximum * 100);
  }

  trackMetric(_: number, item: MetricCard): string { return item.key; }
  trackSignal(_: number, item: SystemSignal): string { return item.key; }
  trackService(_: number, item: { key: string }): string { return item.key; }
  trackBucket(_: number, item: ApiTrafficBucket): string { return item.bucketStart; }

  private signalKey(item: SystemSignal): string {
    return ({
      memory: 'memory', 'signup-burst': 'signup', 'locked-accounts': 'locked',
      'abuse-reports': 'abuse', 'moderation-backlog': 'moderation', 'payment-failures': 'payments', 'api-errors': 'apiErrors',
    } as Record<string, string>)[item.key] ?? 'memory';
  }

  private formatDateTime(value: string | null | undefined, options: Intl.DateTimeFormatOptions): string {
    if (!value) return '—';
    const date = new Date(value);
    if (!Number.isFinite(date.getTime())) return '—';
    try {
      return new Intl.DateTimeFormat(this.locale(), options).format(date);
    } catch {
      return date.toISOString().replace('T', ' ').slice(0, 16) + ' UTC';
    }
  }

  private locale(): string { return this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US'; }
}
