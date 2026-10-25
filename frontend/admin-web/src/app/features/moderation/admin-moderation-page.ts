import { FeedbackService } from '@dalitu/ui/feedback.service';
import { ResultNoticeComponent } from '@dalitu/ui/result-notice.component';
import { ReviewerLeaseService } from './reviewer-lease.service';
import { Component, DestroyRef, ElementRef, OnInit, ViewChild, afterRenderEffect, viewChild, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { catchError, forkJoin, map, of, TimeoutError } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';
import {
  AdminModerationService,
  ModerationDecision,
  ModerationQueueItem,
  PolicyItem,
  ResolveModerationRequest
} from './admin-moderation.service';

@Component({
  selector: 'app-admin-moderation-page',
  standalone: true,
  imports: [ResultNoticeComponent, CommonModule, FormsModule, RouterLink, TranslatePipe],
  templateUrl: './admin-moderation-page.html',
  styleUrl: './admin-moderation-page.scss'
})
export class AdminModerationPage implements OnInit {
  private readonly feedback = inject(FeedbackService);
  readonly lease = inject(ReviewerLeaseService);
  private readonly moderationService = inject(AdminModerationService);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);

  readonly loading = signal(true);
  readonly error = signal<string | null>(null);
  readonly successMessage = signal<string | null>(null);
  readonly queue = signal<ModerationQueueItem[]>([]);
  readonly selectedCaseIds = signal<string[]>([]);
  readonly policies = signal<PolicyItem[]>([]);

  readonly selectedStatus = signal<'ALL' | 'pending' | 'reviewing' | 'processed' | 'escalated'>('pending');
  readonly selectedRisk = signal<'ALL' | 'high' | 'low'>('ALL');
  readonly selectedCategory = signal('ALL');
  readonly selectedDuration = signal('ALL');
  readonly searchQuery = signal('');

  // Workspace / Review modal state
  readonly activeCase = signal<ModerationQueueItem | null>(null);
  readonly isReviewModalOpen = signal(false);
  readonly isTheaterMode = signal(false);
  readonly submitting = signal(false);
  readonly quickReview = signal(false);
  readonly reviewTabs = signal<ModerationQueueItem[]>([]);
  readonly reviewError = signal('');
  readonly reviewMessage = signal('');
  readonly selectedDecision = signal<ModerationDecision | null>(null);
  readonly activeTabIndex = computed(() => this.reviewTabs().findIndex(item => item.moderationCaseId === this.activeCase()?.moderationCaseId));
  readonly canDecideActive = computed(() => {
    const item = this.activeCase();
    return !!item && this.isClaimedByMe(item);
  });
  readonly selectedReviewable = computed(() => this.visibleSelected().filter(item => this.canReview() && this.canSelectForBatch(item)));
  @ViewChild('reviewPlayer') private reviewPlayer?: ElementRef<HTMLVideoElement>;
  private readonly reviewDrafts = new Map<string, { policy: string; note: string; reason: string; decision: ModerationDecision | null }>();
  private reviewReturnFocus: HTMLElement | null = null;
  private readonly reviewDialog = viewChild<ElementRef<HTMLDialogElement>>('reviewDialog');
  private reviewPreviousOverflow: string | null = null;

  readonly selectedPolicyCode = signal<string>('');
  readonly internalNote = signal<string>('');
  readonly actionReason = signal<string>('');

  resetFilters(): void {
    this.searchQuery.set(''); this.selectedRisk.set('ALL');
    this.selectedCategory.set('ALL'); this.selectedDuration.set('ALL');
  }

  readonly filteredQueue = computed(() => {
    let items = this.queue();
    const status = this.selectedStatus();
    const risk = this.selectedRisk();
    const category = this.selectedCategory();
    const duration = this.selectedDuration();
    const query = this.searchQuery().trim().toLowerCase();

    if (status === 'processed') items = items.filter(x => x.status === 'approved' || x.status === 'rejected' || x.status === 'resolved');
    else if (status === 'pending') items = items.filter(x => x.status === 'pending' || this.lease.expired(x));
    else if (status === 'reviewing') items = items.filter(x => this.lease.active(x));
    else if (status !== 'ALL') items = items.filter(x => x.status === status);
    if (risk !== 'ALL') {
      items = items.filter(x => x.riskLevel === risk);
    }
    if (category !== 'ALL') items = items.filter(x => (x.categoryName || this.i18n.t('moderationPage.noCategory')) === category);
    if (duration !== 'ALL') {
      items = items.filter(x => duration === 'short' ? x.duration < 300 : duration === 'medium' ? x.duration >= 300 && x.duration <= 900 : x.duration > 900);
    }
    if (query) {
      items = items.filter(x =>
        x.title.toLowerCase().includes(query) ||
        x.channelName.toLowerCase().includes(query)
      );
    }
    return [...items].sort((left, right) => Date.parse(left.submittedAt) - Date.parse(right.submittedAt));
  });

  readonly stats = computed(() => {
    const all = this.queue();
    const active = all.filter(item => !this.isProcessed(item));
    return {
      total: active.length,
      pending: active.filter(x => x.status === 'pending' || this.lease.expired(x)).length,
      reviewing: active.filter(x => this.lease.active(x)).length,
      processed: all.filter(x => this.isProcessed(x)).length,
      escalated: active.filter(x => x.status === 'escalated').length,
      highRisk: active.filter(x => x.riskLevel === 'high').length
    };
  });

  readonly categories = computed(() => [...new Set(this.queue().map(item => item.categoryName || this.i18n.t('moderationPage.noCategory')))].sort((a, b) => a.localeCompare(b, this.i18n.currentLang())));
  readonly visibleSelected = computed(() => this.filteredQueue().filter(item => this.isSelected(item) && this.canSelectForBatch(item)));
  readonly selectedClaimable = computed(() => this.visibleSelected().filter(item => item.status === 'pending' || this.lease.expired(item)));
  readonly selectedReleasable = computed(() => this.visibleSelected().filter(item => item.status === 'reviewing' && this.isClaimedByMe(item)));
  readonly visibleSelectionPartial = computed(() => this.filteredQueue().some(item => this.canSelectForBatch(item) && this.isSelected(item)) && !this.visibleSelectionComplete());

  constructor() {
    afterRenderEffect(() => {
      const dialog = this.reviewDialog()?.nativeElement;
      if (dialog && !dialog.open) {
        this.reviewPreviousOverflow = document.body.style.overflow;
        document.body.style.overflow = 'hidden';
        dialog.showModal();
        dialog.querySelector<HTMLElement>('[role=tab][aria-selected=true], .close-button')?.focus({ preventScroll: true });
      } else if (!dialog) this.restoreReviewScroll();
    });
    inject(DestroyRef).onDestroy(() => {
      this.reviewPlayer?.nativeElement.pause();
      this.restoreReviewScroll();
    });
  }

  private restoreReviewScroll(): void {
    if (this.reviewPreviousOverflow === null) return;
    document.body.style.overflow = this.reviewPreviousOverflow;
    this.reviewPreviousOverflow = null;
  }

  ngOnInit(): void {
    this.loadData();
  }

  loadData(): void {
    this.loading.set(true);
    this.error.set(null);

    forkJoin({
      active: this.moderationService.getQueue(undefined, undefined, 1, 100),
      processed: this.moderationService.getQueue('processed', undefined, 1, 100),
      policies: this.moderationService.getPolicies().pipe(catchError(() => of([] as PolicyItem[]))),
    }).subscribe({
      next: ({ active, processed, policies }) => {
        this.queue.set([...active, ...processed]);
        const availableIds = new Set([...active, ...processed].map(item => item.moderationCaseId));
        this.selectedCaseIds.update(ids => ids.filter(id => availableIds.has(id)));
        this.policies.set(policies);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err?.error?.detail || this.i18n.t('common.error'));
        this.loading.set(false);
      }
    });
  }

  claimCase(item: ModerationQueueItem): void {
    if (this.loading() || this.submitting() || !this.canClaim() || !this.canReview()) return;
    this.loading.set(true);
    this.moderationService.claim(item.moderationCaseId).subscribe({
      next: (res) => {
        const updated = { ...item, ...res, status: 'reviewing' as const, reviewerId: this.auth.user()!.userId, reviewerName: this.auth.user()!.displayName };
        this.queue.update(items => items.map(value => value.moderationCaseId === item.moderationCaseId ? updated : value));
        this.loading.set(false); this.openReviewModal(updated);
      },
      error: (err) => {
        this.error.set(err?.error?.detail || this.i18n.t('common.error'));
        this.loading.set(false);
      }
    });
  }

  releaseCase(item: ModerationQueueItem): void {
    this.loading.set(true);
    this.moderationService.release(item.moderationCaseId, item.claimId).subscribe({
      next: (res) => {
        this.showMessage(res.message || this.i18n.t('moderation.releaseSuccess'));
        this.loadData();
      },
      error: (err) => {
        this.error.set(err?.error?.detail || this.i18n.t('common.error'));
        this.loading.set(false);
      }
    });
  }

  canSelectForBatch(item: ModerationQueueItem): boolean {
    if (!this.canClaim() || this.isProcessed(item)) return false;
    return (item.status === 'pending' || this.lease.expired(item)) || (item.status === 'reviewing' && this.isClaimedByMe(item));
  }

  isSelected(item: ModerationQueueItem): boolean { return this.selectedCaseIds().includes(item.moderationCaseId); }

  toggleCaseSelection(item: ModerationQueueItem, checked: boolean): void {
    if (!this.canSelectForBatch(item)) return;
    this.selectedCaseIds.update(ids => checked
      ? [...new Set([...ids, item.moderationCaseId])]
      : ids.filter(id => id !== item.moderationCaseId));
  }

  toggleVisibleSelection(checked: boolean): void {
    const selectable = this.filteredQueue().filter(item => this.canSelectForBatch(item)).map(item => item.moderationCaseId);
    this.selectedCaseIds.update(ids => checked
      ? [...new Set([...ids, ...selectable])]
      : ids.filter(id => !selectable.includes(id)));
  }

  visibleSelectionComplete(): boolean {
    const selectable = this.filteredQueue().filter(item => this.canSelectForBatch(item));
    return selectable.length > 0 && selectable.every(item => this.isSelected(item));
  }

  bulkClaimSelected(): void { this.applyBulkSelection('claim'); }
  bulkReleaseSelected(): void { this.applyBulkSelection('release'); }

  canApprove(): boolean { return this.auth.hasPermission('moderation.approve'); }
  canReject(): boolean { return this.auth.hasPermission('moderation.reject'); }

  readonly bulkResult = signal<{ succeeded: number; failed: Array<{ id: string; title: string; reason: string }> } | null>(null);
  readonly bulkDetails = computed(() => this.bulkResult()?.failed.map(item => ({ label: item.title, message: item.reason })) ?? []);
  readonly bulkTone = computed(() => !this.bulkResult()?.failed.length ? 'success' : this.bulkResult()?.succeeded ? 'warning' : 'error');

  private async applyBulkSelection(action: 'claim' | 'release'): Promise<void> {
    if (this.loading() || !this.canClaim()) return;
    const selected = new Set(this.selectedCaseIds());
    const eligible = this.filteredQueue().filter(item => selected.has(item.moderationCaseId)
      && (action === 'claim' ? (item.status === 'pending' || this.lease.expired(item)) : item.status === 'reviewing' && this.isClaimedByMe(item)));
    if (!eligible.length) return;
    const label = this.i18n.t(action === 'claim' ? 'moderationPage.bulkClaimLabel' : 'moderationPage.bulkReleaseLabel');
    if (!(await this.feedback.confirm(this.i18n.format('moderationPage.bulkConfirm', { action: label, count: eligible.length })))) return;
    this.loading.set(true);
    this.bulkResult.set(null);
    const requests = eligible.map(item => (action === 'claim'
      ? this.moderationService.claim(item.moderationCaseId)
      : this.moderationService.release(item.moderationCaseId, item.claimId)).pipe(
        map(() => ({ item, success: true, reason: '' })),
        catchError(err => of({ item, success: false,
          reason: err?.error?.detail || this.i18n.format('moderationPage.bulkError', { action: label }) }))
      ));
    forkJoin(requests).subscribe(results => {
      const succeeded = new Set(results.filter(result => result.success).map(result => result.item.moderationCaseId));
      this.selectedCaseIds.update(ids => ids.filter(id => !succeeded.has(id)));
      this.bulkResult.set({ succeeded: succeeded.size,
        failed: results.filter(result => !result.success).map(result => ({
          id: result.item.moderationCaseId, title: result.item.title, reason: result.reason })) });
      this.loadData();
    });
  }

  openReviewModal(item: ModerationQueueItem): void {
    if (this.loading() || this.submitting()) return;
    if (this.canClaim() && this.canReview() && (item.status === 'pending' || item.status === 'escalated' || this.lease.expired(item))) {
      this.claimCase(item); return;
    }
    this.quickReview.set(false);
    this.reviewTabs.set([item]);
    this.openReviewSession(item);
  }

  openQuickReview(): void {
    if (this.loading() || this.submitting()) return;
    const items = this.selectedReviewable();
    if (!items.length) return;
    this.loading.set(true); this.bulkResult.set(null);
    forkJoin(items.map(item => this.isClaimedByMe(item) ? of({ item, success: true, reason: '' })
      : this.moderationService.claim(item.moderationCaseId).pipe(
        map(lease => ({ item: { ...item, ...lease, status: 'reviewing' as const, reviewerId: this.auth.user()!.userId, reviewerName: this.auth.user()!.displayName }, success: true, reason: '' })),
        catchError(err => of({ item, success: false, reason: err?.error?.detail || this.i18n.t('workflow.unavailable') }))
      ))).subscribe(results => {
      this.loading.set(false);
      const available = results.filter(result => result.success).map(result => result.item);
      const failed = results.filter(result => !result.success).map(result => ({ id: result.item.moderationCaseId, title: result.item.title, reason: result.reason }));
      if (failed.length) this.bulkResult.set({ succeeded: available.length, failed });
      if (!available.length) return;
      const byId = new Map(available.map(item => [item.moderationCaseId, item]));
      this.queue.update(queue => queue.map(item => byId.get(item.moderationCaseId) ?? item));
      this.quickReview.set(true); this.reviewTabs.set(available); this.openReviewSession(available[0]);
    });
  }

  private openReviewSession(item: ModerationQueueItem): void {
    this.reviewReturnFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    this.reviewMessage.set('');
    this.activateReviewTab(item);
    this.isReviewModalOpen.set(true);
  }

  switchReviewTab(item: ModerationQueueItem): void {
    if (this.submitting() || item.moderationCaseId === this.activeCase()?.moderationCaseId) return;
    this.saveReviewDraft();
    this.reviewMessage.set('');
    this.activateReviewTab(item);
  }

  private activateReviewTab(item: ModerationQueueItem): void {
    this.reviewPlayer?.nativeElement.pause();
    this.activeCase.set(item);
    const draft = this.reviewDrafts.get(item.moderationCaseId);
    this.selectedPolicyCode.set(draft?.policy ?? '');
    this.internalNote.set(draft?.note ?? item.note ?? '');
    this.actionReason.set(draft?.reason ?? '');
    this.selectedDecision.set(draft?.decision ?? null);
    this.reviewError.set('');
  }

  private saveReviewDraft(): void {
    const item = this.activeCase();
    if (item) this.reviewDrafts.set(item.moderationCaseId, {
      policy: this.selectedPolicyCode(), note: this.internalNote(), reason: this.actionReason(), decision: this.selectedDecision(),
    });
  }

  removeReviewTab(item: ModerationQueueItem): void {
    if (this.submitting()) return;
    this.saveReviewDraft();
    const index = this.reviewTabs().findIndex(tab => tab.moderationCaseId === item.moderationCaseId);
    const remaining = this.reviewTabs().filter(tab => tab.moderationCaseId !== item.moderationCaseId);
    this.reviewTabs.set(remaining);
    if (!remaining.length) { this.closeReviewModal(); return; }
    if (item.moderationCaseId === this.activeCase()?.moderationCaseId) this.activateReviewTab(remaining[Math.min(index, remaining.length - 1)]);
  }

  moveReviewTab(direction: -1 | 1): void {
    const item = this.reviewTabs()[this.activeTabIndex() + direction];
    if (item) this.switchReviewTab(item);
  }

  onReviewTabKey(event: KeyboardEvent, index: number): void {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key) || this.submitting()) return;
    event.preventDefault();
    const last = this.reviewTabs().length - 1;
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? last : (index + (event.key === 'ArrowRight' ? 1 : -1) + last + 1) % (last + 1);
    this.switchReviewTab(this.reviewTabs()[next]);
    document.getElementById('review-tab-' + this.reviewTabs()[next].moderationCaseId)?.focus();
  }

  chooseDecision(decision: ModerationDecision): void {
    if (this.quickReview()) { this.selectedDecision.set(decision); this.reviewError.set(''); this.reviewMessage.set(''); }
    else this.submitDecision(decision);
  }

  submitQuickDecision(): void {
    const decision = this.selectedDecision();
    if (decision) this.submitDecision(decision);
  }

  closeReviewModal(): void {
    if (this.submitting()) return;
    this.saveReviewDraft();
    this.reviewPlayer?.nativeElement.pause();
    this.reviewDialog()?.nativeElement.close();
    this.restoreReviewScroll();
    this.isReviewModalOpen.set(false);
    this.isTheaterMode.set(false);
    this.activeCase.set(null);
    if (this.reviewReturnFocus?.isConnected) this.reviewReturnFocus.focus({ preventScroll: true });
  }

  toggleTheaterMode(): void {
    this.isTheaterMode.update(v => !v);
  }

  getPolicyName(policy: { code: string; name?: string } | null | undefined): string {
    if (!policy) return '';
    const key = `policy.${policy.code}.name`;
    const val = this.i18n.t(key);
    return val !== key ? val : (policy.name || policy.code);
  }

  submitDecision(decision: ModerationDecision): void {
    const currentCase = this.activeCase();
    if (!currentCase || this.submitting()) return;
    if (!this.isClaimedByMe(currentCase)) {
      this.reviewError.set(this.i18n.t('moderationPage.reviewLeaseRequired'));
      return;
    }
    if ((['approve', 'age_restricted', 'recommendation_restricted'].includes(decision) && !this.canApprove())
      || (decision === 'reject' && !this.canReject()) || (decision === 'escalate' && !this.canReview())) return;

    if (decision !== 'approve' && !this.selectedPolicyCode() && decision !== 'escalate') {
      this.reviewError.set(this.i18n.t('moderation.policyRequired'));
      return;
    }

    const selectedPolicy = this.policies().find(p => p.code === this.selectedPolicyCode());

    const req: ResolveModerationRequest = {
      claimId: currentCase.claimId,
      decision,
      policyCode: this.selectedPolicyCode() || undefined,
      reason: this.actionReason().trim() || this.getPolicyName(selectedPolicy) || undefined,
      internalNote: this.internalNote().trim() || undefined
    };

    this.submitting.set(true);
    this.reviewError.set('');
    this.moderationService.resolve(currentCase.moderationCaseId, req).subscribe({
      next: (res) => {
        this.submitting.set(false);
        this.reviewDrafts.delete(currentCase.moderationCaseId);
        this.selectedCaseIds.update(ids => ids.filter(id => id !== currentCase.moderationCaseId));
        const remaining = this.reviewTabs().filter(item => item.moderationCaseId !== currentCase.moderationCaseId);
        const nextIndex = Math.min(this.activeTabIndex(), remaining.length - 1);
        const message = res.message || this.i18n.t('moderation.resolveSuccess');
        if (this.quickReview() && remaining.length) {
          this.reviewTabs.set(remaining);
          this.activateReviewTab(remaining[Math.max(0, nextIndex)]);
          this.reviewMessage.set(`${currentCase.title}: ${message}`);
        } else {
          // Clear the active item before closing so the saved draft stays deleted.
          this.activeCase.set(null);
          this.closeReviewModal();
          this.showMessage(message);
        }
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.reviewError.set(err instanceof TimeoutError || err?.status === 0
          ? this.i18n.t('moderationPage.decisionUnconfirmed')
          : err?.error?.detail || this.i18n.t('common.error'));
      }
    });
  }

  onReviewEscape(event: Event): void {
    event.preventDefault();
    this.closeReviewModal();
  }

  onReviewBackdrop(event: MouseEvent): void {
    const dialog = this.reviewDialog()?.nativeElement;
    if (!dialog || event.target !== dialog) return;
    const rect = dialog.getBoundingClientRect();
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) this.closeReviewModal();
  }

  isClaimedByMe(item: ModerationQueueItem): boolean {
    const myId = this.auth.user()?.userId;
    return !!myId && item.reviewerId === myId && this.lease.active(item);
  }

  canClaim(): boolean {
    return this.auth.hasPermission('moderation.claim');
  }

  canReview(): boolean {
    return this.auth.hasPermission('moderation.review');
  }

  getStatusLabel(status: string): string {
    switch (status?.toLowerCase()) {
      case 'pending': return this.i18n.t('moderation.statusPending');
      case 'reviewing': return this.i18n.t('moderation.statusReviewing');
      case 'escalated': return this.i18n.t('moderation.statusEscalated');
      case 'approved':
      case 'rejected':
      case 'resolved': return this.i18n.t('moderationPage.statusProcessed');
      default: return status;
    }
  }

  isProcessed(item: ModerationQueueItem): boolean {
    return item.status === 'approved' || item.status === 'rejected' || item.status === 'resolved';
  }

  waitingTime(submittedAt: string): string {
    const minutes = Math.max(0, Math.floor((Date.now() - new Date(submittedAt).getTime()) / 60_000));
    if (minutes < 60) return this.i18n.format('moderationPage.minutes', { count: minutes });
    const hours = Math.floor(minutes / 60);
    const remainder = minutes % 60 ? this.i18n.format('moderationPage.minuteRemainder', { count: minutes % 60 }) : '';
    return this.i18n.format('moderationPage.hoursMinutes', { hours, remainder });
  }

  formatDate(value: string): string {
    const locale = this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US';
    return new Intl.DateTimeFormat(locale, { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value));
  }


  getRiskLabel(risk: string): string {
    switch (risk?.toLowerCase()) {
      case 'high':
      case 'critical':
        return this.i18n.t('moderation.riskHigh');
      case 'low':
      case 'normal':
        return this.i18n.t('moderation.riskLow');
      default: return risk;
    }
  }

  formatDuration(seconds: number): string {
    if (!seconds || seconds <= 0) return '00:00';
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }

  claimFirstPending(): void {
    const item = this.queue().find(candidate => candidate.status === 'pending' || this.lease.expired(candidate));
    if (item) this.openReviewModal(item);
  }

  private showMessage(msg: string): void {
    this.successMessage.set(msg);
    setTimeout(() => this.successMessage.set(null), 4000);
  }
}
