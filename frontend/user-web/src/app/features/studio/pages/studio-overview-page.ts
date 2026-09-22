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
  readonly loadingAppeals = signal(false);

  readonly isAppealModalOpen = signal(false);
  readonly appealReason = signal('');
  readonly appealEvidenceUrl = signal('');
  readonly appealEvidenceNote = signal('');
  readonly appealSubmitting = signal(false);
  readonly appealMessage = signal<string | null>(null);
  readonly appealError = signal<string | null>(null);

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
      case 'under_review': return 'Đang thẩm định';
      case 'approved': return 'Chấp thuận (Gỡ phạt)';
      case 'rejected': return 'Bác bỏ (Giữ nguyên phạt)';
      default: return status || 'Không rõ';
    }
  }

  appealStatusClass(status: string): string {
    switch (status?.toLowerCase()) {
      case 'pending': return 'status-pending';
      case 'under_review': return 'status-reviewing';
      case 'approved': return 'status-approved';
      case 'rejected': return 'status-rejected';
      default: return '';
    }
  }

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

  openAppealModal() {
    this.appealReason.set('');
    this.appealEvidenceUrl.set('');
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
      evidenceUrl: this.appealEvidenceUrl().trim() || undefined,
      evidenceNote: this.appealEvidenceNote().trim() || undefined
    };

    this.content.createAppeal(payload).subscribe({
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
}
