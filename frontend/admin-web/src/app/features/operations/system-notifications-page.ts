import { Component, OnDestroy, OnInit, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Subscription, interval } from 'rxjs';
import { TranslatePipe } from '../../core/translate.pipe';
import { I18nService } from '../../core/i18n.service';
import { AuthService } from '../../core/auth.service';
import { AdminOperationsService, ApiTrafficBucket, SystemOverview, SystemSignal } from './operations.service';

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
      error: ['Không hoạt động', 'Unavailable'],
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
      redis: ['Redis', 'Redis'],
      storage: ['Cloudflare R2 / Storage', 'Cloudflare R2 / Storage'],
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
    return value ? new Intl.DateTimeFormat(this.locale(), { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : '';
  }

  collectedSince(): string {
    const value = this.overview()?.apiTraffic.collectedSince;
    return value ? new Intl.DateTimeFormat(this.locale(), { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : '';
  }

  bucketLabel(bucket: ApiTrafficBucket): string {
    return new Intl.DateTimeFormat(this.locale(), { hour: '2-digit' }).format(new Date(bucket.bucketStart));
  }

  bucketTooltip(bucket: ApiTrafficBucket): string {
    const start = new Intl.DateTimeFormat(this.locale(), { dateStyle: 'short', hour: '2-digit', minute: '2-digit' }).format(new Date(bucket.bucketStart));
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

  private locale(): string { return this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US'; }
}
