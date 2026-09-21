import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import {
  AdminModerationService,
  CreateStrikeRequest,
  PolicyItem,
  RevokeStrikeRequest,
  StrikeItem
} from './admin-moderation.service';

@Component({
  selector: 'app-admin-strikes-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './admin-strikes-page.html',
  styleUrl: './admin-strikes-page.scss'
})
export class AdminStrikesPage implements OnInit {
  private readonly moderationService = inject(AdminModerationService);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);

  readonly loading = signal(true);
  readonly error = signal<string | null>(null);
  readonly successMessage = signal<string | null>(null);
  readonly strikes = signal<StrikeItem[]>([]);
  readonly policies = signal<PolicyItem[]>([]);

  readonly selectedStatus = signal<'ALL' | 'active' | 'expired' | 'revoked'>('ALL');
  readonly searchQuery = signal('');

  // Modals
  readonly isCreateModalOpen = signal(false);
  readonly isRevokeModalOpen = signal(false);
  readonly isChannelLockModalOpen = signal(false);
  readonly activeStrike = signal<StrikeItem | null>(null);
  readonly submitting = signal(false);

  // Create Strike form
  readonly createChannelId = signal('');
  readonly createPolicyCode = signal('');
  readonly createSeverity = signal('high');
  readonly createReason = signal('');
  readonly createInternalNote = signal('');

  // Revoke Strike form
  readonly revokeReason = signal('');

  // Channel Lock form
  readonly lockChannelId = signal('');
  readonly lockAction = signal<'lock' | 'unlock'>('lock');
  readonly lockReason = signal('');

  readonly countActive = computed(() => this.strikes().filter(s => s.status === 'active').length);
  readonly countExpired = computed(() => this.strikes().filter(s => s.status === 'expired').length);
  readonly countRevoked = computed(() => this.strikes().filter(s => s.status === 'revoked').length);

  readonly filteredStrikes = computed(() => {
    let items = this.strikes();
    const status = this.selectedStatus();
    const query = this.searchQuery().trim().toLowerCase();

    if (status !== 'ALL') {
      items = items.filter(x => x.status === status);
    }
    if (query) {
      items = items.filter(x =>
        (x.channelName && x.channelName.toLowerCase().includes(query)) ||
        (x.reason && x.reason.toLowerCase().includes(query)) ||
        (x.policyCode && x.policyCode.toLowerCase().includes(query))
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

    this.moderationService.getStrikes().subscribe({
      next: (items) => {
        this.strikes.set(items);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err?.error?.message || 'Không thể tải danh sách gậy phạt.');
        this.loading.set(false);
      }
    });

    this.moderationService.getPolicies().subscribe({
      next: (items) => this.policies.set(items),
      error: () => {}
    });
  }

  openCreateModal(): void {
    this.createChannelId.set('');
    this.createPolicyCode.set('');
    this.createSeverity.set('high');
    this.createReason.set('');
    this.createInternalNote.set('');
    this.isCreateModalOpen.set(true);
  }

  closeCreateModal(): void {
    this.isCreateModalOpen.set(false);
  }

  submitCreateStrike(): void {
    if (!this.createChannelId() || !this.createReason()) {
      this.error.set('Vui lòng nhập Channel ID và lý do áp dụng gậy.');
      return;
    }

    this.submitting.set(true);
    const payload: CreateStrikeRequest = {
      channelId: this.createChannelId().trim(),
      policyCode: this.createPolicyCode() || undefined,
      severity: this.createSeverity(),
      reason: this.createReason().trim(),
      internalNote: this.createInternalNote() || undefined
    };

    this.moderationService.createStrike(payload).subscribe({
      next: (created) => {
        this.submitting.set(false);
        this.closeCreateModal();
        this.successMessage.set(`Đã áp dụng gậy phạt #${created.strikeNumber} cho kênh.`);
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.message || 'Không thể áp dụng gậy phạt.');
      }
    });
  }

  openRevokeModal(strike: StrikeItem): void {
    this.activeStrike.set(strike);
    this.revokeReason.set('');
    this.isRevokeModalOpen.set(true);
  }

  closeRevokeModal(): void {
    this.isRevokeModalOpen.set(false);
    this.activeStrike.set(null);
  }

  submitRevokeStrike(): void {
    const strike = this.activeStrike();
    if (!strike || !this.revokeReason()) {
      this.error.set('Vui lòng nhập lý do thu hồi gậy.');
      return;
    }

    this.submitting.set(true);
    const payload: RevokeStrikeRequest = {
      reason: this.revokeReason().trim()
    };

    this.moderationService.revokeStrike(strike.strikeId, payload).subscribe({
      next: () => {
        this.submitting.set(false);
        this.closeRevokeModal();
        this.successMessage.set(`Đã thu hồi gậy phạt #${strike.strikeNumber} thành công.`);
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.message || 'Không thể thu hồi gậy phạt.');
      }
    });
  }

  openChannelLockModal(channelId?: string, action: 'lock' | 'unlock' = 'lock'): void {
    this.lockChannelId.set(channelId || '');
    this.lockAction.set(action);
    this.lockReason.set('');
    this.isChannelLockModalOpen.set(true);
  }

  closeChannelLockModal(): void {
    this.isChannelLockModalOpen.set(false);
  }

  submitChannelLock(): void {
    if (!this.lockChannelId() || !this.lockReason()) {
      this.error.set('Vui lòng nhập Channel ID và lý do.');
      return;
    }

    this.submitting.set(true);
    const action = this.lockAction();
    const req = action === 'lock'
      ? this.moderationService.lockChannel(this.lockChannelId().trim(), this.lockReason().trim())
      : this.moderationService.unlockChannel(this.lockChannelId().trim(), this.lockReason().trim());

    req.subscribe({
      next: () => {
        this.submitting.set(false);
        this.closeChannelLockModal();
        this.successMessage.set(`Đã ${action === 'lock' ? 'khóa' : 'mở khóa'} kênh thành công.`);
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.message || `Không thể ${action === 'lock' ? 'khóa' : 'mở khóa'} kênh.`);
      }
    });
  }
}
