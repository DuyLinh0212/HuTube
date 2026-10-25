import { ChannelPickerComponent } from './channel-picker.component';
import { ConfirmDialogComponent } from '@dalitu/ui/confirm-dialog.component';
import { ResultNoticeComponent } from '@dalitu/ui/result-notice.component';
import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';
import {
  AdminModerationService,
  CreateStrikeRequest,
  ModerationChannelOption,
  PolicyItem,
  RevokeStrikeRequest,
  StrikeItem,
  StrikePolicySettings,
  UpdateStrikePolicySettingsRequest
} from './admin-moderation.service';

type StrikePolicyNumberKey = keyof Pick<StrikePolicySettings,
  'rejectedVideosPerStrike' | 'firstStrikeRestrictionDays' | 'secondStrikeRestrictionDays' | 'strikeExpirationDays' | 'suspensionStrikeCount'>;

@Component({
  selector: 'app-admin-strikes-page',
  standalone: true,
  imports: [ChannelPickerComponent, ConfirmDialogComponent, ResultNoticeComponent, CommonModule, FormsModule, TranslatePipe],
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
  readonly policyLoading = signal(true);
  readonly policySaving = signal(false);
  readonly policy = signal<StrikePolicySettings>({
    rejectedVideosPerStrike: 5,
    firstStrikeRestrictionDays: 7,
    secondStrikeRestrictionDays: 14,
    strikeExpirationDays: 90,
    suspensionStrikeCount: 3,
    rejectedVideosEffectiveAt: '',
    updatedAt: ''
  });
  readonly savedPolicy = signal<StrikePolicySettings | null>(null);

  readonly selectedStatus = signal<'ALL' | 'active' | 'expired' | 'revoked'>('ALL');
  readonly searchQuery = signal('');
  readonly showOverview = signal(false);

  // Modals
  readonly isCreateModalOpen = signal(false);
  readonly isRevokeModalOpen = signal(false);
  readonly isChannelLockModalOpen = signal(false);
  readonly activeStrike = signal<StrikeItem | null>(null);
  readonly submitting = signal(false);

  // Create Strike form
  readonly createChannelId = signal('');
  readonly createChannel = signal<ModerationChannelOption | null>(null);
  readonly createPolicyCode = signal('');
  readonly createSeverity = signal('high');
  readonly createReason = signal('');
  readonly createInternalNote = signal('');

  // Revoke Strike form
  readonly revokeReason = signal('');

  // Channel Lock form
  readonly lockChannelId = signal('');
  readonly lockChannel = signal<ModerationChannelOption | null>(null);
  readonly lockAction = signal<'lock' | 'unlock'>('lock');
  readonly lockReason = signal('');

  // Keep the UI aligned with the same permissions enforced by AdminController.
  // `strike.view` is enough to load this page, but it must not expose mutation
  // actions that would be rejected by the API.
  readonly canManageStrikes = computed(() => this.auth.hasPermission('strike.manage'));
  readonly canLockChannels = computed(() => this.auth.hasPermission('channel.lock'));

  readonly selectedChannelId = signal('');
  readonly affectedChannels = computed(() => {
    const grouped = new Map<string, { channelId: string; userId: string; name: string; handle: string | null; count: number }>();
    for (const strike of this.strikes()) {
      if (strike.status !== 'active' || strike.strikeNumber <= 0) continue;
      const current = grouped.get(strike.channelId);
      if (current) current.count++;
      else grouped.set(strike.channelId, { channelId: strike.channelId, userId: strike.userId,
        name: strike.channelName || this.i18n.t('strikes.channel'), handle: strike.channelHandle ?? null, count: 1 });
    }
    return [...grouped.values()].sort((a, b) => b.count - a.count || a.name.localeCompare(b.name, this.i18n.currentLang()));
  });
  readonly affectedUserCount = computed(() => new Set(this.affectedChannels().map(channel => channel.userId)).size);
  readonly lockedChannelCount = computed(() => new Set(this.strikes().filter(strike => strike.channelStatus === 'suspended').map(strike => strike.channelId)).size);
  readonly activeWarningCount = computed(() => this.strikes().filter(strike => strike.status === 'active' && strike.strikeNumber === 0).length);
  readonly selectedChannelName = computed(() => this.knownChannels().find(channel => channel.channelId === this.selectedChannelId())?.name ?? '');
  focusChannel(channelId: string): void {
    this.selectedChannelId.set(this.selectedChannelId() === channelId ? '' : channelId);
    this.searchQuery.set(''); this.selectedStatus.set('active');
  }

  readonly countActive = computed(() => this.strikes().filter(s => s.status === 'active').length);
  readonly countExpired = computed(() => this.strikes().filter(s => s.status === 'expired').length);
  readonly countRevoked = computed(() => this.strikes().filter(s => s.status === 'revoked').length);
  readonly policyDirty = computed(() => {
    const saved = this.savedPolicy();
    const draft = this.policy();
    return !!saved && (
      saved.rejectedVideosPerStrike !== draft.rejectedVideosPerStrike ||
      saved.firstStrikeRestrictionDays !== draft.firstStrikeRestrictionDays ||
      saved.secondStrikeRestrictionDays !== draft.secondStrikeRestrictionDays ||
      saved.strikeExpirationDays !== draft.strikeExpirationDays ||
      saved.suspensionStrikeCount !== draft.suspensionStrikeCount
    );
  });
  readonly policyValid = computed(() => {
    const value = this.policy();
    return Number.isInteger(value.rejectedVideosPerStrike) && value.rejectedVideosPerStrike >= 1 && value.rejectedVideosPerStrike <= 100
      && Number.isInteger(value.firstStrikeRestrictionDays) && value.firstStrikeRestrictionDays >= 0 && value.firstStrikeRestrictionDays <= 365
      && Number.isInteger(value.secondStrikeRestrictionDays) && value.secondStrikeRestrictionDays >= value.firstStrikeRestrictionDays && value.secondStrikeRestrictionDays <= 365
      && Number.isInteger(value.strikeExpirationDays) && value.strikeExpirationDays >= Math.max(1, value.secondStrikeRestrictionDays) && value.strikeExpirationDays <= 3650
      && Number.isInteger(value.suspensionStrikeCount) && value.suspensionStrikeCount >= 3 && value.suspensionStrikeCount <= 10;
  });
  readonly rejectedVideosForSuspension = computed(() => this.policy().rejectedVideosPerStrike * this.policy().suspensionStrikeCount);

  readonly policyGroups = computed(() => {
    const groupsMap = new Map<string, { label: string; items: PolicyItem[] }>();
    const groupLabelKeys: Record<string, string> = {
      community_guidelines: 'strikes.policyGroup.communityGuidelines',
      safety: 'strikes.policyGroup.safety',
      copyright: 'strikes.policyGroup.copyright',
      monetization: 'strikes.policyGroup.monetization',
      platform: 'strikes.policyGroup.platform',
      terms: 'strikes.policyGroup.terms'
    };

    for (const p of this.policies()) {
      const grpKey = p.group || 'community_guidelines';
      if (!groupsMap.has(grpKey)) {
        const label = groupLabelKeys[grpKey] ? this.i18n.t(groupLabelKeys[grpKey]) : grpKey.toUpperCase();
        groupsMap.set(grpKey, { label, items: [] });
      }
      groupsMap.get(grpKey)!.items.push(p);
    }

    return Array.from(groupsMap.values());
  });

  readonly knownChannels = computed(() => {
    const map = new Map<string, { channelId: string; name: string; handle?: string | null; status?: string | null }>();
    for (const s of this.strikes()) {
      if (s.channelId && !map.has(s.channelId)) {
        map.set(s.channelId, {
          channelId: s.channelId,
          name: s.channelName || this.i18n.t('strikes.channel'),
          handle: s.channelHandle,
          status: s.channelStatus
        });
      }
    }
    return Array.from(map.values());
  });

  policyName(code: string | null): string {
    if (!code) return this.i18n.t('strikes.generalPolicy');
    return this.policies().find(policy => policy.code === code)?.name || this.i18n.t('strikes.unavailablePolicy');
  }

  readonly filteredStrikes = computed(() => {
    let items = this.strikes();
    if (this.selectedChannelId()) items = items.filter(item => item.channelId === this.selectedChannelId());
    const status = this.selectedStatus();
    const query = this.searchQuery().trim().toLowerCase();

    if (status !== 'ALL') {
      items = items.filter(x => x.status === status);
    }
    if (query) {
      items = items.filter(x =>
        (x.channelName && x.channelName.toLowerCase().includes(query)) ||
        (x.reason && x.reason.toLowerCase().includes(query)) ||
        this.policyName(x.policyCode).toLowerCase().includes(query) ||
        (x.policyCode && x.policyCode.toLowerCase().includes(query)) ||
        (x.channelHandle && x.channelHandle.toLowerCase().includes(query))
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
        this.error.set(err?.error?.message || this.i18n.t('strikes.loadError'));
        this.loading.set(false);
      }
    });

    this.moderationService.getPolicies().subscribe({
      next: (items) => this.policies.set(items),
      error: () => {}
    });

    this.policyLoading.set(true);
    this.moderationService.getStrikePolicySettings().subscribe({
      next: (settings) => {
        this.policy.set(settings);
        this.savedPolicy.set(settings);
        this.policyLoading.set(false);
      },
      error: (err) => {
        this.error.set(err?.error?.message || this.i18n.t('strikes.policyLoadError'));
        this.policyLoading.set(false);
      }
    });
  }

  setPolicyValue(key: StrikePolicyNumberKey, value: number | string): void {
    const numberValue = Number(value);
    this.policy.update(current => ({ ...current, [key]: Number.isFinite(numberValue) ? numberValue : 0 }));
  }

  savePolicy(): void {
    if (!this.canManageStrikes() || this.policySaving()) return;
    if (!this.policyValid()) {
      this.error.set(this.i18n.t('strikes.policyInvalid'));
      return;
    }

    const current = this.policy();
    const request: UpdateStrikePolicySettingsRequest = {
      rejectedVideosPerStrike: current.rejectedVideosPerStrike,
      firstStrikeRestrictionDays: current.firstStrikeRestrictionDays,
      secondStrikeRestrictionDays: current.secondStrikeRestrictionDays,
      strikeExpirationDays: current.strikeExpirationDays,
      suspensionStrikeCount: current.suspensionStrikeCount
    };
    this.policySaving.set(true);
    this.error.set(null);
    this.moderationService.updateStrikePolicySettings(request).subscribe({
      next: (settings) => {
        this.policy.set(settings);
        this.savedPolicy.set(settings);
        this.policySaving.set(false);
        this.successMessage.set(this.i18n.t('strikes.policySaved'));
      },
      error: (err) => {
        this.policySaving.set(false);
        this.error.set(err?.error?.message || this.i18n.t('strikes.policySaveError'));
      }
    });
  }

  openCreateModal(): void {
    if (!this.canManageStrikes()) return;

    this.selectCreateChannel(null);
    this.error.set(null);
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
    if (!this.canManageStrikes()) return;

    if (!this.createChannelId().trim() || !this.createReason().trim()) {
      this.error.set(this.i18n.t('strikes.channelReasonRequired'));
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
        this.successMessage.set(this.i18n.format('strikes.createdSuccess', { number: created.strikeNumber }));
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.message || this.i18n.t('strikes.createError'));
      }
    });
  }

  openRevokeModal(strike: StrikeItem): void {
    if (!this.canManageStrikes()) return;

    this.activeStrike.set(strike);
    this.revokeReason.set('');
    this.isRevokeModalOpen.set(true);
  }

  closeRevokeModal(): void {
    this.isRevokeModalOpen.set(false);
    this.activeStrike.set(null);
  }

  submitRevokeStrike(): void {
    if (!this.canManageStrikes()) return;

    const strike = this.activeStrike();
    if (!strike || !this.revokeReason()) {
      this.error.set(this.i18n.t('strikes.revokeReasonRequired'));
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
        this.successMessage.set(this.i18n.format('strikes.revokedSuccess', { number: strike.strikeNumber }));
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.message || this.i18n.t('strikes.revokeError'));
      }
    });
  }

  openChannelLockModal(channelId?: string, action: 'lock' | 'unlock' = 'lock'): void {
    if (!this.canLockChannels()) return;

    this.lockChannelId.set(channelId || '');
    const channel = this.knownChannels().find(item => item.channelId === channelId);
    this.lockChannel.set(channel ? { ...channel, handle: channel.handle || '', status: channel.status || '' } : null);
    this.error.set(null);
    this.lockAction.set(action);
    this.lockReason.set('');
    this.isChannelLockModalOpen.set(true);
  }

  selectCreateChannel(channel: ModerationChannelOption | null): void {
    this.createChannel.set(channel); this.createChannelId.set(channel?.channelId ?? '');
  }
  selectLockChannel(channel: ModerationChannelOption | null): void {
    this.lockChannel.set(channel); this.lockChannelId.set(channel?.channelId ?? '');
    if (channel?.status === 'suspended') this.lockAction.set('unlock');
    else if (channel?.status === 'active') this.lockAction.set('lock');
  }

  closeChannelLockModal(): void {
    this.isChannelLockModalOpen.set(false);
  }

  submitChannelLock(): void {
    if (!this.canLockChannels()) return;

    if (!this.lockChannelId().trim() || !this.lockReason().trim()) {
      this.error.set(this.i18n.t('strikes.lockReasonRequired'));
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
        this.successMessage.set(this.i18n.format('strikes.lockSuccess', {
          action: this.i18n.t(action === 'lock' ? 'strikes.lockedAction' : 'strikes.unlockedAction'),
        }));
        this.loadData();
      },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.message || this.i18n.format('strikes.lockError', {
          action: this.i18n.t(action === 'lock' ? 'strikes.lockedAction' : 'strikes.unlockedAction'),
        }));
      }
    });
  }

  dateLocale(): string {
    return this.i18n.currentLang() === 'en' ? 'en-US' : 'vi-VN';
  }
}
