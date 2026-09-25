import { Component, OnInit, effect, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { AppealItem, ChannelStrikeStatus, ContentService, CreateAppealPayload } from '../../../core/content.service';
import { I18nService } from '../../../core/i18n.service';
import { LocaleDatePipe } from '../../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../../core/locale-number.pipe';
import { StudioDataService } from '../../../core/studio-data.service';
import { TranslatePipe } from '../../../core/translate.pipe';

@Component({
  selector: 'app-studio-overview-page',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, LocaleDatePipe, LocaleNumberPipe, TranslatePipe],
  templateUrl: './studio-overview-page.html',
  styleUrl: './studio-overview-page.scss',
})
export class StudioOverviewPage implements OnInit {
  readonly data = inject(StudioDataService);
  private readonly content = inject(ContentService);
  readonly i18n = inject(I18nService);

  readonly strikeStatus = signal<ChannelStrikeStatus | null>(null);
  readonly appeals = signal<AppealItem[]>([]);
  readonly selectedAppeal = signal<AppealItem | null>(null);
  readonly loadingAppeals = signal(false);

  readonly isAppealModalOpen = signal(false);
  readonly appealReason = signal('');
  readonly appealEvidenceFile = signal<File | null>(null);
  readonly appealEvidenceNote = signal('');
  readonly appealSubmitting = signal(false);
  readonly appealMessage = signal<string | null>(null);
  readonly appealError = signal<string | null>(null);

  private readonly appealEvidenceMaxBytes = 10 * 1024 * 1024;
  private readonly appealEvidenceMimeTypes = new Set([
    'image/png',
    'image/jpeg',
    'image/webp',
    'application/pdf',
  ]);
  private readonly appealEvidenceExtensions = new Set(['.png', '.jpg', '.jpeg', '.webp', '.pdf']);

  constructor() {
    effect(() => {
      const ch = this.data.channel();
      if (ch?.channelId) {
        this.loadStrikes(ch.channelId);
        this.loadAppeals();
      }
    });
  }

  visibilityLabel(value: string): string {
    if (value === 'public') return this.i18n.t('ui.public');
    if (value === 'unlisted') return this.i18n.t('ui.unlisted');
    return this.i18n.t('ui.private');
  }

  statusLabel(value: string | null | undefined): string {
    switch (value) {
      case 'published': return this.i18n.t('ui.statusPublished');
      case 'draft': return this.i18n.t('ui.statusDraft');
      case 'processing': return this.i18n.t('ui.statusProcessing');
      case 'scheduled': return this.i18n.t('ui.statusScheduled');
      case 'pending': return this.i18n.t('ui.statusPending');
      case 'rejected': return this.i18n.t('ui.statusRejected');
      default: return value || this.i18n.t('ui.status');
    }
  }

  appealStatusLabel(status: string): string {
    switch (status?.toLowerCase()) {
      case 'pending': return 'Chờ xử lý';
      case 'reviewing': return 'Đang thẩm định';
      case 'escalated': return 'Đã chuyển cấp cao hơn';
      case 'approved': return 'Chấp thuận (Gỡ phạt)';
      case 'rejected': return 'Bác bỏ (Giữ nguyên phạt)';
      case 'cancelled': return 'Đã rút đơn';
      default: return status || 'Không rõ';
    }
  }

  appealStatusClass(status: string): string {
    switch (status?.toLowerCase()) {
      case 'pending': return 'status-pending';
      case 'reviewing': return 'status-reviewing';
      case 'escalated': return 'status-escalated';
      case 'approved': return 'status-approved';
      case 'rejected': return 'status-rejected';
      case 'cancelled': return 'status-cancelled';
      default: return '';
    }
  }

  appealTargetLabel(targetType: string): string {
    switch (targetType?.toLowerCase()) {
      case 'video': return 'Video';
      case 'channel': return 'Kênh';
      case 'strike': return 'Gậy phạt';
      case 'comment': return 'Bình luận';
      default: return 'Nội dung';
    }
  }

  appealIsFinal(status: string): boolean {
    return ['approved', 'rejected', 'cancelled'].includes(status?.toLowerCase());
  }

  isAppealEligible(): boolean {
    const status = this.strikeStatus();
    const channel = this.data.channel();
    if (!status || !channel) return false;
    if (status.appealEligible !== undefined) return status.appealEligible;
    return status.isSuspended
      || channel.status === 'banned'
      || status.activeStrikesCount > 0
      || status.hasWarning
      || !!status.uploadRestrictedUntil;
  }

  openAppealDetail(appeal: AppealItem): void { this.selectedAppeal.set(appeal); }
  closeAppealDetail(): void { this.selectedAppeal.set(null); }

  ngOnInit() {
    this.data.load();
    const ch = this.data.channel();
    if (ch?.channelId) {
      this.loadStrikes(ch.channelId);
      this.loadAppeals();
    }
  }

  loadStrikes(channelId: string) {
    this.content.getChannelStrikes(channelId).subscribe({
      next: (status) => this.strikeStatus.set(status),
      error: () => {}
    });
  }

  loadAppeals() {
    this.loadingAppeals.set(true);
    this.content.getMyAppeals().subscribe({
      next: (items) => {
        this.appeals.set(items || []);
        this.loadingAppeals.set(false);
      },
      error: () => this.loadingAppeals.set(false)
    });
  }

  openAppealEvidence(appeal: AppealItem): void {
    if (!appeal.evidenceUrl) return;
    const tab = window.open('about:blank', '_blank');
    if (!tab) { this.appealError.set('Trình duyệt đã chặn cửa sổ bằng chứng. Hãy cho phép mở tab mới rồi thử lại.'); return; }
    this.content.getAppealEvidence(appeal.appealId).subscribe({
      next: blob => {
        const url = URL.createObjectURL(blob);
        tab.opener = null;
        tab.location.href = url;
        setTimeout(() => URL.revokeObjectURL(url), 60_000);
      },
      error: () => { tab.close(); this.appealError.set('Không thể mở tệp bằng chứng của đơn này.'); }
    });
  }

  openAppealModal() {
    if (!this.isAppealEligible()) return;
    this.appealReason.set('');
    this.clearAppealEvidence();
    this.appealEvidenceNote.set('');
    this.appealMessage.set(null);
    this.appealError.set(null);
    this.isAppealModalOpen.set(true);
  }

  closeAppealModal() {
    this.isAppealModalOpen.set(false);
  }

  submitAppeal() {
    const ch = this.data.channel();
    if (!this.isAppealEligible()) {
      this.appealError.set('Kênh hiện không có cảnh báo hoặc quyết định kiểm duyệt để gửi khiếu nại.');
      return;
    }
    if (!ch || !this.appealReason().trim()) {
      this.appealError.set('Vui lòng nhập lý do khiếu nại.');
      return;
    }

    this.appealSubmitting.set(true);
    this.appealError.set(null);

    const payload: CreateAppealPayload = {
      targetType: 'channel',
      targetId: ch.channelId,
      reason: this.appealReason().trim(),
      evidenceNote: this.appealEvidenceNote().trim() || undefined
    };

    this.content.createAppeal(payload, this.appealEvidenceFile()).subscribe({
      next: () => {
        this.appealSubmitting.set(false);
        this.appealMessage.set('Đơn khiếu nại của bạn đã được gửi. Ban quản trị độc lập sẽ thẩm định và phản hồi sớm nhất.');
        this.loadAppeals();
        setTimeout(() => this.closeAppealModal(), 2500);
      },
      error: (err) => {
        this.appealSubmitting.set(false);
        this.appealError.set(err?.error?.message || 'Không thể gửi đơn khiếu nại.');
      }
    });
  }

  onAppealEvidenceSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    this.setAppealEvidenceFile(input.files?.[0] ?? null);
  }

  onAppealEvidenceDragOver(event: DragEvent): void {
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'copy';
  }

  onAppealEvidenceDrop(event: DragEvent): void {
    event.preventDefault();
    this.setAppealEvidenceFile(event.dataTransfer?.files?.[0] ?? null);
  }

  clearAppealEvidence(): void {
    this.appealEvidenceFile.set(null);
    const input = document.getElementById('appeal-evidence-input') as HTMLInputElement | null;
    if (input) input.value = '';
  }

  formatAppealFileSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  private setAppealEvidenceFile(file: File | null): void {
    if (!file) {
      this.clearAppealEvidence();
      return;
    }

    const extension = `.${file.name.split('.').pop()?.toLowerCase() ?? ''}`;
    if (!this.appealEvidenceMimeTypes.has(file.type.toLowerCase()) && !this.appealEvidenceExtensions.has(extension)) {
      this.clearAppealEvidence();
      this.appealError.set('Tệp không đúng định dạng. Chỉ nhận PNG, JPEG, WEBP hoặc PDF.');
      return;
    }
    if (file.size < 1) {
      this.clearAppealEvidence();
      this.appealError.set('Tệp rỗng. Hãy chọn một tệp bằng chứng khác.');
      return;
    }
    if (file.size > this.appealEvidenceMaxBytes) {
      this.clearAppealEvidence();
      this.appealError.set('Tệp quá lớn. Kích thước tối đa là 10 MiB.');
      return;
    }

    this.appealEvidenceFile.set(file);
    this.appealError.set(null);
  }
}
