import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { MyPlan, Plan, PlanMember, PlanService } from '../../core/plan.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleCurrencyPipe } from '../../core/locale-currency.pipe';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

export type PlansView = 'overview' | 'catalog';

@Component({
  selector: 'app-plans-page',
  imports: [LocaleCurrencyPipe, LocaleDatePipe, LocaleNumberPipe, FormsModule, RouterLink, TranslatePipe],
  templateUrl: './plans-page.html',
  styleUrl: './plans-page.scss'
})
export class PlansPage {
  private readonly plansService = inject(PlanService);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);

  readonly view = signal<PlansView>('overview');
  readonly plans = signal<Plan[]>([]);
  readonly myPlan = signal<MyPlan | null>(null);
  readonly loading = signal(true);
  readonly planLoading = signal(false);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly message = signal('');
  inviteEmail = '';

  constructor() {
    this.load();
  }

  setView(view: PlansView) {
    this.view.set(view);
  }

  load() {
    this.loading.set(true);
    this.planLoading.set(false);
    this.error.set('');
    this.message.set('');
    this.myPlan.set(null);

    this.plansService.getPlans().pipe(finalize(() => this.loading.set(false))).subscribe({
      next: plans => this.plans.set(plans),
      error: () => this.error.set(this.i18n.t('plans.loadError'))
    });

    const loadCurrentPlan = () => {
      this.planLoading.set(true);
      this.plansService.getMyPlan().pipe(finalize(() => this.planLoading.set(false))).subscribe({
        next: plan => this.myPlan.set(plan),
        error: () => this.myPlan.set(null)
      });
    };

    if (this.auth.user()) {
      loadCurrentPlan();
    } else {
      this.auth.restore().subscribe({
        next: authenticated => { if (authenticated) loadCurrentPlan(); },
        error: () => undefined
      });
    }
  }

  isCurrentPlan(planId: string): boolean {
    const current = this.myPlan();
    if (!current || current.planId !== planId) return false;
    return !current.subscription || !current.subscription.isExpired;
  }

  canSwitch(planId: string): boolean {
    const current = this.myPlan();
    if (!current || !current.planId || (current.subscription && current.subscription.isExpired)) return false;
    const target = this.plans().find(plan => plan.planId === planId);
    return current.price > 0 && !!target && target.price >= current.price && (current.activePaidPlanIds ?? []).includes(planId);
  }

  quotaPercent(plan: MyPlan) {
    return plan.storageLimit ? Math.min(100, (plan.usedStorage / plan.storageLimit) * 100) : 0;
  }

  featureEnabled(plan: Plan, key: string): boolean {
    return plan.features?.[key] === true;
  }

  qualitySummary(plan: Plan): string {
    const upload = plan.maxVideoQuality || this.i18n.t('plans.defaultUploadQuality');
    const download = plan.maxDownloadQuality || plan.maxVideoQuality || this.i18n.t('plans.defaultDownloadQuality');
    return `${this.i18n.t('plans.qualityUpload', { quality: upload })} · ${this.i18n.t('plans.qualityDownload', { quality: download })}`;
  }

  formatBytes(bytes: number): string {
    if (bytes >= 1024 ** 3) return this.i18n.formatNumber(bytes / 1024 ** 3, { maximumFractionDigits: 2 }) + ' GB';
    return this.i18n.formatNumber(bytes / 1024 ** 2, { maximumFractionDigits: 2 }) + ' MB';
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

  invite() {
    const plan = this.myPlan();
    if (!plan || !this.inviteEmail.trim() || this.busy()) return;

    this.busy.set(true);
    this.error.set('');
    this.plansService.invite(this.inviteEmail.trim()).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: (member: PlanMember) => {
        this.myPlan.update(current => current ? { ...current, members: [...current.members, member] } : current);
        this.inviteEmail = '';
        this.message.set(this.i18n.t('plans.inviteSent'));
      },
      error: () => this.error.set(this.i18n.t('plans.inviteError'))
    });
  }

  revoke(memberId: string) {
    if (this.busy()) return;

    this.busy.set(true);
    this.error.set('');
    this.plansService.revoke(memberId).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => {
        this.myPlan.update(plan => plan ? { ...plan, members: plan.members.filter(member => member.planMemberId !== memberId) } : plan);
        this.message.set(this.i18n.t('plans.revokeSent'));
      },
      error: () => this.error.set(this.i18n.t('plans.revokeError'))
    });
  }
}
