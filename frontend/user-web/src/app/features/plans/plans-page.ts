import { ResultNoticeComponent } from '@dalitu/ui/result-notice.component';
import { FeedbackService } from '@dalitu/ui/feedback.service';
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
  imports: [ResultNoticeComponent, LocaleCurrencyPipe, LocaleDatePipe, LocaleNumberPipe, FormsModule, RouterLink, TranslatePipe],
  templateUrl: './plans-page.html',
  styleUrl: './plans-page.scss'
})
export class PlansPage {
  private readonly feedback = inject(FeedbackService);
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
    if (view === 'catalog' && this.myPlan()?.isSharedMember) return;
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
    if (current?.isSharedMember) return false;
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

  showAllocation(plan: MyPlan): boolean {
    return !plan.isSharedMember && plan.maxMembers > 1
      && plan.members.some(member => member.status === 'pending' || member.status === 'accepted');
  }

  showFamilyStorage(plan: MyPlan): boolean {
    return !plan.isSharedMember && !!plan.storageUsageBreakdown?.length
      && (plan.members.some(member => member.status === 'accepted')
        || plan.storageUsageBreakdown.some(item => !item.isOwner && item.storageUsed > 0));
  }

  storageSlices(plan: MyPlan) {
    const colors = ['#2563eb', '#0d9488', '#b45309', '#7c3aed', '#be185d'];
    const rows = (plan.storageUsageBreakdown ?? []).map((item, index) => {
      const name = item.displayName || plan.members.find(member => member.memberUserId === item.userId)?.memberEmail
        || this.i18n.t('plans.storageMember');
      return {
        key: item.userId ?? `other-${index}`,
        label: item.isOwner ? this.i18n.t('plans.storageOwner')
          : !item.userId ? this.i18n.t('plans.storageOther')
          : item.isFormerMember ? this.i18n.t('plans.storageFormerMember', { name }) : name,
        bytes: Math.max(0, item.storageUsed),
        color: item.isOwner ? 'var(--primary, #ff2b66)' : colors[Math.max(0, index - 1) % colors.length],
        free: false,
      };
    });
    rows.push({ key: 'free', label: this.i18n.t('plans.storageFree'),
      bytes: Math.max(0, plan.storageLimit - plan.usedStorage), color: 'var(--storage-free, #e2e8f0)', free: true });
    const scale = Math.max(plan.storageLimit, rows.reduce((sum, row) => sum + row.bytes, 0), 1);
    return rows.map(row => ({ ...row, percent: row.bytes / scale * 100 }));
  }

  storageSummary(plan: MyPlan): string {
    return this.storageSlices(plan).map(row => `${row.label}: ${this.formatBytes(row.bytes)}`).join('; ');
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
    return Math.max(0, plan.ownerAllocatedStorage - (plan.ownerOwnStorageUsed ?? 0));
  }

  inviteQuotaError(plan: MyPlan): string | null {
    const bytes = this.parseQuotaGb(this.inviteStorageGB);
    if (bytes === undefined) return this.i18n.t('plans.invalidQuota');
    if (bytes !== null && bytes > this.unallocatedStorage(plan))
      return this.i18n.t('plans.quotaExceedsAvailable', { available: this.formatBytes(this.unallocatedStorage(plan)) });
    return null;
  }

  memberQuotaError(plan: MyPlan, memberId: string): string | null {
    const bytes = this.parseQuotaGb(this.editingMemberStorageGB());
    if (bytes === undefined) return this.i18n.t('plans.invalidQuota');
    const available = this.maxMemberQuotaGB(plan, memberId) * 1024 ** 3;
    if (bytes !== null && bytes > available)
      return this.i18n.t('plans.quotaExceedsAvailable', { available: this.formatBytes(available) });
    return null;
  }

  maxMemberQuotaGB(plan: MyPlan, memberId: string): number {
    const otherAllocated = (plan.members ?? [])
      .filter(member => member.planMemberId !== memberId)
      .reduce((sum, member) => sum + (member.allocatedStorage ?? 0), 0);
    return Math.max(0, plan.storageLimit - (plan.ownerAllocatedStorage ?? 0) - otherAllocated) / 1024 ** 3;
  }

  ownerQuotaError(plan: MyPlan): string | null {
    const bytes = this.parseQuotaGb(this.ownerStorageGB());
    if (bytes === undefined) return this.i18n.t('plans.invalidQuota');
    const available = Math.max(0, plan.storageLimit - (plan.members ?? []).reduce((sum, member) => sum + (member.allocatedStorage ?? 0), 0));
    if (bytes !== null && bytes > available)
      return this.i18n.t('plans.quotaExceedsAvailable', { available: this.formatBytes(available) });
    return null;
  }

  maxOwnerQuotaGB(plan: MyPlan): number {
    return Math.max(0, plan.storageLimit - (plan.members ?? []).reduce((sum, member) => sum + (member.allocatedStorage ?? 0), 0)) / 1024 ** 3;
  }

  maxInviteQuotaGB(plan: MyPlan): number {
    return this.unallocatedStorage(plan) / 1024 ** 3;
  }

  private parseQuotaGb(value: number | null): number | null | undefined {
    if (value == null) return null;
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
    const quotaError = this.inviteQuotaError(plan) || this.quotaError(allocatedBytes);
    if (quotaError) {
      this.error.set(quotaError);
      return;
    }

    this.busy.set(true);
    this.error.set('');
    this.plansService.invite(this.inviteEmail.trim(), allocatedBytes).pipe(finalize(() => this.busy.set(false))).subscribe({
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
    this.editingMemberStorageGB.set(member.allocatedStorage != null ? Math.round(member.allocatedStorage / 1024 ** 3) : null);
  }

  cancelEditMember() {
    this.editingMemberId.set(null);
    this.editingMemberStorageGB.set(null);
  }

  saveMemberStorage(memberId: string) {
    if (this.busy()) return;
    const plan = this.myPlan();
    if (!plan) return;
    const member = plan.members.find(item => item.planMemberId === memberId);
    const bytes = this.parseQuotaGb(this.editingMemberStorageGB());
    const validationError = this.quotaError(bytes) || this.memberQuotaError(plan, memberId);
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
    if (!plan || !this.showAllocation(plan)) return;
    this.editingOwnerStorage.set(true);
    this.ownerStorageGB.set(plan.ownerAllocatedStorage != null ? Math.round(plan.ownerAllocatedStorage / 1024 ** 3) : null);
  }

  cancelEditOwnerStorage() {
    this.editingOwnerStorage.set(false);
    this.ownerStorageGB.set(null);
  }

  saveOwnerStorage() {
    if (this.busy()) return;
    const plan = this.myPlan();
    if (!plan || !this.showAllocation(plan)) return;
    const bytes = this.parseQuotaGb(this.ownerStorageGB());
    const validationError = this.quotaError(bytes) || this.ownerQuotaError(plan);
    if (validationError) {
      this.error.set(validationError);
      return;
    }
    if (bytes === undefined) return;
    if (plan?.ownerOwnStorageUsed && bytes !== null && bytes < plan.ownerOwnStorageUsed) {
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
        this.myPlan.update(plan => {
          if (!plan) return plan;
          const member = plan.members.find(item => item.planMemberId === memberId);
          return { ...plan, members: plan.members.filter(item => item.planMemberId !== memberId),
            storageUsageBreakdown: plan.storageUsageBreakdown?.flatMap(item =>
              member?.memberUserId && item.userId === member.memberUserId
                ? item.storageUsed > 0 ? [{ ...item, isFormerMember: true }] : [] : [item]) };
        });
        if (this.myPlan() && !this.showAllocation(this.myPlan()!)) this.cancelEditOwnerStorage();
        this.message.set(this.i18n.t('plans.revokeSent'));
      },
      error: () => this.error.set(this.i18n.t('plans.revokeError'))
    });
  }

  async leaveSharedPlan(plan: MyPlan) {
    if (this.busy() || !plan.isSharedMember) return;
    const owner = plan.sharedOwnerDisplayName || this.i18n.t('plans.sharedPlanOwnerFallback');
    if (!(await this.feedback.confirm(this.i18n.t('plans.leaveSharedConfirm', { owner }), { tone: 'danger' }))) return;
    this.busy.set(true);
    this.error.set('');
    this.plansService.leaveSharedPlan().pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => {
        this.load();
        this.message.set(this.i18n.t('plans.leftSharedPlan'));
      },
      error: err => this.error.set(err?.error?.message || this.i18n.t('plans.leaveSharedError'))
    });
  }
}
