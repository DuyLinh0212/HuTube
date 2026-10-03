import { Component, OnInit, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { TranslatePipe } from '../../core/translate.pipe';
import { I18nService } from '../../core/i18n.service';
import { AdminOperationsService, ReportDay, ReportSlice, SystemMetric, SystemReport } from './operations.service';

type MetricKey = 'users' | 'verifiedUsers' | 'videos' | 'publishedVideos' | 'channels' | 'views' | 'comments' | 'likes' | 'subscribers' | 'reports' | 'pendingReports' | 'pendingReviews' | 'pendingAppeals' | 'activeSessions' | 'shares';

interface MetricCard { key: MetricKey; icon: string; tone: string; }

@Component({
  selector: 'app-system-reports-page',
  imports: [DatePipe, TranslatePipe],
  templateUrl: './system-reports-page.html',
  styleUrl: './system-reports-page.scss',
})
export class SystemReportsPage implements OnInit {
  private readonly operations = inject(AdminOperationsService);
  readonly i18n = inject(I18nService);
  readonly report = signal<SystemReport | null>(null);
  readonly loading = signal(true);
  readonly error = signal(false);
  readonly days = signal(30);
  readonly periods = [7, 30, 90];
  readonly metricCards: MetricCard[] = [
    { key: 'users', icon: '♙', tone: 'blue' }, { key: 'verifiedUsers', icon: '✓', tone: 'green' },
    { key: 'videos', icon: '▶', tone: 'pink' }, { key: 'publishedVideos', icon: '↗', tone: 'violet' },
    { key: 'channels', icon: '▣', tone: 'cyan' }, { key: 'views', icon: '◉', tone: 'orange' },
    { key: 'comments', icon: '☷', tone: 'amber' }, { key: 'likes', icon: '♥', tone: 'rose' },
    { key: 'subscribers', icon: '♧', tone: 'teal' }, { key: 'reports', icon: '⚑', tone: 'red' },
    { key: 'pendingReports', icon: '◷', tone: 'orange' }, { key: 'pendingReviews', icon: '◌', tone: 'violet' },
    { key: 'pendingAppeals', icon: '↺', tone: 'blue' }, { key: 'activeSessions', icon: '⌘', tone: 'green' },
    { key: 'shares', icon: '↗', tone: 'cyan' },
  ];

  ngOnInit(): void { this.load(); }

  load(days = this.days()): void {
    this.days.set(days);
    this.loading.set(true);
    this.error.set(false);
    this.operations.getReport(days).subscribe({
      next: report => { this.report.set(report); this.loading.set(false); },
      error: () => { this.error.set(true); this.loading.set(false); },
    });
  }

  metric(key: MetricKey): SystemMetric { return this.report()?.[key] ?? { total: 0, inPeriod: 0 }; }
  value(key: MetricKey): string { return this.formatNumber(this.metric(key).total); }
  periodValue(key: MetricKey): string { return `+${this.formatNumber(this.metric(key).inPeriod)}`; }
  formatNumber(value: number): string { return new Intl.NumberFormat(this.locale(), { maximumFractionDigits: 0 }).format(value); }
  formatMoney(value: number): string {
    return new Intl.NumberFormat(this.locale(), { style: 'currency', currency: 'VND', maximumFractionDigits: 0 }).format(value);
  }
  periodLabel(): string { return this.i18n.t('operations.periodCount', { days: this.days() }); }
  dailyLabel(day: ReportDay): string {
    const [year, month, date] = day.date.split('-').map(Number);
    return new Intl.DateTimeFormat(this.locale(), { day: '2-digit', month: 'short' }).format(new Date(year, month - 1, date));
  }
  pathFor(key: 'views' | 'newUsers'): string {
    const days = this.report()?.daily ?? [];
    if (!days.length) return '';
    const values = days.map(day => key === 'views' ? day.views : day.newUsers);
    const max = Math.max(1, ...values);
    return values.map((value, index) => {
      const x = 48 + index * (744 / Math.max(1, values.length - 1));
      const y = 190 - (value / max) * 148;
      return `${index === 0 ? 'M' : 'L'} ${x.toFixed(1)} ${y.toFixed(1)}`;
    }).join(' ');
  }
  areaFor(key: 'views' | 'newUsers'): string {
    const line = this.pathFor(key);
    return line ? `${line} L 792 190 L 48 190 Z` : '';
  }
  maxValue(key: 'views' | 'newUsers'): number {
    const days = this.report()?.daily ?? [];
    return Math.max(0, ...days.map(day => key === 'views' ? day.views : day.newUsers));
  }
  activityBars(): ReportDay[] {
    const days = this.report()?.daily ?? [];
    const stride = Math.max(1, Math.ceil(days.length / 30));
    return days.filter((_, index) => index % stride === 0 || index === days.length - 1);
  }
  barHeight(day: ReportDay): string {
    const max = Math.max(1, ...this.activityBars().map(item => item.newUsers));
    return `${Math.max(3, Math.round(day.newUsers / max * 100))}%`;
  }
  revenueBarHeight(day: ReportDay): number {
    const max = Math.max(0, ...(this.report()?.daily ?? []).map(item => item.revenue));
    return max ? Math.max(4, day.revenue / max * 100) : 4;
  }
  share(item: ReportSlice, list: ReportSlice[]): number {
    const total = list.reduce((sum, row) => sum + row.count, 0);
    return total ? Math.round(item.count / total * 100) : 0;
  }
  statusLabel(key: string): string {
    const normalized = key.replace(/[^a-z0-9]+/gi, '_').toLowerCase();
    const translated = this.i18n.t(`operations.status.${normalized}`);
    return translated === `operations.status.${normalized}` ? key : translated;
  }
  categoryColor(index: number): string { return ['#f62c68', '#5578f5', '#18a673', '#e39822', '#8a62df', '#26a6bf'][index % 6]; }
  trackMetric(_: number, card: MetricCard): string { return card.key; }
  trackSlice(_: number, item: ReportSlice): string { return item.key; }
  private locale(): string { return this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US'; }
}
