import { Component, ElementRef, ViewChild, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import {
  ChannelDetail,
  ChannelInvitation,
  ChannelMember,
  ChannelRole,
  ChannelService
} from '../../core/channel.service';
import { errorMessage } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

export type ChannelLinkPlatform = 'facebook' | 'instagram' | 'tiktok' | 'x' | 'other';

export interface ChannelLinkItem {
  platform: ChannelLinkPlatform;
  title: string;
  url: string;
}

type SettingsTab = 'basic' | 'branding' | 'members' | 'danger';

@Component({
  selector: 'app-channel-settings-page',
  imports: [LocaleDatePipe, FormsModule, RouterLink, TranslatePipe],
  templateUrl: './channel-settings-page.html',
  styleUrl: './channel-settings-page.scss'
})
export class ChannelSettingsPage {
  private route = inject(ActivatedRoute);
  private channelService = inject(ChannelService);
  private router = inject(Router);
  readonly i18n = inject(I18nService);

  @ViewChild('avatarInput') avatarInput?: ElementRef<HTMLInputElement>;
  @ViewChild('bannerInput') bannerInput?: ElementRef<HTMLInputElement>;

  readonly channel = signal<ChannelDetail | null>(null);
  readonly members = signal<ChannelMember[]>([]);
  readonly invitations = signal<ChannelInvitation[]>([]);
  readonly roles = signal<ChannelRole[]>([]);
  readonly activeTab = signal<SettingsTab>('basic');
  readonly loading = signal(true);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly message = signal('');
  readonly linkOptions: ChannelLinkPlatform[] = ['facebook', 'instagram', 'tiktok', 'x', 'other'];

  name = '';
  handle = '';
  description = '';
  contactEmail = '';
  watermarkUrl = '';
  links: ChannelLinkItem[] = [];
  inviteEmail = '';
  inviteRole: ChannelRole['code'] = 'editor';
  confirmChannelName = '';
  showDeleteModal = signal(false);

  constructor() {
    this.loadChannel();
  }

  can(permission: string): boolean {
    return this.channel()?.permissions.includes(permission) ?? false;
  }

  roleName(code: string): string {
    if (code === 'owner') return this.i18n.t('channel.roleOwner');
    const key = this.roleKey(code);
    return key ? this.i18n.t(key) : (this.roles().find(role => role.code === code)?.name ?? code);
  }

  roleDescription(code: string): string {
    const key = this.roleDescriptionKey(code);
    return key ? this.i18n.t(key) : (this.roles().find(role => role.code === code)?.description ?? '');
  }

  private roleKey(code: string): string | null {
    if (code === 'manager') return 'channel.roleManager';
    if (code === 'editor') return 'channel.roleEditor';
    if (code === 'moderator') return 'channel.roleModerator';
    if (code === 'viewer') return 'channel.roleViewer';
    return null;
  }

  private roleDescriptionKey(code: string): string | null {
    if (code === 'manager') return 'channel.roleManagerDesc';
    if (code === 'editor') return 'channel.roleEditorDesc';
    if (code === 'moderator') return 'channel.roleModeratorDesc';
    if (code === 'viewer') return 'channel.roleViewerDesc';
    return null;
  }

  addLink() {
    if (this.links.length < 14) {
      this.links.push({ platform: 'facebook', title: this.i18n.t('channel.platform.facebook'), url: '' });
    }
  }

  removeLink(index: number) {
    this.links.splice(index, 1);
  }

  loadChannel() {
    const handle = this.route.snapshot.paramMap.get('handle');
    if (!handle) {
      this.error.set(this.i18n.t('channel.handleNotFound'));
      this.loading.set(false);
      return;
    }

    this.loading.set(true);
    this.channelService.getChannel(handle).pipe(finalize(() => this.loading.set(false))).subscribe({
      next: channel => {
        this.channel.set(channel);
        this.name = channel.name;
        this.handle = channel.handle;
        this.description = channel.description ?? '';
        this.contactEmail = channel.contactEmail ?? '';
        this.watermarkUrl = channel.watermarkUrl ?? '';
        this.parseLinks(channel);
        this.chooseAvailableTab();
        this.loadCollaboration();
      },
      error: err => this.error.set(errorMessage(err, this.i18n) || this.i18n.t('channel.loadError'))
    });
  }

  private parseLinks(channel: ChannelDetail) {
    try {
      const parsed = typeof channel.settings === 'string' ? JSON.parse(channel.settings || '{}') : (channel.settings || {});
      if (Array.isArray(parsed?.links)) {
        this.links = parsed.links.map((l: any) => this.normalizeLink(l));
        return;
      }
    } catch {}

    const local = localStorage.getItem('hutube_channel_links_' + channel.channelId);
    if (local) {
      try {
        const parsedLocal = JSON.parse(local);
        if (Array.isArray(parsedLocal)) {
          this.links = parsedLocal.map((l: any) => this.normalizeLink(l));
          return;
        }
      } catch {}
    }
    this.links = [];
  }

  loadCollaboration() {
    const channel = this.channel();
    if (!channel) return;

    this.channelService.getRoles().subscribe({ next: roles => this.roles.set(roles) });
    if (this.can('member.view')) {
      this.channelService.getMembers(channel.channelId).subscribe({
        next: members => this.members.set(members),
        error: err => this.error.set(errorMessage(err, this.i18n))
      });
    }
    if (this.can('member.invite')) {
      this.channelService.getPendingInvitations(channel.channelId).subscribe({
        next: invitations => this.invitations.set(invitations),
        error: err => this.error.set(errorMessage(err, this.i18n))
      });
    }
  }

  setTab(tab: SettingsTab) {
    this.activeTab.set(tab);
    this.error.set('');
    this.message.set('');
    if (tab === 'members') this.loadCollaboration();
  }

  onSaveBasicInfo() {
    const channel = this.channel();
    if (!channel || this.busy() || !this.can('channel.edit_profile')) return;
    if (!this.name.trim()) return this.error.set(this.i18n.t('channel.nameEmpty'));
    const cleanHandle = this.handle.trim().replace(/^@/, '');
    if (cleanHandle.length < 3) return this.error.set(this.i18n.t('channel.handleLength'));

    for (const link of this.links) {
      if (link.url.trim() && !this.isValidLinkUrl(link.url)) {
        return this.error.set(this.i18n.t('channel.linkUrlError'));
      }
    }

    const validLinks = this.links.filter(l => l.url.trim()).map(l => ({
      platform: l.platform,
      title: this.linkTitle(l.platform, l.title),
      url: l.url.trim()
    }));
    let currentSettings: Record<string, any> = {};
    try {
      if (channel.settings) {
        currentSettings = typeof channel.settings === 'string' ? JSON.parse(channel.settings) : channel.settings;
      }
    } catch {}
    currentSettings['links'] = validLinks;
    localStorage.setItem('hutube_channel_links_' + channel.channelId, JSON.stringify(validLinks));

    this.runAction(
      this.channelService.updateChannel(channel.channelId, {
        name: this.name.trim(),
        handle: cleanHandle,
        description: this.description.trim(),
        contactEmail: this.contactEmail.trim(),
        watermarkUrl: this.watermarkUrl.trim(),
        settings: JSON.stringify(currentSettings)
      }),
      this.i18n.t('channel.basicSaved')
    );
  }

  linkTitle(platform: ChannelLinkPlatform, current = ''): string {
    if (platform === 'other') return current.trim() || this.i18n.t('channel.otherLink');
    return this.i18n.t('channel.platform.' + platform);
  }

  onPlatformChange(link: ChannelLinkItem) {
    link.title = this.linkTitle(link.platform, link.title);
  }

  private normalizeLink(link: any): ChannelLinkItem {
    const platform = this.detectPlatform(link?.url, link?.platform);
    return { platform, title: this.linkTitle(platform, link?.title || ''), url: link?.url || '' };
  }

  private detectPlatform(url: string, value?: string): ChannelLinkPlatform {
    if (value === 'facebook' || value === 'instagram' || value === 'tiktok' || value === 'x' || value === 'other') return value;
    const lower = String(url || '').toLowerCase();
    if (lower.includes('facebook.com') || lower.includes('fb.me')) return 'facebook';
    if (lower.includes('instagram.com')) return 'instagram';
    if (lower.includes('tiktok.com')) return 'tiktok';
    if (lower.includes('twitter.com') || lower.includes('x.com')) return 'x';
    return 'other';
  }

  private isValidLinkUrl(value: string): boolean {
    try { return ['http:', 'https:'].includes(new URL(value.trim()).protocol); } catch { return false; }
  }

  linkUrlValid(value: string): boolean { return !value.trim() || this.isValidLinkUrl(value); }

  onAvatarSelected(event: Event) {
    const channel = this.channel();
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!channel || !file || !this.can('channel.edit_branding')) return;
    this.runAction(this.channelService.uploadAvatar(channel.channelId, file), this.i18n.t('channel.avatarSaved'));
    input.value = '';
  }

  onBannerSelected(event: Event) {
    const channel = this.channel();
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!channel || !file || !this.can('channel.edit_branding')) return;
    this.runAction(this.channelService.uploadBanner(channel.channelId, file), this.i18n.t('channel.bannerSaved'));
    input.value = '';
  }

  inviteMember() {
    const channel = this.channel();
    if (!channel || !this.inviteEmail.trim() || !this.can('member.invite')) return;
    this.busy.set(true);
    this.clearFeedback();
    this.channelService.inviteMember(channel.channelId, this.inviteEmail.trim(), this.inviteRole)
      .pipe(finalize(() => this.busy.set(false)))
      .subscribe({
        next: () => {
          this.inviteEmail = '';
          this.message.set(this.i18n.t('channel.inviteSent'));
          this.loadCollaboration();
        },
        error: err => this.error.set(errorMessage(err, this.i18n))
      });
  }

  changeRole(member: ChannelMember, roleCode: string) {
    const channel = this.channel();
    if (!channel || roleCode === 'owner' || !this.can('member.change_role')) return;
    this.busy.set(true);
    this.clearFeedback();
    this.channelService.changeMemberRole(channel.channelId, member.userId, roleCode as ChannelRole['code'])
      .pipe(finalize(() => this.busy.set(false)))
      .subscribe({
        next: () => {
          this.message.set(this.i18n.t('channel.roleUpdated', { member: member.displayName }));
          this.loadCollaboration();
        },
        error: err => this.error.set(errorMessage(err, this.i18n))
      });
  }

  removeMember(member: ChannelMember) {
    const channel = this.channel();
    if (!channel || member.roleCode === 'owner' || !this.can('member.remove')) return;
    if (!window.confirm(this.i18n.t('channel.removeConfirm', { member: member.displayName }))) return;
    this.busy.set(true);
    this.clearFeedback();
    this.channelService.removeMember(channel.channelId, member.userId)
      .pipe(finalize(() => this.busy.set(false)))
      .subscribe({
        next: () => {
          this.message.set(this.i18n.t('channel.memberRemoved'));
          this.loadCollaboration();
        },
        error: err => this.error.set(errorMessage(err, this.i18n))
      });
  }

  revokeInvitation(invitation: ChannelInvitation) {
    const channel = this.channel();
    if (!channel || !this.can('member.invite')) return;
    this.busy.set(true);
    this.clearFeedback();
    this.channelService.revokeInvitation(channel.channelId, invitation.channelInvitationId)
      .pipe(finalize(() => this.busy.set(false)))
      .subscribe({
        next: () => {
          this.message.set(this.i18n.t('channel.inviteWithdrawn'));
          this.loadCollaboration();
        },
        error: err => this.error.set(errorMessage(err, this.i18n))
      });
  }

  onConfirmDeleteChannel() {
    const channel = this.channel();
    if (!channel || this.busy() || !this.can('channel.delete')) return;
    if (this.confirmChannelName.trim() !== channel.name.trim()) {
      this.error.set(this.i18n.t('channel.confirmNameMismatch'));
      return;
    }

    this.busy.set(true);
    this.clearFeedback();
    this.channelService.deleteChannel(channel.channelId).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => {
        this.showDeleteModal.set(false);
        void this.router.navigate(['/account']);
      },
      error: err => this.error.set(errorMessage(err, this.i18n))
    });
  }

  private chooseAvailableTab() {
    if (this.can('channel.edit_profile')) this.activeTab.set('basic');
    else if (this.can('member.view')) this.activeTab.set('members');
    else this.activeTab.set('branding');
  }

  private clearFeedback() {
    this.error.set('');
    this.message.set('');
  }

  private runAction(request: ReturnType<ChannelService['updateChannel']>, successMessage: string) {
    this.busy.set(true);
    this.clearFeedback();
    request.pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => {
        this.message.set(successMessage);
        this.loadChannel();
      },
      error: err => this.error.set(errorMessage(err, this.i18n))
    });
  }
}
