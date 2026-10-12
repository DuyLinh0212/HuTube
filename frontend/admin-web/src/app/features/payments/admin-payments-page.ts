import { Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { DecimalPipe, UpperCasePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Subject, debounceTime } from 'rxjs';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { AuthService, errorMessage } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';
import {
  AdminPaymentDaily,
  AdminPaymentDetail,
  AdminPaymentItem,
  AdminPaymentMethod,
  AdminPaymentStats,
  AdminPaymentFilters,
  AdminPaymentsService,
} from './admin-payments.service';

@Component({
  selector: 'app-admin-payments-page',
  imports: [FormsModule, DecimalPipe, UpperCasePipe, TranslatePipe],
  templateUrl: './admin-payments-page.html',
  styleUrl: './admin-payments-page.scss',
})
export class AdminPaymentsPage implements OnInit {
  private readonly service = inject(AdminPaymentsService);
  private readonly searchInput = new Subject<string>();
  private readonly destroyRef = inject(DestroyRef);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);
  readonly items = signal<AdminPaymentItem[]>([]);
  readonly selectedId = signal<string | null>(null);
  readonly detail = signal<AdminPaymentDetail | null>(null);
  readonly stats = signal<AdminPaymentStats | null>(null);
  readonly daily = signal<AdminPaymentDaily[]>([]);
  readonly methods = signal<AdminPaymentMethod[]>([]);
  readonly availableMethods = signal<string[]>([]);
  readonly loading = signal(true);
  readonly detailLoading = signal(false);
  readonly exporting = signal(false);
  readonly error = signal('');
  readonly notice = signal('');

  search = '';
  status = 'all';
  method = 'all';
  type = 'all';
  fromDate = '';
  toDate = '';
  page = 1;
  pageSize = 20;
  total = 0;

  readonly metricCards = [
    { key: 'revenueInRange', label: 'payments.metric.revenue', icon: '↗', tone: 'blue', money: true },
    { key: 'revenueThisMonth', label: 'payments.metric.month', icon: '▣', tone: 'violet', money: true },
    { key: 'successfulTransactions', label: 'payments.metric.success', icon: '✓', tone: 'green', money: false },
    { key: 'refundTransactions', label: 'payments.metric.refund', icon: '↶', tone: 'orange', money: false },
    { key: 'pendingTransactions', label: 'payments.metric.pending', icon: '◷', tone: 'pink', money: false },
  ] as const;

  constructor() {
    this.searchInput.pipe(debounceTime(250), takeUntilDestroyed(this.destroyRef)).subscribe(() => {
      this.page = 1;
      this.load();
    });
  }

  ngOnInit(): void { this.load(); }

  filters(): AdminPaymentFilters {
    return {
      search: this.search.trim() || undefined,
      status: this.status === 'all' ? undefined : this.status,
      method: this.method === 'all' ? undefined : this.method,
      type: this.type === 'all' ? undefined : this.type,
      fromDate: this.fromDate || undefined,
      toDate: this.toDate || undefined,
    };
  }

  load(): void {
    this.loading.set(true);
    this.error.set('');
    this.service.list({ ...this.filters(), page: this.page, pageSize: this.pageSize }).subscribe({
      next: result => {
        this.items.set(result.items);
        this.stats.set(result.stats);
        this.daily.set(result.daily);
        this.methods.set(result.methods);
        this.availableMethods.set(result.availableMethods);
        this.total = result.total;
        const selectedIsVisible = result.items.some(item => item.paymentId === this.selectedId());
        const nextId = selectedIsVisible ? this.selectedId() : result.items[0]?.paymentId ?? null;
        this.loading.set(false);
        if (nextId) this.selectById(nextId);
        else { this.selectedId.set(null); this.detail.set(null); }
      },
      error: error => { this.error.set(errorMessage(error, this.i18n)); this.loading.set(false); },
    });
  }

  onSearchChanged(): void { this.searchInput.next(this.search); }
  onFilterChanged(): void { this.page = 1; this.load(); }
  onDateChanged(): void { this.page = 1; this.load(); }

  select(item: AdminPaymentItem): void { this.selectById(item.paymentId); }
  closeDetails(): void { this.selectedId.set(null); this.detail.set(null); }

  paymentStatusLabel(status: string): string {
    const key = `payments.status.${status}`;
    const translated = this.i18n.t(key);
    return translated === key ? status : translated;
  }

  statusClass(status: string): string {
    return status === 'paid' ? 'is-paid' : status === 'pending' || status === 'processing' ? 'is-pending'
      : status === 'refunded' ? 'is-refunded' : status === 'failed' ? 'is-failed' : 'is-cancelled';
  }

  methodLabel(method: string): string {
    const key = `payments.method.${method}`;
    const translated = this.i18n.t(key);
    return translated === key ? method.toUpperCase() : translated;
  }

  formatMoney(amount: number | null | undefined, currency = 'VND'): string {
    return new Intl.NumberFormat(this.locale(), { style: 'currency', currency, maximumFractionDigits: 0 }).format(amount ?? 0);
  }

  formatDate(value: string | null | undefined, withTime = false): string {
    if (!value) return '—';
    return new Intl.DateTimeFormat(this.locale(), {
      day: '2-digit', month: '2-digit', year: 'numeric',
      ...(withTime ? { hour: '2-digit', minute: '2-digit' } : {}),
    }).format(new Date(value));
  }

  get pageCount(): number { return Math.max(1, Math.ceil(this.total / this.pageSize)); }
  get pageStart(): number { return this.total ? (this.page - 1) * this.pageSize + 1 : 0; }
  get pageEnd(): number { return Math.min(this.page * this.pageSize, this.total); }
  goToPage(page: number): void {
    if (page < 1 || page > this.pageCount || page === this.page) return;
    this.page = page;
    this.load();
  }
  setPageSize(size: number): void { this.pageSize = size; this.page = 1; this.load(); }

  chartBars(): Array<AdminPaymentDaily & { x: number; y: number; width: number; height: number; label: string }> {
    const rows = this.chartWindow();
    const maxRevenue = Math.max(1, ...rows.map(row => row.revenue));
    const slot = 580 / Math.max(1, rows.length);
    return rows.map((row, index) => {
      const height = row.revenue > 0 ? (row.revenue / maxRevenue) * 112 : 0;
      return {
        ...row,
        x: 10 + index * slot + slot * .22,
        y: 166 - height,
        width: Math.max(2, slot * .56),
        height,
        label: new Date(`${row.date}T00:00:00Z`).toLocaleDateString(this.locale(), { day: '2-digit', month: '2-digit', timeZone: 'UTC' }),
      };
    });
  }

  transactionLine(): string {
    const rows = this.chartBars();
    const maxTransactions = Math.max(1, ...rows.map(row => row.transactions));
    return rows.map((row, index) => {
      const x = 10 + (index + .5) * 580 / Math.max(1, rows.length);
      const y = 164 - (row.transactions / maxTransactions) * 112;
      return `${x},${y}`;
    }).join(' ');
  }

  chartTicks(): string[] {
    const rows = this.chartBars();
    if (rows.length <= 6) return rows.map(row => row.label);
    return [0, Math.floor((rows.length - 1) / 3), Math.floor((rows.length - 1) * 2 / 3), rows.length - 1]
      .filter((index, position, all) => all.indexOf(index) === position).map(index => rows[index].label);
  }

  methodChartBackground(): string {
    const palette = ['#ef4b87', '#6186ff', '#a478f5', '#ff9c55', '#41bd90', '#97a6be'];
    let cursor = 0;
    const stops = this.methods().map((method, index) => {
      const start = cursor;
      cursor += method.share;
      return `${palette[index % palette.length]} ${start}% ${cursor}%`;
    });
    return stops.length ? `conic-gradient(${stops.join(',')})` : 'conic-gradient(#e8edf4 0% 100%)';
  }

  methodColor(index: number): string { return ['#ef4b87', '#6186ff', '#a478f5', '#ff9c55', '#41bd90', '#97a6be'][index % 6]; }
  methodColorFor(method: string): string { return this.methodColor(Math.max(0, this.methods().findIndex(item => item.method === method))); }
  methodTransactionTotal(): number { return this.methods().reduce((sum, item) => sum + item.transactions, 0); }
  shortTime(value: string): string { return new Intl.DateTimeFormat(this.locale(), { hour: '2-digit', minute: '2-digit' }).format(new Date(value)); }
  chartTick(index: number, fallback = ''): string { return this.chartTicks()[index] ?? fallback; }

  exportReport(): void {
    if (this.exporting()) return;
    this.exporting.set(true);
    this.error.set('');
    this.service.export(this.filters()).subscribe({
      next: items => { this.downloadCsv(items); this.exporting.set(false); },
      error: error => { this.error.set(errorMessage(error, this.i18n)); this.exporting.set(false); },
    });
  }

  copyValue(value: string, label: string): void {
    if (!value || !navigator.clipboard) return;
    const translatedLabel = this.i18n.t(label);
    navigator.clipboard.writeText(value).then(() => this.notice.set(this.i18n.format('payments.copied', { label: translatedLabel })))
      .catch(() => this.error.set(this.i18n.t('payments.copyFailed')));
  }

  private selectById(paymentId: string): void {
    this.selectedId.set(paymentId);
    this.detailLoading.set(true);
    this.service.detail(paymentId).subscribe({
      next: detail => { this.detail.set(detail); this.detailLoading.set(false); },
      error: error => { this.error.set(errorMessage(error, this.i18n)); this.detailLoading.set(false); },
    });
  }

  private chartWindow(): AdminPaymentDaily[] {
    const byDate = new Map(this.daily().map(row => [row.date, row]));
    const today = this.toDate ? new Date(`${this.toDate}T00:00:00`) : new Date();
    const requestedStart = this.fromDate ? new Date(`${this.fromDate}T00:00:00`) : new Date(today.getTime() - 29 * 86_400_000);
    const latestStart = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 89);
    const start = requestedStart < latestStart ? latestStart : requestedStart;
    const rows: AdminPaymentDaily[] = [];
    for (const date = new Date(start); date <= today; date.setDate(date.getDate() + 1)) {
      const key = this.localDate(date);
      rows.push(byDate.get(key) ?? { date: key, revenue: 0, transactions: 0 });
    }
    return rows;
  }

  private downloadCsv(items: AdminPaymentItem[]): void {
    const headers = [
      this.i18n.t('payments.colCode'), this.i18n.t('payments.colUser'), this.i18n.t('payments.colType'),
      this.i18n.t('payments.colMethod'), this.i18n.t('payments.colAmount'), this.i18n.t('payments.colStatus'),
      this.i18n.t('payments.colCreated'), this.i18n.t('payments.colReference'),
    ];
    const rows = items.map(item => [item.transactionCode, item.userName, item.planName, this.methodLabel(item.paymentMethod),
      this.formatMoney(item.amount, item.currency), this.paymentStatusLabel(item.status), this.formatDate(item.createdAt, true), item.sepayTransactionId ?? '']);
    const csv = '\ufeff' + [headers, ...rows].map(row => row.map(value => `"${String(value ?? '').replaceAll('"', '""')}"`).join(',')).join('\r\n');
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = `hutube-payments-${this.localDate(new Date())}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }

  private localDate(date: Date): string {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  private locale(): string { return this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US'; }
}
