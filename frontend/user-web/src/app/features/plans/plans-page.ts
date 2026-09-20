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
  inviteStorageGB: number | null = null;
  readonly editingMemberId = signal<string | null>(null);
  readonly editingMemberStorageGB = signal<number | null>(null);
  readonly editingOwnerStorage = signal<boolean>(false);
  readonly ownerStorageGB = signal<number | null>(null);

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
    if (!target) return false;
    // Nâng cấp lên gói cao hơn: luôn cho phép
    if (current.price > 0 && target.price > current.price) return true;
    // Chuyển ngang giữa các gói cùng giá: kiểm tra đã mua chưa
    return current.price > 0 && target.price === current.price && (current.activePaidPlanIds ?? []).includes(planId);
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

  totalAllocatedStorage(plan: MyPlan): number {
    return (plan.ownerAllocatedStorage ?? 0) + (plan.members ?? []).reduce((sum, m) => sum + (m.allocatedStorage ?? 0), 0);
  }

  unallocatedStorage(plan: MyPlan): number {
    return Math.max(0, plan.storageLimit - this.totalAllocatedStorage(plan));
  }
  memberRemainingStorage(member: PlanMember): number | null {
    if (member.allocatedStorage == null) return null;
    return Math.max(0, member.allocatedStorage - (member.storageUsed ?? 0));
  }

  ownerRemainingStorage(plan: MyPlan): number | null {
    if (plan.ownerAllocatedStorage == null) return null;
    return Math.max(0, plan.ownerAllocatedStorage - (plan.usedStorage ?? 0));
  }

  private parseQuotaGb(value: number | null): number | null | undefined {
    if (value == null || value === 0) return null;
    if (!Number.isFinite(value) || value < 0) return undefined;
    return Math.round(value * 1024 ** 3);
  }

  private quotaError(bytes: number | null | undefined): string | null {
    if (bytes === undefined) return this.i18n.t('plans.invalidQuota');
    return null;
  }

  invite() {
    const plan = this.myPlan();
    if (!plan || !this.inviteEmail.trim() || this.busy()) return;

    const allocatedBytes = this.parseQuotaGb(this.inviteStorageGB);
    const quotaError = this.quotaError(allocatedBytes);
    if (quotaError) {
      this.error.set(quotaError);
      return;
    }

    this.busy.set(true);
    this.error.set('');    this.plansService.invite(this.inviteEmail.trim(), allocatedBytes).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: (member: PlanMember) => {
        this.myPlan.update(current => current ? { ...current, members: [...current.members, member] } : current);
        this.inviteEmail = '';
        this.inviteStorageGB = null;
        this.message.set(this.i18n.t('plans.inviteSent'));
      },
      error: (err) => this.error.set(err?.error?.message || this.i18n.t('plans.inviteError'))
    });
  }

  startEditMember(member: PlanMember) {
    this.editingMemberId.set(member.planMemberId);
    this.editingMemberStorageGB.set(member.allocatedStorage ? Math.round(member.allocatedStorage / 1024 ** 3) : null);
  }

  cancelEditMember() {
    this.editingMemberId.set(null);
    this.editingMemberStorageGB.set(null);
  }

  saveMemberStorage(memberId: string) {
    if (this.busy()) return;
    const member = this.myPlan()?.members.find(item => item.planMemberId === memberId);
    const bytes = this.parseQuotaGb(this.editingMemberStorageGB());
    const validationError = this.quotaError(bytes);
    if (validationError) {
      this.error.set(validationError);
      return;
    }
    if (bytes === undefined) return;
    if (member?.storageUsed && bytes !== null && bytes < member.storageUsed) {
      this.error.set(this.i18n.t('plans.quotaBelowUsed'));
      return;
    }
    this.busy.set(true);
    this.error.set('');
    this.plansService.updateMemberStorage(memberId, bytes).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: (updated: PlanMember) => {
        this.myPlan.update(plan => plan ? {
          ...plan,
          members: plan.members.map(m => m.planMemberId === memberId ? { ...m, allocatedStorage: updated.allocatedStorage } : m)
        } : plan);
        this.cancelEditMember();
        this.message.set(this.i18n.t('plans.storageUpdated'));
      },
      error: (err) => this.error.set(err?.error?.message || this.i18n.t('plans.storageUpdateError'))
    });
  }

  startEditOwnerStorage() {
    const plan = this.myPlan();
    if (!plan) return;
    this.editingOwnerStorage.set(true);
    this.ownerStorageGB.set(plan.ownerAllocatedStorage ? Math.round(plan.ownerAllocatedStorage / 1024 ** 3) : null);
  }

  cancelEditOwnerStorage() {
    this.editingOwnerStorage.set(false);
    this.ownerStorageGB.set(null);
  }

  saveOwnerStorage() {
    if (this.busy()) return;
    const plan = this.myPlan();
    const bytes = this.parseQuotaGb(this.ownerStorageGB());
    const validationError = this.quotaError(bytes);
    if (validationError) {
      this.error.set(validationError);
      return;
    }
    if (bytes === undefined) return;
    if (plan?.usedStorage && bytes !== null && bytes < plan.usedStorage) {
      this.error.set(this.i18n.t('plans.quotaBelowUsed'));
      return;
    }
    this.busy.set(true);
    this.error.set('');
    this.plansService.updateOwnerStorage(bytes).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => {
        this.myPlan.update(plan => plan ? { ...plan, ownerAllocatedStorage: bytes } : plan);
        this.cancelEditOwnerStorage();
        this.message.set(this.i18n.t('plans.storageUpdated'));
      },
      error: (err) => this.error.set(err?.error?.message || this.i18n.t('plans.storageUpdateError'))
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
