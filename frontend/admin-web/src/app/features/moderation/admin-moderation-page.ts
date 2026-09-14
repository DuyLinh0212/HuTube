import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';
import {
  AdminModerationService,
  ModerationQueueItem,
  PolicyItem,
  ResolveModerationRequest
} from './admin-moderation.service';

@Component({
  selector: 'app-admin-moderation-page',
  standalone: true,
  imports: [CommonModule, FormsModule, TranslatePipe],
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

  readonly selectedStatus = signal<'ALL' | 'pending' | 'reviewing' | 'escalated'>('ALL');
  readonly selectedRisk = signal<'ALL' | 'high' | 'low'>('ALL');
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
    const query = this.searchQuery().trim().toLowerCase();

    if (status !== 'ALL') {
      items = items.filter(x => x.status === status);
    }
    if (risk !== 'ALL') {
      items = items.filter(x => x.riskLevel === risk);
    }
    if (query) {
      items = items.filter(x =>
        x.videoTitle.toLowerCase().includes(query) ||
        x.channelName.toLowerCase().includes(query)
      );
    }
    return items;
  });

  readonly stats = computed(() => {
    const all = this.queue();
    return {
      total: all.length,
      pending: all.filter(x => x.status === 'pending').length,
      reviewing: all.filter(x => x.status === 'reviewing').length,
      highRisk: all.filter(x => x.riskLevel === 'high').length
    };
  });

  ngOnInit(): void {
    this.loadData();
  }

  loadData(): void {
    this.loading.set(true);
    this.error.set(null);

    this.moderationService.getQueue().subscribe({
      next: (items) => {
        this.queue.set(items);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err?.error?.detail || this.i18n.t('common.error'));
        this.loading.set(false);
      }
    });

    this.moderationService.getPolicies().subscribe({
      next: (policies) => {
        this.policies.set(policies);
      },
      error: () => {
        // Soft-fail for dropdown policies
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
    this.internalNote.set(item.internalNote || '');
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

  submitDecision(decision: 'Approve' | 'AgeRestricted' | 'RecommendationRestricted' | 'Reject' | 'Escalate'): void {
    const currentCase = this.activeCase();
    if (!currentCase) return;

    if (decision !== 'Approve' && !this.selectedPolicyCode() && decision !== 'Escalate') {
      alert(this.i18n.t('moderation.policyRequired'));
      return;
    }

    const selectedPolicy = this.policies().find(p => p.code === this.selectedPolicyCode());

    const req: ResolveModerationRequest = {
      decision,
      policyCode: this.selectedPolicyCode() || undefined,
      policyVersion: selectedPolicy?.version || undefined,
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
      case 'approved': return this.i18n.t('moderation.statusApproved');
      case 'rejected': return this.i18n.t('moderation.statusRejected');
      default: return status;
    }
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

  private showMessage(msg: string): void {
    this.successMessage.set(msg);
    setTimeout(() => this.successMessage.set(null), 4000);
  }
}
