import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/auth.service';
import { AdminModerationService, ReportCaseDetail, ReportCaseReportDetail, ReportCaseSummary } from './admin-moderation.service';

type QueueStatus = 'ALL' | 'pending' | 'reviewing' | 'resolved' | 'escalated';
type ReportDecision = 'dismiss' | 'warn' | 'age_restrict' | 'recommendation_restricted' | 'hide' | 'remove' | 'upload_restriction' | 'strike' | 'lock_channel' | 'escalate';

@Component({
  selector: 'app-admin-reports-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './admin-reports-page.html',
  styleUrl: './admin-reports-page.scss'
})
export class AdminReportsPage implements OnInit {
  private readonly moderation = inject(AdminModerationService);
  readonly auth = inject(AuthService);
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
    const hideLabel = targetType === 'channel' ? 'Tạm ngưng kênh' : targetType === 'comment' ? 'Ẩn bình luận' : 'Ẩn khỏi bề mặt công khai';
    const removeLabel = targetType === 'channel' ? 'Cấm kênh' : targetType === 'comment' ? 'Gỡ bình luận' : 'Gỡ nội dung';
    const options: Array<{ value: ReportDecision; label: string; hint: string }> = [
      { value: 'dismiss', label: 'Không vi phạm', hint: 'Bác bỏ báo cáo và giữ nguyên đối tượng.' },
      { value: 'warn', label: 'Cảnh cáo', hint: 'Gửi cảnh cáo cho chủ sở hữu nội dung.' },
      { value: 'hide', label: hideLabel, hint: targetType === 'channel' ? 'Tạm ngưng kênh và lưu lý do quản trị.' : 'Ẩn đối tượng khỏi người xem.' },
      { value: 'remove', label: removeLabel, hint: targetType === 'channel' ? 'Cấm kênh và lưu lý do quản trị.' : 'Gỡ đối tượng theo lý do đã nhập.' },
      { value: 'escalate', label: 'Chuyển cấp', hint: 'Chuyển hồ sơ lên cấp cao hơn để xem xét.' }
    ];
    if (targetType === 'video') {
      options.splice(2, 0,
        { value: 'age_restrict', label: 'Giới hạn độ tuổi', hint: 'Gắn nhãn 18+ cho video.' },
        { value: 'recommendation_restricted', label: 'Hạn chế đề xuất', hint: 'Giữ video công khai nhưng không đưa vào gợi ý.' });
    }
    if (targetType === 'video' || targetType === 'channel') {
      const insertAt = Math.max(2, options.length - 1);
      if (this.canManageStrikes()) options.splice(insertAt, 0, { value: 'upload_restriction', label: 'Hạn chế tải lên', hint: 'Tạm dừng quyền tải video của kênh theo số ngày.' });
      if (this.canManageStrikes()) options.splice(insertAt, 0, { value: 'strike', label: 'Áp dụng gậy phạt', hint: 'Ghi một gậy phạt mức cao cho kênh sở hữu.' });
      if (this.canLockChannels()) options.splice(insertAt, 0, { value: 'lock_channel', label: 'Khóa kênh', hint: 'Tạm ngưng toàn bộ hoạt động của kênh.' });
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
      error: err => { this.error.set(err?.error?.message || 'Không thể tải danh sách hồ sơ báo cáo.'); this.loading.set(false); }
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
      error: err => this.error.set(err?.error?.message || 'Không thể tải chi tiết hồ sơ.')
    });
  }

  closeCase(): void { if (!this.submitting()) this.activeCase.set(null); }
  toggleReport(reportId: string, checked: boolean): void { this.selectedReports.update(current => ({ ...current, [reportId]: checked })); }

  claim(item: ReportCaseSummary): void {
    if (!this.canClaim()) return;
    this.submitting.set(true);
    this.moderation.claimReportCase(item.caseId).subscribe({
      next: () => { this.submitting.set(false); this.successMessage.set('Đã nhận hồ sơ báo cáo.'); this.loadData(); if (this.activeCase()?.case.caseId === item.caseId) this.openCase(item); },
      error: err => { this.submitting.set(false); this.error.set(err?.error?.message || 'Không thể nhận hồ sơ.'); }
    });
  }

  release(item: ReportCaseSummary): void {
    if (!this.canClaim()) return;
    this.submitting.set(true);
    this.moderation.releaseReportCase(item.caseId).subscribe({
      next: () => { this.submitting.set(false); this.successMessage.set('Đã trả hồ sơ về hàng đợi.'); this.loadData(); this.closeCase(); },
      error: err => { this.submitting.set(false); this.error.set(err?.error?.message || 'Không thể trả hồ sơ.'); }
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
        this.successMessage.set(`Đã phân loại ${reportIds.length} báo cáo.`);
        this.openCase(current.case);
        this.loadData();
      },
      error: err => { this.submitting.set(false); this.error.set(err?.error?.message || 'Không thể cập nhật kết quả báo cáo.'); }
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
        this.successMessage.set(result.message || 'Đã đóng hồ sơ.');
        this.activeCase.set(null);
        this.loadData();
      },
      error: err => { this.submitting.set(false); this.error.set(err?.error?.message || 'Không thể đóng hồ sơ.'); }
    });
  }
}
