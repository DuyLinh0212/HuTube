import { ResultNoticeComponent } from '@dalitu/ui/result-notice.component';
import { ReviewerLeaseService } from './reviewer-lease.service';
import { Component, DestroyRef, ElementRef, OnInit, afterRenderEffect, computed, inject, signal, viewChild } from '@angular/core';
import { EMPTY, expand, reduce } from 'rxjs';
import { RuntimeConfig } from '../../core/runtime-config';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { AdminModerationService, ReportCaseDetail, ReportCaseReportDetail, ReportCaseSummary, PolicyItem } from './admin-moderation.service';
import { TranslatePipe } from '../../core/translate.pipe';

type QueueStatus = 'ALL' | 'pending' | 'reviewing' | 'resolved' | 'escalated';
type ReportDecision = 'dismiss' | 'warn' | 'age_restrict' | 'recommendation_restricted' | 'hide' | 'remove' | 'upload_restriction' | 'strike' | 'lock_channel' | 'escalate';
interface ViolationTypeOption { value: string; label: string; }

@Component({
  selector: 'app-admin-reports-page',
  standalone: true,
  imports: [ResultNoticeComponent, CommonModule, FormsModule, TranslatePipe],
  templateUrl: './admin-reports-page.html',
  styleUrl: './admin-reports-page.scss'
})
export class AdminReportsPage implements OnInit {
  readonly lease = inject(ReviewerLeaseService);
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
  readonly allStatusFilter = signal<QueueStatus>('ALL');
  readonly selectedViolationType = signal('ALL');
  readonly violationTypeSearch = signal('');
  readonly violationTypePage = signal(1);
  readonly processedFrom = signal('');
  readonly processedTo = signal('');
  readonly currentPage = signal(1);
  readonly pageSize = 20;
  readonly searchQuery = signal('');
  readonly activeCase = signal<ReportCaseDetail | null>(null);
  readonly selectedReports = signal<Record<string, boolean>>({});
  readonly dispositionReason = signal('');
  readonly decision = signal<ReportDecision | ''>('');
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
  readonly selectedReportIds = computed(() => (this.activeCase()?.reports ?? []).filter(report => this.selectedReports()[report.reportId]).map(report => report.reportId));
  readonly violationTypes = computed<ViolationTypeOption[]>(() => {
    const options = new Map<string, string>();
    for (const item of this.cases()) {
      for (const violation of item.violationCounts ?? []) {
        const value = violation.code || '__unclassified__';
        const label = violation.name || violation.code || this.i18n.t('reports.other');
        if (!options.has(value)) options.set(value, label);
      }
    }
    return [...options].map(([value, label]) => ({ value, label }))
      .sort((left, right) => left.label.localeCompare(right.label, this.i18n.currentLang()));
  });
  readonly matchingViolationTypes = computed(() => {
    const query = this.violationTypeSearch().trim().toLocaleLowerCase(this.i18n.currentLang());
    return this.violationTypes().filter(option => !query || `${option.label} ${option.value}`.toLocaleLowerCase(this.i18n.currentLang()).includes(query));
  });
  readonly violationTypePageSize = 8;
  readonly violationTypePageCount = computed(() => Math.max(1, Math.ceil(this.matchingViolationTypes().length / this.violationTypePageSize)));
  readonly safeViolationTypePage = computed(() => Math.min(this.violationTypePage(), this.violationTypePageCount()));
  readonly pagedViolationTypes = computed(() => {
    const start = (this.safeViolationTypePage() - 1) * this.violationTypePageSize;
    return this.matchingViolationTypes().slice(start, start + this.violationTypePageSize);
  });
  readonly selectedViolationTypeLabel = computed(() => this.selectedViolationType() === 'ALL'
    ? this.i18n.t('reports.allViolations')
    : this.violationTypes().find(option => option.value === this.selectedViolationType())?.label ?? this.i18n.t('reports.other'));
  readonly filteredCases = computed(() => {
    const search = this.searchQuery().trim().toLowerCase();
    const allTabActive = this.selectedStatus() === 'ALL';
    const status = allTabActive ? this.allStatusFilter() : this.selectedStatus();
    const violationType = allTabActive ? this.selectedViolationType() : 'ALL';
    const from = allTabActive ? this.processedFrom() : '';
    const to = allTabActive ? this.processedTo() : '';
    return this.cases().filter(item => {
      const typeMatches = this.selectedTargetType() === 'ALL' || item.targetType === this.selectedTargetType();
      const statusMatches = status === 'ALL' || (status === 'pending' ? item.status === 'pending' || this.lease.expired(item) : status === 'reviewing' ? this.lease.active(item) : item.status === status);
      const violationMatches = violationType === 'ALL' || item.violationCounts.some(violation =>
        violationType === '__unclassified__' ? !violation.code : violation.code === violationType);
      const resolvedAt = item.resolvedAt || (item.status === 'resolved' || item.status === 'escalated' ? item.updatedAt : null);
      const processedDate = this.localDateKey(resolvedAt);
      const processedTimeMatches = (!from && !to) || (!!processedDate && (!from || processedDate >= from) && (!to || processedDate <= to));
      const text = [item.targetTitle, item.targetChannelName, item.targetChannelHandle,
        ...item.violationCounts.flatMap(v => [v.code, v.name])].filter(Boolean).join(' ').toLowerCase();
      return typeMatches && statusMatches && violationMatches && processedTimeMatches && (!search || text.includes(search));
    });
  });
  readonly pageCount = computed(() => Math.max(1, Math.ceil(this.filteredCases().length / this.pageSize)));
  readonly safePage = computed(() => Math.min(this.currentPage(), this.pageCount()));
  readonly paginatedCases = computed(() => {
    const start = (this.safePage() - 1) * this.pageSize;
    return this.filteredCases().slice(start, start + this.pageSize);
  });
  readonly pageRangeStart = computed(() => this.filteredCases().length ? (this.safePage() - 1) * this.pageSize + 1 : 0);
  readonly pageRangeEnd = computed(() => Math.min(this.safePage() * this.pageSize, this.filteredCases().length));
  readonly allClassified = computed(() => {
    const details = this.activeCase()?.reports ?? [];
    return details.length > 0 && details.every(report => report.disposition === 'accepted' || report.disposition === 'rejected');
  });
  readonly classifiedCount = computed(() => {
    const details = this.activeCase()?.reports ?? [];
    return details.filter(report => report.disposition === 'accepted' || report.disposition === 'rejected').length;
  });
  readonly unclassifiedCount = computed(() => Math.max(0, (this.activeCase()?.reports.length ?? 0) - this.classifiedCount()));
  readonly isCaseOwner = computed(() => !!this.activeCase() && this.activeCase()!.case.reviewerId === this.auth.user()?.userId && this.lease.active(this.activeCase()!.case));

  private readonly caseDialog = viewChild<ElementRef<HTMLDialogElement>>('caseDialog');
  private readonly decisionField = viewChild<ElementRef<HTMLSelectElement>>('decisionField');
  private previousOverflow: string | null = null;
  private caseGeneration = 0;
  private policiesLoaded = false;
  readonly detailLoading = signal(false);
  readonly policyOptions = signal<PolicyItem[]>([]);
  readonly policiesLoading = signal(false);
  readonly policiesError = signal(false);
  readonly canEditCase = computed(() => this.canResolve() && this.isCaseOwner() && this.activeCase()?.case.status === 'reviewing');
  readonly canClassify = computed(() => this.canEditCase() && !this.submitting() && !this.detailLoading()
    && this.selectedReportIds().length > 0 && this.dispositionReason().trim().length >= 3);
  readonly canCloseCase = computed(() => this.canEditCase() && !this.submitting() && !this.detailLoading()
    && this.allClassified() && this.selectedDecisionAvailable() && this.decisionReason().trim().length >= 3
    && (this.decision() !== 'upload_restriction' || Number.isInteger(this.restrictionDays()) && this.restrictionDays() >= 1 && this.restrictionDays() <= 30));
  readonly reviewStage = signal<'classification' | 'resolution'>('classification');
  readonly focusedReportId = signal('');
  readonly reportDisposition = signal<'accepted' | 'rejected' | ''>('');
  readonly focusedReport = computed(() => this.activeCase()?.reports.find(report => report.reportId === this.focusedReportId()) ?? null);
  readonly focusedReportNumber = computed(() => (this.activeCase()?.reports.findIndex(report => report.reportId === this.focusedReportId()) ?? -1) + 1);
  readonly canSaveCurrentReport = computed(() => this.canEditCase() && !this.submitting() && !this.detailLoading()
    && this.reviewStage() === 'classification' && !!this.focusedReport() && !!this.reportDisposition() && this.dispositionReason().trim().length >= 3);
  private readonly reviewHeading = viewChild<ElementRef<HTMLElement>>('reviewHeading');
  showReport(reportId: string): void {
    if (this.submitting() || this.detailLoading()) return;
    const report = this.activeCase()?.reports.find(item => item.reportId === reportId);
    if (!report) return;
    this.focusedReportId.set(reportId);
    this.reportDisposition.set(report.disposition === 'accepted' || report.disposition === 'rejected' ? report.disposition : '');
    this.dispositionReason.set(report.dispositionReason ?? '');
    this.reviewStage.set('classification');
  }
  showResolution(): void {
    if (!this.allClassified() || this.submitting() || this.detailLoading()) return;
    this.reviewStage.set('resolution');
  }
  saveCurrentReport(): void {
    const report = this.focusedReport(); const disposition = this.reportDisposition();
    if (!report || !disposition || !this.canSaveCurrentReport()) return;
    this.selectedReports.set({ [report.reportId]: true });
    this.classify(disposition);
  }

  readonly selectedDecisionLabel = computed(() => this.availableDecisions().find(option => option.value === this.decision())?.label ?? '');

  constructor() {
    afterRenderEffect(() => {
      this.reviewStage(); this.focusedReportId();
      const dialog = this.caseDialog()?.nativeElement;
      const heading = this.reviewHeading()?.nativeElement;
      if (dialog && !dialog.open) {
        this.previousOverflow = document.body.style.overflow;
        document.body.style.overflow = 'hidden'; dialog.showModal();
      }
      if (heading && dialog?.open) {
        const body = dialog.querySelector<HTMLElement>('.report-workspace-body');
        if (body) body.scrollTop = 0;
        heading.focus({ preventScroll: true });
      }
    });
    inject(DestroyRef).onDestroy(() => { this.caseGeneration++; this.restoreCaseScroll(); });
  }
  private restoreCaseScroll(): void {
    if (this.previousOverflow === null) return;
    document.body.style.overflow = this.previousOverflow; this.previousOverflow = null;
  }
  onCaseBackdrop(event: MouseEvent): void {
    const dialog = this.caseDialog()?.nativeElement;
    if (!dialog || event.target !== dialog) return;
    const rect = dialog.getBoundingClientRect();
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) this.closeCase();
  }
  scrollToStage(stage: 'classification' | 'resolution'): void {
    const dialog = this.caseDialog()?.nativeElement;
    const body = dialog?.querySelector<HTMLElement>('.report-workspace-body');
    const element = dialog?.querySelector<HTMLElement>('#report-' + stage + '-stage');
    if (!body || !element) return;
    const top = Math.max(0, body.scrollTop + element.getBoundingClientRect().top - body.getBoundingClientRect().top - 16);
    body.scrollTo({ top, behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth' });
  }
  selectUnclassified(): void {
    if (!this.canEditCase() || this.submitting() || this.detailLoading()) return;
    this.selectedReports.set(Object.fromEntries((this.activeCase()?.reports ?? [])
      .filter(report => report.disposition !== 'accepted' && report.disposition !== 'rejected').map(report => [report.reportId, true])));
  }
  loadCasePolicies(): void {
    if (this.policiesLoading()) return;
    this.policiesLoading.set(true); this.policiesError.set(false);
    this.moderation.getPolicies().subscribe({
      next: policies => { this.policyOptions.set(policies); this.policiesLoaded = true; this.policiesLoading.set(false); },
      error: () => { this.policiesLoading.set(false); this.policiesError.set(true); }
    });
  }

  private readonly config = inject(RuntimeConfig);
  private loadGeneration = 0;

  ngOnInit(): void { this.loadData(); }

  loadData(): void {
    const generation = ++this.loadGeneration;
    const type = this.selectedTargetType(), status = this.selectedStatus();
    this.loading.set(true);
    this.error.set(null);
    this.moderation.getReportCases(type, status, 1, 100).pipe(
      expand(page => page.page * page.pageSize < page.total ? this.moderation.getReportCases(type, status, page.page + 1, page.pageSize) : EMPTY),
      reduce((all, page) => ({ ...page, items: [...all.items, ...page.items] }), { items: [] as ReportCaseSummary[], total: 0, page: 0, pageSize: 100 })
    ).subscribe({
      next: result => { if (generation !== this.loadGeneration) return; this.cases.set(result.items ?? []); this.total.set(result.total ?? 0); this.loading.set(false); },
      error: err => { if (generation !== this.loadGeneration) return; this.error.set(err?.error?.message || this.i18n.t('reports.loadError')); this.loading.set(false); }
    });
  }

  resetFilters(): void {
    const reload = this.selectedTargetType() !== 'ALL';
    this.searchQuery.set(''); this.selectedTargetType.set('ALL'); this.allStatusFilter.set('ALL');
    this.selectedViolationType.set('ALL'); this.violationTypeSearch.set(''); this.violationTypePage.set(1);
    this.processedFrom.set(''); this.processedTo.set(''); this.currentPage.set(1);
    if (reload) this.loadData();
  }

  setStatus(status: QueueStatus): void {
    this.selectedStatus.set(status);
    this.allStatusFilter.set('ALL');
    this.currentPage.set(1);
    this.loadData();
  }
  setTargetType(value: 'ALL' | 'video' | 'comment' | 'channel'): void {
    this.selectedTargetType.set(value);
    this.selectedViolationType.set('ALL');
    this.currentPage.set(1);
    this.loadData();
  }
  setAllStatusFilter(value: QueueStatus): void { this.allStatusFilter.set(value); this.currentPage.set(1); }
  setViolationType(value: string): void { this.selectedViolationType.set(value); this.currentPage.set(1); }
  setViolationTypeSearch(value: string): void { this.violationTypeSearch.set(value); this.violationTypePage.set(1); }
  setViolationTypePage(page: number): void { this.violationTypePage.set(Math.max(1, Math.min(page, this.violationTypePageCount()))); }
  setSearchQuery(value: string): void { this.searchQuery.set(value); this.currentPage.set(1); }
  setProcessedFrom(value: string): void { this.processedFrom.set(value); this.currentPage.set(1); }
  setProcessedTo(value: string): void { this.processedTo.set(value); this.currentPage.set(1); }
  setPage(page: number): void { this.currentPage.set(Math.max(1, Math.min(page, this.pageCount()))); }
  selectViolationType(value: string, dropdown: HTMLDetailsElement): void {
    this.setViolationType(value);
    dropdown.open = false;
  }
  targetHref(item: ReportCaseSummary): string | null {
    if (!item.targetUrl || !this.config.userWebBaseUrl || !item.targetUrl.startsWith('/') || item.targetUrl.startsWith('//')) return null;
    const url = new URL(item.targetUrl, this.config.userWebBaseUrl);
    return url.origin === new URL(this.config.userWebBaseUrl).origin ? url.href : null;
  }
  trackReport(_: number, report: ReportCaseReportDetail): string { return report.reportId; }

  openCase(item: ReportCaseSummary, preserveDraft = false): void {
    const generation = ++this.caseGeneration;
    this.error.set(null); this.detailLoading.set(true);
    if (!preserveDraft) this.successMessage.set(null);
    if (!this.policiesLoaded) this.loadCasePolicies();
    this.moderation.getReportCase(item.caseId).subscribe({
      next: value => {
        if (generation !== this.caseGeneration) return;
        this.activeCase.set(value); this.detailLoading.set(false);
        const pending = value.reports.filter(report => report.disposition !== 'accepted' && report.disposition !== 'rejected');
        this.selectedReports.set(pending.length === 1 ? { [pending[0].reportId]: true } : {});
        this.dispositionReason.set('');
        const nextReport = pending[0] ?? value.reports[0];
        if (nextReport) this.showReport(nextReport.reportId);
        this.reviewStage.set(pending.length ? 'classification' : 'resolution');
        if (!preserveDraft) {
          this.decision.set(''); this.decisionReason.set(''); this.policyCode.set('');
          this.internalNote.set(''); this.restrictionDays.set(7);
        }

      },
      error: err => {
        if (generation !== this.caseGeneration) return;
        this.detailLoading.set(false); this.error.set(err?.error?.message || this.i18n.t('reports.detailError'));
      }
    });
  }

  closeCase(): void {
    if (this.submitting()) return;
    this.caseGeneration++; this.detailLoading.set(false); this.activeCase.set(null); this.restoreCaseScroll();
  }
  toggleReport(reportId: string, checked: boolean): void { this.selectedReports.update(current => ({ ...current, [reportId]: checked })); }

  startCase(item: ReportCaseSummary): void {
    if (this.submitting() || this.detailLoading()) return;
    if (!this.canClaim() || !this.canResolve() || !(item.status === 'pending' || this.lease.expired(item))) {
      this.openCase(item); return;
    }
    this.submitting.set(true); this.error.set(null);
    this.moderation.claimReportCase(item.caseId).subscribe({
      next: () => { this.submitting.set(false); this.openCase(item); this.loadData(); },
      error: err => { this.submitting.set(false); this.error.set(err?.error?.message || this.i18n.t('workflow.unavailable')); }
    });
  }

  release(item: ReportCaseSummary): void {
    if (!this.canClaim()) return;
    this.submitting.set(true);
    this.moderation.releaseReportCase(item.caseId, item.claimId).subscribe({
      next: () => { this.submitting.set(false); this.successMessage.set(this.i18n.t('reports.returnSuccess')); this.loadData(); this.closeCase(); },
      error: err => { this.submitting.set(false); this.error.set(err?.error?.message || this.i18n.t('reports.returnError')); }
    });
  }

  classify(disposition: 'accepted' | 'rejected'): void {
    const current = this.activeCase();
    const reportIds = this.selectedReportIds();
    if (!current || !this.canClassify()) return;
    this.submitting.set(true);
    this.moderation.updateReportDispositions(current.case.caseId, { claimId: current.case.claimId, reportIds, disposition, reason: this.dispositionReason().trim() }).subscribe({
      next: () => {
        this.submitting.set(false);
        this.successMessage.set(this.i18n.format('reports.classifySuccess', { count: reportIds.length }));
        this.openCase(current.case, true);
        this.loadData();
      },
      error: err => { this.submitting.set(false); this.error.set(err?.error?.message || this.i18n.t('reports.classifyError')); }
    });
  }

  resolveCase(): void {
    const current = this.activeCase();
    if (!current || !this.canCloseCase()) return;
    if (!this.availableDecisions().some(option => option.value === this.decision())) return;
    this.submitting.set(true);
    this.moderation.resolveReportCase(current.case.caseId, {
      claimId: current.case.claimId,
      decision: this.decision(), reason: this.decisionReason().trim(),
      internalNote: this.internalNote().trim() || undefined, policyCode: this.policyCode().trim() || undefined,
      restrictionDays: this.decision() === 'upload_restriction' ? this.restrictionDays() : undefined
    }).subscribe({
      next: result => {
        this.submitting.set(false);
        this.successMessage.set(result.message || this.i18n.t('reports.closedSuccess'));
        this.closeCase();
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

  private localDateKey(value: string | null | undefined): string {
    if (!value) return '';
    const date = new Date(value);
    if (!Number.isFinite(date.getTime())) return '';
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  dateLocale(): string {
    return this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US';
  }
}
