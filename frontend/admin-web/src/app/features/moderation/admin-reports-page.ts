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
  readonly selectedStatus = signal<'ALL' | 'pending' | 'reviewing' | 'resolved' | 'dismissed'>('pending');
  readonly searchQuery = signal('');

  // Preview Modal
  readonly previewReport = signal<ReportItem | null>(null);
  readonly isPreviewModalOpen = signal(false);

  // Resolution Modal
  readonly activeReport = signal<ReportItem | null>(null);
  readonly isResolveModalOpen = signal(false);
  readonly submitting = signal(false);

  readonly selectedDecision = signal<string>('dismiss');
  readonly selectedPolicyCode = signal<string>('');
  readonly resolutionReason = signal<string>('');
  readonly internalNote = signal<string>('');

  readonly countPending = computed(() => this.reports().filter(r => r.status === 'pending').length);
  readonly countReviewing = computed(() => this.reports().filter(r => r.status === 'reviewing').length);
  readonly countResolved = computed(() => this.reports().filter(r => r.status === 'resolved').length);
  readonly countDismissed = computed(() => this.reports().filter(r => r.status === 'dismissed' || r.status === 'rejected').length);

  readonly policyGroups = computed(() => {
    const groupsMap = new Map<string, { label: string; items: PolicyItem[] }>();
    const groupLabelMap: Record<string, string> = {
      community_guidelines: 'Tiêu chuẩn nội dung cộng đồng',
      safety: 'An toàn & Bảo vệ người dùng',
      copyright: 'Bảo vệ bản quyền & Sở hữu trí tuệ',
      monetization: 'Chính sách kiếm tiền',
      platform: 'Nguyên tắc nền tảng & Thủ tục',
      terms: 'Điều khoản dịch vụ'
    };

    for (const p of this.policies()) {
      const grpKey = p.group || 'community_guidelines';
      if (!groupsMap.has(grpKey)) {
        const label = groupLabelMap[grpKey] || grpKey.toUpperCase();
        groupsMap.set(grpKey, { label, items: [] });
      }
      groupsMap.get(grpKey)!.items.push(p);
    }

    return Array.from(groupsMap.values());
  });

  readonly filteredReports = computed(() => {
    let items = this.reports();
    const targetType = this.selectedTargetType();
    const status = this.selectedStatus();
    const query = this.searchQuery().trim().toLowerCase();

    if (targetType !== 'ALL') {
      items = items.filter(x => x.targetType === targetType);
    }
    if (status !== 'ALL') {
      if (status === 'dismissed') {
        items = items.filter(x => x.status === 'dismissed' || x.status === 'rejected');
      } else {
        items = items.filter(x => x.status === status);
      }
    }
    if (query) {
      items = items.filter(x =>
        (x.targetTitle && x.targetTitle.toLowerCase().includes(query)) ||
        (x.description && x.description.toLowerCase().includes(query)) ||
        (x.reporterName && x.reporterName.toLowerCase().includes(query)) ||
        (x.targetChannelName && x.targetChannelName.toLowerCase().includes(query)) ||
        (x.contextText && x.contextText.toLowerCase().includes(query))
      );
    }
    return items;
  });

  openPreviewModal(report: ReportItem): void {
    this.previewReport.set(report);
    this.isPreviewModalOpen.set(true);
  }

  closePreviewModal(): void {
    this.isPreviewModalOpen.set(false);
    this.previewReport.set(null);
  }

  getTargetHref(item: ReportItem): string {
    if (item.targetUrl) {
      if (item.targetUrl.startsWith('http')) return item.targetUrl;
      return `http://localhost:4200${item.targetUrl}`;
    }
    if (item.targetType === 'video') return `http://localhost:4200/watch/${item.targetId}`;
    if (item.targetType === 'channel') return `http://localhost:4200/channel/${item.targetChannelHandle || item.targetId}`;
    return '#';
  }

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
