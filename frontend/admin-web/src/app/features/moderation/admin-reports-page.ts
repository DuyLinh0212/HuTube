import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { AdminModerationService, ReportCaseDetail, ReportCaseReportDetail, ReportCaseSummary } from './admin-moderation.service';
import { TranslatePipe } from '../../core/translate.pipe';

type QueueStatus = 'ALL' | 'pending' | 'reviewing' | 'resolved' | 'escalated';
type ReportDecision = 'dismiss' | 'warn' | 'age_restrict' | 'recommendation_restricted' | 'hide' | 'remove' | 'upload_restriction' | 'strike' | 'lock_channel' | 'escalate';

@Component({
  selector: 'app-admin-reports-page',
  standalone: true,
  imports: [CommonModule, FormsModule, TranslatePipe],
  templateUrl: './admin-reports-page.html',
  styleUrl: './admin-reports-page.scss'
})
export class AdminReportsPage implements OnInit {
  private readonly moderation = inject(AdminModerationService);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);
  readonly loading = signal(true);
  readonly submitting = signal(false);
  readonly error = signal<string | null>(null);
  readonly successMessage = signal<string | null>(null);
  readonly cases = signal<ReportCaseSummary[]>([]);
  readonly total = signal(0);
  readonly selectedTargetType = signal<'ALL' | 'video' | 'comment' | 'channel'>('ALL');
  readonly selectedStatus = signal<QueueStatus>('pending');
  readonly searchQuery = signal('');
  readonly activeCase = signal<ReportCaseDetail | null>(null);
  readonly selectedReports = signal<Record<string, boolean>>({});
  readonly dispositionReason = signal('');
  readonly decision = signal<ReportDecision>('dismiss');
  readonly decisionReason = signal('');
  readonly internalNote = signal('');
  readonly policyCode = signal('');
  readonly restrictionDays = signal(7);

  readonly canClaim = computed(() => this.auth.hasPermission('report.claim'));
  readonly canResolve = computed(() => this.auth.hasPermission('report.resolve'));
  readonly canManageStrikes = computed(() => this.auth.hasPermission('strike.manage'));
  readonly canLockChannels = computed(() => this.auth.hasPermission('channel.lock'));
  readonly availableDecisions = computed(() => {
    const targetType = this.activeCase()?.case.targetType;
    const hideLabelKey = targetType === 'channel' ? 'reports.decisions.hideChannel' : targetType === 'comment' ? 'reports.decisions.hideComment' : 'reports.decisions.hideOther';
    const removeLabelKey = targetType === 'channel' ? 'reports.decisions.removeChannel' : targetType === 'comment' ? 'reports.decisions.removeComment' : 'reports.decisions.removeOther';
    const hideLabel = this.i18n.t(hideLabelKey);
    const removeLabel = this.i18n.t(removeLabelKey);
    const options: Array<{ value: ReportDecision; label: string; hint: string }> = [
      { value: 'dismiss', label: this.i18n.t('reports.decisions.dismiss'), hint: this.i18n.t('reports.decisions.dismissHint') },
      { value: 'warn', label: this.i18n.t('reports.decisions.warn'), hint: this.i18n.t('reports.decisions.warnHint') },
      { value: 'hide', label: hideLabel, hint: this.i18n.t(targetType === 'channel' ? 'reports.decisions.hideChannelHint' : 'reports.decisions.hideHint') },
      { value: 'remove', label: removeLabel, hint: this.i18n.t(targetType === 'channel' ? 'reports.decisions.removeChannelHint' : 'reports.decisions.removeHint') },
      { value: 'escalate', label: this.i18n.t('reports.decisions.escalate'), hint: this.i18n.t('reports.decisions.escalateHint') }
    ];
    if (targetType === 'video') {
      options.splice(2, 0,
        { value: 'age_restrict', label: this.i18n.t('reports.decisions.ageRestrict'), hint: this.i18n.t('reports.decisions.ageRestrictHint') },
        { value: 'recommendation_restricted', label: this.i18n.t('reports.decisions.recommendationRestricted'), hint: this.i18n.t('reports.decisions.recommendationRestrictedHint') });
    }
    if (targetType === 'video' || targetType === 'channel') {
      const insertAt = Math.max(2, options.length - 1);
      if (this.canManageStrikes()) options.splice(insertAt, 0, { value: 'upload_restriction', label: this.i18n.t('reports.decisions.uploadRestriction'), hint: this.i18n.t('reports.decisions.uploadRestrictionHint') });
      if (this.canManageStrikes()) options.splice(insertAt, 0, { value: 'strike', label: this.i18n.t('reports.decisions.strike'), hint: this.i18n.t('reports.decisions.strikeHint') });
      if (this.canLockChannels()) options.splice(insertAt, 0, { value: 'lock_channel', label: this.i18n.t('reports.decisions.lockChannel'), hint: this.i18n.t('reports.decisions.lockChannelHint') });
    }
    return options;
  });
  readonly selectedDecisionHint = computed(() => this.availableDecisions().find(option => option.value === this.decision())?.hint ?? '');
  readonly selectedDecisionAvailable = computed(() => this.availableDecisions().some(option => option.value === this.decision()));
  readonly selectedReportIds = computed(() => Object.keys(this.selectedReports()).filter(id => this.selectedReports()[id]));
  readonly filteredCases = computed(() => {
    const search = this.searchQuery().trim().toLowerCase();
    return this.cases().filter(item => {
      const typeMatches = this.selectedTargetType() === 'ALL' || item.targetType === this.selectedTargetType();
      const text = [item.targetTitle, item.targetChannelName, item.targetChannelHandle,
        ...item.violationCounts.flatMap(v => [v.code, v.name])].filter(Boolean).join(' ').toLowerCase();
      return typeMatches && (!search || text.includes(search));
    });
  });
  readonly allClassified = computed(() => {
    const details = this.activeCase()?.reports ?? [];
    return details.length > 0 && details.every(report => report.disposition === 'accepted' || report.disposition === 'rejected');
  });
  readonly classifiedCount = computed(() => {
    const details = this.activeCase()?.reports ?? [];
    return details.filter(report => report.disposition === 'accepted' || report.disposition === 'rejected').length;
  });
  readonly unclassifiedCount = computed(() => Math.max(0, (this.activeCase()?.reports.length ?? 0) - this.classifiedCount()));
  readonly isCaseOwner = computed(() => this.activeCase()?.case.reviewerId === this.auth.user()?.userId);

  ngOnInit(): void { this.loadData(); }

  loadData(): void {
    this.loading.set(true);
    this.error.set(null);
    this.moderation.getReportCases(this.selectedTargetType(), this.selectedStatus(), 1, 100).subscribe({
      next: result => { this.cases.set(result.items ?? []); this.total.set(result.total ?? 0); this.loading.set(false); },
      error: err => { this.error.set(err?.error?.message || this.i18n.t('reports.loadError')); this.loading.set(false); }
    });
  }

  setStatus(status: QueueStatus): void { this.selectedStatus.set(status); this.loadData(); }
  setTargetType(value: 'ALL' | 'video' | 'comment' | 'channel'): void { this.selectedTargetType.set(value); this.loadData(); }
  targetHref(item: ReportCaseSummary): string { return item.targetUrl ? `http://localhost:4200${item.targetUrl}` : '#'; }
  trackReport(_: number, report: ReportCaseReportDetail): string { return report.reportId; }

  openCase(item: ReportCaseSummary): void {
    this.error.set(null);
    this.moderation.getReportCase(item.caseId).subscribe({
      next: value => {
        this.activeCase.set(value);
        this.selectedReports.set({});
        this.dispositionReason.set('');
        this.decision.set('dismiss');
        this.decisionReason.set('');
        this.policyCode.set(value.reports.find(report => report.violationTypeCode)?.violationTypeCode ?? '');
      },
      error: err => this.error.set(err?.error?.message || this.i18n.t('reports.detailError'))
    });
  }

  closeCase(): void { if (!this.submitting()) this.activeCase.set(null); }
  toggleReport(reportId: string, checked: boolean): void { this.selectedReports.update(current => ({ ...current, [reportId]: checked })); }

  claim(item: ReportCaseSummary): void {
    if (!this.canClaim()) return;
    this.submitting.set(true);
    this.moderation.claimReportCase(item.caseId).subscribe({
      next: () => { this.submitting.set(false); this.successMessage.set(this.i18n.t('reports.claimSuccess')); this.loadData(); if (this.activeCase()?.case.caseId === item.caseId) this.openCase(item); },
      error: err => { this.submitting.set(false); this.error.set(err?.error?.message || this.i18n.t('reports.claimError')); }
    });
  }

  release(item: ReportCaseSummary): void {
    if (!this.canClaim()) return;
    this.submitting.set(true);
    this.moderation.releaseReportCase(item.caseId).subscribe({
      next: () => { this.submitting.set(false); this.successMessage.set(this.i18n.t('reports.returnSuccess')); this.loadData(); this.closeCase(); },
      error: err => { this.submitting.set(false); this.error.set(err?.error?.message || this.i18n.t('reports.returnError')); }
    });
  }

  classify(disposition: 'accepted' | 'rejected'): void {
    const current = this.activeCase();
    const reportIds = this.selectedReportIds();
    if (!current || !this.canResolve() || !this.isCaseOwner() || !reportIds.length || this.dispositionReason().trim().length < 3) return;
    this.submitting.set(true);
    this.moderation.updateReportDispositions(current.case.caseId, { reportIds, disposition, reason: this.dispositionReason().trim() }).subscribe({
      next: () => {
        this.submitting.set(false);
        this.successMessage.set(this.i18n.format('reports.classifySuccess', { count: reportIds.length }));
        this.openCase(current.case);
        this.loadData();
      },
      error: err => { this.submitting.set(false); this.error.set(err?.error?.message || this.i18n.t('reports.classifyError')); }
    });
  }

  resolveCase(): void {
    const current = this.activeCase();
    if (!current || !this.canResolve() || !this.isCaseOwner() || !this.allClassified() || this.decisionReason().trim().length < 3) return;
    if (!this.availableDecisions().some(option => option.value === this.decision())) return;
    this.submitting.set(true);
    this.moderation.resolveReportCase(current.case.caseId, {
      decision: this.decision(), reason: this.decisionReason().trim(),
      internalNote: this.internalNote().trim() || undefined, policyCode: this.policyCode().trim() || undefined,
      restrictionDays: this.decision() === 'upload_restriction' ? this.restrictionDays() : undefined
    }).subscribe({
      next: result => {
        this.submitting.set(false);
        this.successMessage.set(result.message || this.i18n.t('reports.closedSuccess'));
        this.activeCase.set(null);
        this.loadData();
      },
      error: err => { this.submitting.set(false); this.error.set(err?.error?.message || this.i18n.t('reports.closeError')); }
    });
  }

  targetTypeLabel(targetType: string): string {
    const key = targetType === 'video' ? 'moderation.colVideo'
      : targetType === 'channel' ? 'nav.channels'
        : targetType === 'comment' ? 'reports.comment' : '';
    return key ? this.i18n.t(key) : targetType;
  }

  statusLabel(status: string): string {
    const keys: Record<string, string> = {
      pending: 'reports.pending',
      reviewing: 'reports.statusReviewing',
      escalated: 'reports.statusEscalated',
      resolved: 'reports.statusResolved',
    };
    return keys[status] ? this.i18n.t(keys[status]) : status;
  }

  dateLocale(): string {
    return this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US';
  }
}
