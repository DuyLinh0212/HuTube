import { Component, inject, signal } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { MyPlan, Plan, PlanService, PlanShare } from '../../core/plan.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleCurrencyPipe } from '../../core/locale-currency.pipe';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({ selector: 'app-plan-detail-page', imports: [LocaleCurrencyPipe, LocaleNumberPipe, RouterLink, TranslatePipe], templateUrl: './plan-detail-page.html', styleUrl: './plan-detail-page.scss' })
export class PlanDetailPage {
  private route = inject(ActivatedRoute);
  private plansService = inject(PlanService);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);
  readonly plan = signal<Plan | null>(null);
  readonly myPlan = signal<MyPlan | null>(null);
  readonly share = signal<PlanShare | null>(null);
  readonly loading = signal(true);
  readonly message = signal('');
  readonly error = signal('');
  readonly busy = signal(false);

  constructor() {
    const planId = this.route.snapshot.paramMap.get('planId');
    if (!planId) { this.error.set(this.i18n.t('plans.invalid')); this.loading.set(false); return; }
    this.plansService.getPlan(planId).subscribe({
      next: plan => { this.plan.set(plan); this.loading.set(false); },
      error: () => { this.error.set(this.i18n.t('plans.notFound')); this.loading.set(false); }
    });
    this.plansService.getShare(planId).subscribe({ next: share => this.share.set(share), error: () => {} });
    if (this.auth.user()) {
      this.plansService.getMyPlan().subscribe({ next: mp => this.myPlan.set(mp), error: () => {} });
    }
  }

  isCurrentActivePlan(): boolean {
    const p = this.plan();
    const mp = this.myPlan();
    if (!p || !mp || mp.planId !== p.planId) return false;
    if (mp.subscription && mp.subscription.isExpired) return false;
    return true;
  }

  canSwitchToThisPlan(): boolean {
    const p = this.plan();
    const mp = this.myPlan();
    if (!mp || !mp.planId) return true; // Chưa có gói -> đăng ký mới được
    if (mp.subscription && mp.subscription.isExpired) return true; // Gói cũ đã hết hạn -> đăng ký được
    if (mp.price === 0) return true; // Gói miễn phí -> được mua gói trả phí
    // Gói cũ chưa hết hạn -> không được hạ gói, chỉ đổi sang gói đã mua và còn hạn
    return mp.price > 0 && !!p && p.price >= mp.price && (mp.activePaidPlanIds ?? []).includes(p.planId);
  }

  async copyShareUrl() {
    const url = this.share()?.shareUrl;
    if (!url) return;
    try {
      if (!navigator.clipboard) throw new Error('clipboard-unavailable');
      await navigator.clipboard.writeText(url);
      this.message.set(this.i18n.t('plans.copiedShare'));
    } catch {
      this.error.set(this.i18n.t('plans.copyError'));
    }
  }

  async nativeShare() {
    const share = this.share();
    if (!share || !navigator.share) return this.copyShareUrl();
    try {
      await navigator.share({ title: share.name, text: share.description || this.i18n.t('plans.shareText', { name: share.name }), url: share.shareUrl });
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') return;
      this.error.set(this.i18n.t('plans.shareError'));
    }
  }

  formatBytes(bytes: number): string {
    if (bytes >= 1024 ** 3) return `${this.i18n.formatNumber(bytes / 1024 ** 3, { maximumFractionDigits: 2 })} GB`;
    return `${this.i18n.formatNumber(bytes / 1024 ** 2, { maximumFractionDigits: 2 })} MB`;
  }

  formatDuration(seconds: number): string {
    const minutes = Math.max(1, Math.round((seconds || 0) / 60));
    const hours = Math.floor(minutes / 60);
    const remainder = minutes % 60;
    if (!hours) return this.i18n.t('plans.minutes', { count: this.i18n.formatNumber(minutes, { useGrouping: false }) });
    return remainder
      ? this.i18n.t('plans.hoursMinutes', { hours: this.i18n.formatNumber(hours, { useGrouping: false }), minutes: this.i18n.formatNumber(remainder, { useGrouping: false }) })
      : this.i18n.t('plans.hours', { count: this.i18n.formatNumber(hours, { useGrouping: false }) });
  }

  hasFeature(plan: Plan, key: string): boolean { return plan.features?.[key] === true; }

  membersLabel(count: number) {
    return this.i18n.t('plans.members', { count: this.i18n.formatNumber(count) });
  }

  subscribe() {
    const plan = this.plan();
    if (!plan || this.busy()) return;
    this.busy.set(true); this.error.set('');
    this.plansService.subscribe(plan.planId).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => {
        this.message.set(this.i18n.t('plans.subscribeSuccess'));
        this.plansService.getMyPlan().subscribe({ next: myPlan => this.myPlan.set(myPlan), error: () => {} });
      },
      error: err => this.error.set(this.i18n.t('plans.subscribeErrorFallback', { status: String(err?.status || 500) }))
    });
  }
}
