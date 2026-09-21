import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import {
  AdminModerationService,
  PolicyItem,
  ReportItem,
  ResolveReportRequest
} from './admin-moderation.service';

@Component({
  selector: 'app-admin-reports-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './admin-reports-page.html',
  styleUrl: './admin-reports-page.scss'
})
export class AdminReportsPage implements OnInit {
  private readonly moderationService = inject(AdminModerationService);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);

  readonly loading = signal(true);
  readonly error = signal<string | null>(null);
  readonly successMessage = signal<string | null>(null);
  readonly reports = signal<ReportItem[]>([]);
  readonly policies = signal<PolicyItem[]>([]);

  readonly selectedTargetType = signal<'ALL' | 'video' | 'comment' | 'channel'>('ALL');
  readonly selectedStatus = signal<'ALL' | 'pending' | 'resolved' | 'dismissed'>('pending');
  readonly searchQuery = signal('');

  // Resolution Modal
  readonly activeReport = signal<ReportItem | null>(null);
  readonly isResolveModalOpen = signal(false);
  readonly submitting = signal(false);

  readonly selectedDecision = signal<string>('dismiss');
  readonly selectedPolicyCode = signal<string>('');
  readonly resolutionReason = signal<string>('');
  readonly internalNote = signal<string>('');

  readonly countPending = computed(() => this.reports().filter(r => r.status === 'pending').length);
  readonly countResolved = computed(() => this.reports().filter(r => r.status === 'resolved').length);
  readonly countDismissed = computed(() => this.reports().filter(r => r.status === 'dismissed').length);

  readonly filteredReports = computed(() => {
    let items = this.reports();
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
        (x.description && x.description.toLowerCase().includes(query)) ||
        (x.reporterName && x.reporterName.toLowerCase().includes(query))
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

    this.moderationService.getReports().subscribe({
      next: (items) => {
        this.reports.set(items);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err?.error?.message || 'Không thể tải danh sách báo cáo.');
        this.loading.set(false);
      }
    });

    this.moderationService.getPolicies().subscribe({
      next: (items) => this.policies.set(items),
      error: () => {}
    });
  }

  claimReport(report: ReportItem): void {
    this.submitting.set(true);
    this.moderationService.claimReport(report.reportId).subscribe({
      next: () => {
        this.submitting.set(false);
        this.successMessage.set(`Đã nhận xử lý báo cáo #${report.reportId.slice(0, 8)}`);
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.message || 'Không thể nhận xử lý báo cáo.');
      }
    });
  }

  releaseReport(report: ReportItem): void {
    this.submitting.set(true);
    this.moderationService.releaseReport(report.reportId).subscribe({
      next: () => {
        this.submitting.set(false);
        this.successMessage.set(`Đã trả lại báo cáo #${report.reportId.slice(0, 8)} vào hàng đợi.`);
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.message || 'Không thể trả lại báo cáo.');
      }
    });
  }

  openResolveModal(report: ReportItem): void {
    this.activeReport.set(report);
    this.selectedDecision.set('dismiss');
    this.selectedPolicyCode.set(report.violationTypeCode || '');
    this.resolutionReason.set('');
    this.internalNote.set('');
    this.isResolveModalOpen.set(true);
  }

  closeResolveModal(): void {
    this.isResolveModalOpen.set(false);
    this.activeReport.set(null);
  }

  submitResolution(): void {
    const report = this.activeReport();
    if (!report) return;

    this.submitting.set(true);
    this.error.set(null);

    const payload: ResolveReportRequest = {
      decision: this.selectedDecision(),
      policyCode: this.selectedPolicyCode() || undefined,
      reason: this.resolutionReason() || undefined,
      internalNote: this.internalNote() || undefined
    };

    this.moderationService.resolveReport(report.reportId, payload).subscribe({
      next: (res) => {
        this.submitting.set(false);
        this.closeResolveModal();
        this.successMessage.set(res.message || 'Đã giải quyết báo cáo thành công.');
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.message || 'Không thể giải quyết báo cáo.');
      }
    });
  }
}
