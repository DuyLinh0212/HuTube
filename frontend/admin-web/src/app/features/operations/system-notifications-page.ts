import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { TranslatePipe } from '../../core/translate.pipe';
import { I18nService } from '../../core/i18n.service';
import { AuthService } from '../../core/auth.service';
import { AdminOperationsService, SystemOverview, SystemSignal } from './operations.service';

@Component({
  selector: 'app-system-notifications-page',
  imports: [RouterLink, TranslatePipe],
  templateUrl: './system-notifications-page.html',
  styleUrl: './system-notifications-page.scss',
})
export class SystemNotificationsPage implements OnInit {
  private readonly operations = inject(AdminOperationsService);
  readonly i18n = inject(I18nService);
  private readonly auth = inject(AuthService);
  readonly overview = signal<SystemOverview | null>(null);
  readonly loading = signal(true);
  readonly error = signal(false);
  readonly activeFilter = signal('all');
  readonly visibleSignals = computed(() => {
    const filter = this.activeFilter();
    const signals = this.overview()?.signals ?? [];
    return filter === 'all' ? signals : signals.filter(signal => signal.category === filter);
  });

  ngOnInit(): void { this.load(); }

  load(): void {
    this.loading.set(true);
    this.error.set(false);
    this.operations.getSystemOverview().subscribe({
      next: overview => { this.overview.set(overview); this.loading.set(false); },
      error: () => { this.error.set(true); this.loading.set(false); },
    });
  }

  setFilter(filter: string): void { this.activeFilter.set(filter); }
  triggeredCount(): number { return this.overview()?.activeAlertCount ?? 0; }
  criticalCount(): number { return this.overview()?.criticalAlertCount ?? 0; }
  normalCount(): number { return (this.overview()?.signals ?? []).filter(signal => !signal.isTriggered).length; }
  severityKey(signal: SystemSignal): string { return `operations.severity.${signal.severity}`; }
  categoryKey(category: string): string { return `operations.category.${category}`; }
  signalTitle(signal: SystemSignal): string { return this.i18n.t(`operations.signal.${this.signalKey(signal)}.title`); }
  signalDescription(signal: SystemSignal): string {
    const count = new Intl.NumberFormat(this.locale(), { maximumFractionDigits: 0 }).format(signal.currentValue);
    const value = signal.key === 'memory' ? String(signal.currentValue) : count;
    return this.i18n.t(`operations.signal.${this.signalKey(signal)}.description`, { count, value });
  }
  severityIcon(signal: SystemSignal): string {
    return signal.severity === 'critical' ? '!' : signal.severity === 'warning' ? '△' : '✓';
  }
  valueLabel(signal: SystemSignal): string {
    const formatter = new Intl.NumberFormat(this.locale(), { maximumFractionDigits: 0 });
    return `${formatter.format(signal.currentValue)} ${signal.unit}`;
  }
  thresholdLabel(signal: SystemSignal): string {
    return `${this.i18n.t('operations.threshold')} ${new Intl.NumberFormat(this.locale()).format(signal.threshold)} ${signal.unit}`;
  }
  canOpen(signal: SystemSignal): boolean {
    if (!signal.actionUrl) return false;
    const requiredPermission: Record<string, string> = {
      '/users': 'user.view', '/moderation/reports': 'report.view',
      '/moderation/videos': 'moderation.view_queue', '/payments': 'payment.view',
      '/system/logs': 'audit.view',
    };
    const permission = requiredPermission[signal.actionUrl];
    return !permission || this.auth.hasPermission(permission);
  }
  meterPercent(signal: SystemSignal): number { return signal.threshold ? Math.min(100, signal.currentValue / signal.threshold * 100) : 0; }
  sampledAt(): string {
    const value = this.overview()?.sampledAt;
    return value ? new Intl.DateTimeFormat(this.locale(), { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : '';
  }
  trackSignal(_: number, signal: SystemSignal): string { return signal.key; }
  private signalKey(signal: SystemSignal): string {
    return ({
      memory: 'memory', 'signup-burst': 'signup', 'locked-accounts': 'locked',
      'abuse-reports': 'abuse', 'moderation-backlog': 'moderation', 'payment-failures': 'payments', 'api-errors': 'apiErrors',
    } as Record<string, string>)[signal.key] ?? 'memory';
  }
  private locale(): string { return this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US'; }
}
