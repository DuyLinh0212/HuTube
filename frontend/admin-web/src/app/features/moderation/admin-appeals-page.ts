import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';
import {
  AdminModerationService,
  AppealItem,
  ResolveAppealRequest
} from './admin-moderation.service';

@Component({
  selector: 'app-admin-appeals-page',
  standalone: true,
  imports: [CommonModule, FormsModule, TranslatePipe],
  templateUrl: './admin-appeals-page.html',
  styleUrl: './admin-appeals-page.scss'
})
export class AdminAppealsPage implements OnInit {
  private readonly moderationService = inject(AdminModerationService);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);
  canResolveAppeal(): boolean { return this.auth.hasPermission('appeal.resolve'); }

  openEvidence(appeal: AppealItem): void {
    if (!appeal.evidenceUrl) return;
    const tab = window.open('about:blank', '_blank');
    if (!tab) { this.error.set(this.i18n.t('appeals.openBlocked')); return; }
    this.moderationService.getAppealEvidence(appeal.appealId).subscribe({
      next: blob => {
        const url = URL.createObjectURL(blob);
        tab.opener = null;
        tab.location.href = url;
        setTimeout(() => URL.revokeObjectURL(url), 60_000);
      },
      error: () => { tab.close(); this.error.set(this.i18n.t('appeals.openError')); }
    });
  }

  readonly loading = signal(true);
  readonly error = signal<string | null>(null);
  readonly successMessage = signal<string | null>(null);
  readonly appeals = signal<AppealItem[]>([]);

  readonly selectedTargetType = signal<'ALL' | 'video' | 'channel' | 'comment' | 'strike'>('ALL');
  readonly selectedStatus = signal<'ALL' | 'pending' | 'reviewing' | 'approved' | 'rejected' | 'escalated'>('pending');
  readonly searchQuery = signal('');

  // Resolution Modal
  readonly activeAppeal = signal<AppealItem | null>(null);
  readonly isResolveModalOpen = signal(false);
  readonly submitting = signal(false);

  readonly selectedDecision = signal<'approve' | 'reject' | 'escalate'>('approve');
  readonly reviewNote = signal<string>('');

  readonly countPending = computed(() => this.appeals().filter(a => a.status === 'pending').length);
  readonly countReviewing = computed(() => this.appeals().filter(a => a.status === 'reviewing').length);
  readonly countApproved = computed(() => this.appeals().filter(a => a.status === 'approved').length);
  readonly countRejected = computed(() => this.appeals().filter(a => a.status === 'rejected').length);

  readonly filteredAppeals = computed(() => {
    let items = this.appeals();
    const targetType = this.selectedTargetType();
    const status = this.selectedStatus();
    const query = this.searchQuery().trim().toLowerCase();

    if (targetType !== 'ALL') {
      items = items.filter(x => x.targetType === targetType);
    }
    if (status !== 'ALL') {
      items = items.filter(x => x.status === status);
    }
    if (query) {
      items = items.filter(x =>
        (x.targetTitle && x.targetTitle.toLowerCase().includes(query)) ||
        (x.reason && x.reason.toLowerCase().includes(query)) ||
        (x.userName && x.userName.toLowerCase().includes(query))
      );
    }
    return items;
  });

  ngOnInit(): void {
    this.loadData();
  }

  loadData(): void {
    this.loading.set(true);
    this.error.set(null);

    this.moderationService.getAppeals().subscribe({
      next: (items) => {
        this.appeals.set(items);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err?.error?.message || this.i18n.t('appeals.loadError'));
        this.loading.set(false);
      }
    });
  }

  claimAppeal(appeal: AppealItem): void {
    this.submitting.set(true);
    this.moderationService.claimAppeal(appeal.appealId).subscribe({
      next: () => {
        this.submitting.set(false);
        this.successMessage.set(this.i18n.format('appeals.claimSuccess', { id: appeal.appealId.slice(0, 8) }));
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.message || this.i18n.t('appeals.claimError'));
      }
    });
  }

  releaseAppeal(appeal: AppealItem): void {
    this.submitting.set(true);
    this.moderationService.releaseAppeal(appeal.appealId).subscribe({
      next: () => {
        this.submitting.set(false);
        this.successMessage.set(this.i18n.format('appeals.releaseSuccess', { id: appeal.appealId.slice(0, 8) }));
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.message || this.i18n.t('appeals.releaseError'));
      }
    });
  }

  openResolveModal(appeal: AppealItem): void {
    this.activeAppeal.set(appeal);
    this.selectedDecision.set('approve');
    this.reviewNote.set('');
    this.isResolveModalOpen.set(true);
  }

  closeResolveModal(): void {
    this.isResolveModalOpen.set(false);
    this.activeAppeal.set(null);
  }

  submitResolution(): void {
    const appeal = this.activeAppeal();
    if (!appeal) return;

    this.submitting.set(true);
    this.error.set(null);

    const payload: ResolveAppealRequest = {
      decision: this.selectedDecision(),
      reviewNote: this.reviewNote() || undefined
    };

    this.moderationService.resolveAppeal(appeal.appealId, payload).subscribe({
      next: (res) => {
        this.submitting.set(false);
        this.closeResolveModal();
        this.successMessage.set(res.message || this.i18n.t('appeals.resolveSuccess'));
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.message || this.i18n.t('appeals.resolveError'));
      }
    });
  }

  targetTypeLabel(targetType: string): string {
    const key = targetType === 'video' ? 'moderation.colVideo'
      : targetType === 'channel' ? 'nav.channels'
        : targetType === 'comment' ? 'moderation.colComment'
          : targetType === 'strike' ? 'appeals.strike' : '';
    return key ? this.i18n.t(key) : targetType;
  }

  statusLabel(status: string): string {
    const keys: Record<string, string> = {
      pending: 'appeals.pending',
      reviewing: 'appeals.reviewing',
      approved: 'appeals.approved',
      rejected: 'appeals.rejected',
      escalated: 'moderation.statusEscalated',
    };
    return keys[status] ? this.i18n.t(keys[status]) : status;
  }

  dateLocale(): string {
    return this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US';
  }
}
