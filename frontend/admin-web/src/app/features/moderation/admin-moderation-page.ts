import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { catchError, forkJoin, of } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
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
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './admin-moderation-page.html',
  styleUrl: './admin-moderation-page.scss'
})
export class AdminModerationPage implements OnInit {
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

  readonly selectedPolicyCode = signal<string>('');
  readonly internalNote = signal<string>('');
  readonly actionReason = signal<string>('');

  readonly filteredQueue = computed(() => {
    let items = this.queue();
    const status = this.selectedStatus();
    const risk = this.selectedRisk();
    const category = this.selectedCategory();
    const duration = this.selectedDuration();
    const query = this.searchQuery().trim().toLowerCase();

    if (status === 'processed') items = items.filter(x => x.status === 'approved' || x.status === 'rejected' || x.status === 'resolved');
    else if (status !== 'ALL') items = items.filter(x => x.status === status);
    if (risk !== 'ALL') {
      items = items.filter(x => x.riskLevel === risk);
    }
    if (category !== 'ALL') items = items.filter(x => (x.categoryName || 'Chưa phân loại') === category);
    if (duration !== 'ALL') {
      items = items.filter(x => duration === 'short' ? x.duration < 300 : duration === 'medium' ? x.duration >= 300 && x.duration <= 900 : x.duration > 900);
    }
    if (query) {
      items = items.filter(x =>
        x.title.toLowerCase().includes(query) ||
        x.channelName.toLowerCase().includes(query)
      );
    }
    return items;
  });

  readonly stats = computed(() => {
    const all = this.queue();
    const active = all.filter(item => !this.isProcessed(item));
    return {
      total: active.length,
      pending: active.filter(x => x.status === 'pending').length,
      reviewing: active.filter(x => x.status === 'reviewing').length,
      processed: all.filter(x => this.isProcessed(x)).length,
      escalated: active.filter(x => x.status === 'escalated').length,
      highRisk: active.filter(x => x.riskLevel === 'high').length
    };
  });

  readonly categories = computed(() => [...new Set(this.queue().map(item => item.categoryName || 'Chưa phân loại'))].sort((a, b) => a.localeCompare(b, 'vi')));

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
    this.loading.set(true);
    this.moderationService.claim(item.moderationCaseId).subscribe({
      next: (res) => {
        this.showMessage(res.message || this.i18n.t('moderation.claimSuccess'));
        this.loadData();
      },
      error: (err) => {
        this.error.set(err?.error?.detail || this.i18n.t('common.error'));
        this.loading.set(false);
      }
    });
  }

  releaseCase(item: ModerationQueueItem): void {
    this.loading.set(true);
    this.moderationService.release(item.moderationCaseId).subscribe({
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
    return item.status === 'pending' || (item.status === 'reviewing' && this.isClaimedByMe(item));
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

  private applyBulkSelection(action: 'claim' | 'release'): void {
    if (!this.canClaim()) return;
    const selected = new Set(this.selectedCaseIds());
    const eligible = this.filteredQueue().filter(item => selected.has(item.moderationCaseId)
      && (action === 'claim' ? item.status === 'pending' : item.status === 'reviewing' && this.isClaimedByMe(item)));
    if (!eligible.length) return;
    const label = action === 'claim' ? 'nhận xử lý' : 'trả lại hàng đợi';
    if (!window.confirm(`Xác nhận ${label} ${eligible.length} hồ sơ đã chọn?`)) return;
    this.loading.set(true);
    const requests = eligible.map(item => action === 'claim'
      ? this.moderationService.claim(item.moderationCaseId)
      : this.moderationService.release(item.moderationCaseId));
    forkJoin(requests).subscribe({
      next: () => {
        this.selectedCaseIds.update(ids => ids.filter(id => !eligible.some(item => item.moderationCaseId === id)));
        this.showMessage(`Đã ${label} ${eligible.length} hồ sơ.`);
        this.loadData();
      },
      error: err => {
        this.error.set(err?.error?.detail || `Không thể ${label} toàn bộ hồ sơ. Danh sách sẽ được làm mới để phản ánh các thay đổi đã áp dụng.`);
        this.loadData();
      }
    });
  }

  openReviewModal(item: ModerationQueueItem): void {
    this.activeCase.set(item);
    this.selectedPolicyCode.set('');
    this.internalNote.set(item.note || '');
    this.actionReason.set('');
    this.isReviewModalOpen.set(true);
  }

  closeReviewModal(): void {
    if (this.submitting()) return;
    this.isReviewModalOpen.set(false);
    this.isTheaterMode.set(false);
    this.activeCase.set(null);
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
    if (!currentCase) return;

    if (decision !== 'approve' && !this.selectedPolicyCode() && decision !== 'escalate') {
      alert(this.i18n.t('moderation.policyRequired'));
      return;
    }

    const selectedPolicy = this.policies().find(p => p.code === this.selectedPolicyCode());

    const req: ResolveModerationRequest = {
      decision,
      policyCode: this.selectedPolicyCode() || undefined,
      reason: this.actionReason().trim() || this.getPolicyName(selectedPolicy) || undefined,
      internalNote: this.internalNote().trim() || undefined
    };

    this.submitting.set(true);
    this.moderationService.resolve(currentCase.moderationCaseId, req).subscribe({
      next: (res) => {
        this.submitting.set(false);
        this.closeReviewModal();
        this.showMessage(res.message || this.i18n.t('moderation.resolveSuccess'));
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        alert(err?.error?.detail || this.i18n.t('common.error'));
      }
    });
  }

  isClaimedByMe(item: ModerationQueueItem): boolean {
    const myId = this.auth.user()?.userId;
    return !!myId && item.reviewerId === myId;
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
      case 'resolved': return 'Đã xử lý';
      default: return status;
    }
  }

  isProcessed(item: ModerationQueueItem): boolean {
    return item.status === 'approved' || item.status === 'rejected' || item.status === 'resolved';
  }

  waitingTime(submittedAt: string): string {
    const minutes = Math.max(0, Math.floor((Date.now() - new Date(submittedAt).getTime()) / 60_000));
    if (minutes < 60) return `${minutes} phút`;
    const hours = Math.floor(minutes / 60);
    return `${hours} giờ${minutes % 60 ? ` ${minutes % 60} phút` : ''}`;
  }

  formatDate(value: string): string {
    return new Intl.DateTimeFormat('vi-VN', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value));
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
    const item = this.queue().find(candidate => candidate.status === 'pending');
    if (item) this.claimCase(item);
  }

  private showMessage(msg: string): void {
    this.successMessage.set(msg);
    setTimeout(() => this.successMessage.set(null), 4000);
  }
}
