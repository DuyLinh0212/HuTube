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

  readonly ageBuckets = computed(() => {
    const now = Date.now();
    const active = this.queue().filter(item => !this.isProcessed(item));
    const age = (item: ModerationQueueItem) => Math.max(0, now - new Date(item.submittedAt).getTime()) / 3_600_000;
    return [
      { label: 'Dưới 2 giờ', count: active.filter(item => age(item) < 2).length, tone: 'green' },
      { label: '2–6 giờ', count: active.filter(item => age(item) >= 2 && age(item) < 6).length, tone: 'orange' },
      { label: 'Trên 6 giờ', count: active.filter(item => age(item) >= 6).length, tone: 'red' },
    ];
  });

  readonly categories = computed(() => [...new Set(this.queue().map(item => item.categoryName || 'Chưa phân loại'))].sort((a, b) => a.localeCompare(b, 'vi')));
  readonly slaPercent = computed(() => {
    const active = this.queue().filter(item => !this.isProcessed(item));
    if (!active.length) return 100;
    const withinTarget = active.filter(item => Date.now() - new Date(item.submittedAt).getTime() <= 6 * 3_600_000).length;
    return Math.round((withinTarget / active.length) * 100);
  });

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

  ageBarHeight(count: number): number {
    const max = Math.max(...this.ageBuckets().map(bucket => bucket.count), 1);
    return Math.max(12, Math.round((count / max) * 100));
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
