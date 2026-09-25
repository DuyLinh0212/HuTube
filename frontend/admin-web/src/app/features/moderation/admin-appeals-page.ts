import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import {
  AdminModerationService,
  AppealItem,
  ResolveAppealRequest
} from './admin-moderation.service';

@Component({
  selector: 'app-admin-appeals-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
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
    if (!tab) { this.error.set('Trình duyệt đã chặn cửa sổ bằng chứng. Hãy cho phép mở tab mới rồi thử lại.'); return; }
    this.moderationService.getAppealEvidence(appeal.appealId).subscribe({
      next: blob => {
        const url = URL.createObjectURL(blob);
        tab.opener = null;
        tab.location.href = url;
        setTimeout(() => URL.revokeObjectURL(url), 60_000);
      },
      error: () => { tab.close(); this.error.set('Không thể mở tệp bằng chứng của đơn này.'); }
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
        this.error.set(err?.error?.message || 'Không thể tải danh sách khiếu nại.');
        this.loading.set(false);
      }
    });
  }

  claimAppeal(appeal: AppealItem): void {
    this.submitting.set(true);
    this.moderationService.claimAppeal(appeal.appealId).subscribe({
      next: () => {
        this.submitting.set(false);
        this.successMessage.set(`Đã nhận xử lý khiếu nại #${appeal.appealId.slice(0, 8)}`);
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.message || 'Không thể nhận xử lý khiếu nại.');
      }
    });
  }

  releaseAppeal(appeal: AppealItem): void {
    this.submitting.set(true);
    this.moderationService.releaseAppeal(appeal.appealId).subscribe({
      next: () => {
        this.submitting.set(false);
        this.successMessage.set(`Đã trả lại khiếu nại #${appeal.appealId.slice(0, 8)} vào hàng đợi.`);
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.message || 'Không thể trả lại khiếu nại.');
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
        this.successMessage.set(res.message || 'Đã phân xử khiếu nại thành công.');
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.message || 'Không thể xử lý khiếu nại.');
      }
    });
  }
}
