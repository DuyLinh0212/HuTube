import { Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { DecimalPipe, UpperCasePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Subject, debounceTime } from 'rxjs';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { AuthService, errorMessage } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';
import { AdminPlan, AdminPlansService } from '../plans/admin-plans.service';
import {
  AdminSubscription,
  AdminSubscriptionDetail,
  AdminSubscriptionStats,
  AdminSubscriptionsService,
  SubscriptionFilters,
} from './admin-subscriptions.service';

@Component({
  selector: 'app-admin-subscriptions-page',
  imports: [FormsModule, DecimalPipe, UpperCasePipe, TranslatePipe],
  templateUrl: './admin-subscriptions-page.html',
  styleUrl: './admin-subscriptions-page.scss',
})
export class AdminSubscriptionsPage implements OnInit {
  private readonly service = inject(AdminSubscriptionsService);
  private readonly plansService = inject(AdminPlansService);
  private readonly searchInput = new Subject<string>();
  private readonly destroyRef = inject(DestroyRef);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);
  readonly items = signal<AdminSubscription[]>([]);
  readonly selectedId = signal<string | null>(null);
  readonly detail = signal<AdminSubscriptionDetail | null>(null);
  readonly stats = signal<AdminSubscriptionStats | null>(null);
  readonly plans = signal<AdminPlan[]>([]);
  readonly plansLoading = signal(false);
  readonly plansError = signal('');
  readonly loading = signal(true);
  readonly detailLoading = signal(false);
  readonly exporting = signal(false);
  readonly action = signal('');
  readonly error = signal('');
  readonly notice = signal('');
  readonly showPlanSwitch = signal(false);

  search = '';
  status = 'all';
  planId = '';
  cycle = 'all';
  renewal = 'all';
  fromDate = '';
  toDate = '';
  switchPlanId = '';
  page = 1;
  pageSize = 20;
  total = 0;
  hasMore = false;

  readonly metricCards = [
    { key: 'activeSubscriptions', label: 'subscriptions.metric.active', icon: '✓', tone: 'green' },
    { key: 'expiringSubscriptions', label: 'subscriptions.metric.expiring', icon: '◷', tone: 'orange' },
    { key: 'expiredSubscriptions', label: 'subscriptions.metric.expired', icon: '⊘', tone: 'pink' },
    { key: 'paidRevenueThisMonth', label: 'subscriptions.metric.revenueThisMonth', icon: '↗', tone: 'blue' },
  ] as const;

  readonly secondaryMetrics = [
    { key: 'autoRenewSubscriptions', label: 'subscriptions.metric.autoRenew', icon: '↻', tone: 'pink', money: false },
    { key: 'newSubscriptionsThisMonth', label: 'subscriptions.metric.newThisMonth', icon: '＋', tone: 'cyan', money: false },
    { key: 'paidTransactionsThisMonth', label: 'subscriptions.metric.paidThisMonth', icon: '✓', tone: 'green', money: false },
    { key: 'pendingPayments', label: 'subscriptions.metric.pendingPayments', icon: '◷', tone: 'orange', money: false },
    { key: 'failedPayments', label: 'subscriptions.metric.failedPayments', icon: '!', tone: 'red', money: false },
  ] as const;

  constructor() {
    this.searchInput.pipe(debounceTime(250), takeUntilDestroyed(this.destroyRef)).subscribe(() => {
      this.page = 1;
      this.load();
    });
  }

  ngOnInit(): void {
    this.loadPlans();
    this.load();
  }

  loadPlans(): void {
    this.plansLoading.set(true);
    this.plansError.set('');
    this.plansService.plans().subscribe({
      next: plans => plans.length ? this.setPlans(plans) : this.loadActivePlans(),
      error: () => this.loadActivePlans(),
    });
  }

  private loadActivePlans(): void {
    this.plansService.activePlans().subscribe({
      next: plans => this.setPlans(plans),
      error: error => {
        this.plansError.set(errorMessage(error, this.i18n));
        this.plansLoading.set(false);
      },
    });
  }

  private setPlans(plans: AdminPlan[]): void {
    this.plans.set(plans);
    this.plansLoading.set(false);
    const selected = this.detail()?.subscription;
    if (selected && !this.switchPlanId)
      this.switchPlanId = plans.find(plan => plan.status === 'active' && plan.planId !== selected.planId)?.planId ?? '';
  }

  filters(): SubscriptionFilters {
    return {
      search: this.search.trim() || undefined,
      status: this.status === 'all' ? undefined : this.status,
      planId: this.planId || undefined,
      cycle: this.cycle === 'all' ? undefined : this.cycle,
      autoRenew: this.renewal === 'all' ? undefined : this.renewal === 'yes',
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
        this.total = result.total;
        this.hasMore = result.hasMore;
        const selectedStillVisible = result.items.some(item => item.planHistoryId === this.selectedId());
        const nextId = selectedStillVisible ? this.selectedId() : result.items[0]?.planHistoryId ?? null;
        this.loading.set(false);
        if (nextId) this.selectById(nextId);
        else { this.selectedId.set(null); this.detail.set(null); }
      },
      error: error => {
        this.error.set(errorMessage(error, this.i18n));
        this.loading.set(false);
      },
    });
  }

  onSearchChanged(): void { this.searchInput.next(this.search); }

  onFilterChanged(): void {
    this.page = 1;
    this.load();
  }

  onDateChanged(): void {
    this.page = 1;
    this.load();
  }

  setStatus(status: string): void {
    this.status = status;
    this.page = 1;
    this.load();
  }

  select(item: AdminSubscription): void { this.selectById(item.planHistoryId); }
  closeDetails(): void { this.selectedId.set(null); this.detail.set(null); }

  statusLabel(status: string): string {
    const key = status === 'active' ? 'subscriptions.status.active'
      : status === 'expiring' ? 'subscriptions.status.expiring'
      : status === 'expired' ? 'subscriptions.status.expired'
      : `subscriptions.status.${status}`;
    const translated = this.i18n.t(key);
    return translated === key ? status : translated;
  }

  statusClass(status: string): string {
    return status === 'active' ? 'is-active' : status === 'expiring' ? 'is-expiring' : 'is-expired';
  }

  cycleLabel(cycle: string): string {
    const key = `subscriptions.cycle.${cycle}`;
    const translated = this.i18n.t(key);
    return translated === key ? cycle : translated;
  }

  paymentStatusLabel(status: string | null): string {
    if (!status) return this.i18n.t('subscriptions.noPayment');
    const key = `subscriptions.paymentStatus.${status}`;
    const translated = this.i18n.t(key);
    return translated === key ? status : translated;
  }

  formatMoney(amount: number | null | undefined): string {
    return new Intl.NumberFormat(this.locale(), { style: 'currency', currency: 'VND', maximumFractionDigits: 0 }).format(amount ?? 0);
  }

  formatDate(value: string | null, withTime = false): string {
    if (!value) return '—';
    return new Intl.DateTimeFormat(this.locale(), {
      day: '2-digit', month: '2-digit', year: 'numeric',
      ...(withTime ? { hour: '2-digit', minute: '2-digit' } : {}),
    }).format(new Date(value));
  }

  rowNumber(index: number): number { return (this.page - 1) * this.pageSize + index + 1; }
  get pageCount(): number { return Math.max(1, Math.ceil(this.total / this.pageSize)); }
  get pageEnd(): number { return Math.min(this.page * this.pageSize, this.total); }

  goToPage(page: number): void {
    if (page < 1 || page > this.pageCount || page === this.page) return;
    this.page = page;
    this.load();
  }

  setPageSize(size: number): void {
    this.pageSize = size;
    this.page = 1;
    this.load();
  }

  extendSubscription(): void {
    const selected = this.detail()?.subscription;
    if (!selected || this.action()) return;
    const message = this.i18n.format('subscriptions.extendConfirm', { days: selected.durationDays, plan: selected.planName });
    if (!window.confirm(message)) return;
    this.action.set('extend');
    this.runAction(this.service.extend(selected.planHistoryId), 'subscriptions.extended');
  }

  openSwitchPlan(): void {
    const selected = this.detail()?.subscription;
    if (!selected) return;
    this.switchPlanId = this.plans().find(plan => plan.status === 'active' && plan.planId !== selected.planId)?.planId ?? '';
    this.showPlanSwitch.set(true);
  }

  closeSwitchPlan(): void { this.showPlanSwitch.set(false); }

  confirmSwitchPlan(): void {
    const selected = this.detail()?.subscription;
    const target = this.plans().find(plan => plan.planId === this.switchPlanId && plan.status === 'active');
    if (!selected || !target || this.action()) return;
    if (!window.confirm(this.i18n.format('subscriptions.switchConfirm', { plan: target.name }))) return;
    this.action.set('switch');
    this.showPlanSwitch.set(false);
    this.runAction(this.service.switchPlan(selected.planHistoryId, target.planId), 'subscriptions.switched');
  }

  exportReport(): void {
    if (this.exporting()) return;
    this.exporting.set(true);
    this.error.set('');
    this.service.export(this.filters()).subscribe({
      next: items => { this.downloadCsv(items); this.exporting.set(false); },
      error: error => { this.error.set(errorMessage(error, this.i18n)); this.exporting.set(false); },
    });
  }

  private selectById(historyId: string): void {
    this.selectedId.set(historyId);
    this.detailLoading.set(true);
    this.service.detail(historyId).subscribe({
      next: detail => { this.detail.set(detail); this.detailLoading.set(false); },
      error: error => { this.error.set(errorMessage(error, this.i18n)); this.detailLoading.set(false); },
    });
  }

  private runAction(request: import('rxjs').Observable<AdminSubscription>, successKey: string): void {
    request.subscribe({
      next: updated => {
        this.notice.set(this.i18n.t(successKey));
        this.selectedId.set(updated.planHistoryId);
        this.page = 1;
        this.load();
        this.action.set('');
      },
      error: error => {
        this.error.set(errorMessage(error, this.i18n));
        this.action.set('');
      },
    });
  }

  private downloadCsv(items: AdminSubscription[]): void {
    const headers = [
      this.i18n.t('subscriptions.colId'), this.i18n.t('subscriptions.colUser'), this.i18n.t('subscriptions.colPlan'),
      this.i18n.t('subscriptions.colStatus'), this.i18n.t('subscriptions.colCycle'), this.i18n.t('subscriptions.colStart'),
      this.i18n.t('subscriptions.colEnd'), this.i18n.t('subscriptions.colAutoRenew'), this.i18n.t('subscriptions.colLastPayment'),
    ];
    const rows = items.map(item => [item.planHistoryId, item.userName, item.planName, this.statusLabel(item.status), this.cycleLabel(item.cycle),
      this.formatDate(item.startedAt, true), this.formatDate(item.expiresAt, true), item.autoRenew ? this.i18n.t('subscriptions.yes') : this.i18n.t('subscriptions.no'),
      item.lastPaymentAmount == null ? '' : this.formatMoney(item.lastPaymentAmount)]);
    const csv = '\ufeff' + [headers, ...rows].map(row => row.map(value => `"${String(value ?? '').replaceAll('"', '""')}"`).join(',')).join('\r\n');
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = `hutube-subscriptions-${this.localDate(new Date())}.csv`;
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
