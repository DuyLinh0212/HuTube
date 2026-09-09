import { DatePipe } from '@angular/common';
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

type SettingsTab = 'basic' | 'branding' | 'members' | 'danger';

@Component({
  selector: 'app-channel-settings-page',
  imports: [DatePipe, FormsModule, RouterLink],
  templateUrl: './channel-settings-page.html',
  styleUrl: './channel-settings-page.scss'
})
export class ChannelSettingsPage {
  private route = inject(ActivatedRoute);
  private channelService = inject(ChannelService);
  private router = inject(Router);

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

  name = '';
  handle = '';
  description = '';
  contactEmail = '';
  watermarkUrl = '';
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
    if (code === 'owner') return 'Chủ sở hữu';
    return this.roles().find(role => role.code === code)?.name ?? code;
  }

  loadChannel() {
    const handle = this.route.snapshot.paramMap.get('handle');
    if (!handle) {
      this.error.set('Không tìm thấy handle kênh.');
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
        this.chooseAvailableTab();
        this.loadCollaboration();
      },
      error: err => this.error.set(errorMessage(err) || 'Không thể tải thông tin kênh.')
    });
  }

  loadCollaboration() {
    const channel = this.channel();
    if (!channel) return;

    this.channelService.getRoles().subscribe({ next: roles => this.roles.set(roles) });
    if (this.can('member.view')) {
      this.channelService.getMembers(channel.channelId).subscribe({
        next: members => this.members.set(members),
        error: err => this.error.set(errorMessage(err))
      });
    }
    if (this.can('member.invite')) {
      this.channelService.getPendingInvitations(channel.channelId).subscribe({
        next: invitations => this.invitations.set(invitations),
        error: err => this.error.set(errorMessage(err))
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
    if (!this.name.trim()) return this.error.set('Tên kênh không được để trống.');
    const cleanHandle = this.handle.trim().replace(/^@/, '');
    if (cleanHandle.length < 3) return this.error.set('Handle cần từ 3 đến 50 ký tự.');

    this.runAction(
      this.channelService.updateChannel(channel.channelId, {
        name: this.name.trim(),
        handle: cleanHandle,
        description: this.description.trim(),
        contactEmail: this.contactEmail.trim(),
        watermarkUrl: this.watermarkUrl.trim()
      }),
      'Đã cập nhật thông tin kênh.'
    );
  }

  onAvatarSelected(event: Event) {
    const channel = this.channel();
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!channel || !file || !this.can('channel.edit_branding')) return;
    this.runAction(this.channelService.uploadAvatar(channel.channelId, file), 'Đã cập nhật ảnh đại diện kênh.');
    input.value = '';
  }

  onBannerSelected(event: Event) {
    const channel = this.channel();
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!channel || !file || !this.can('channel.edit_branding')) return;
    this.runAction(this.channelService.uploadBanner(channel.channelId, file), 'Đã cập nhật ảnh bìa kênh.');
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
          this.message.set('Đã gửi lời mời tham gia kênh.');
          this.loadCollaboration();
        },
        error: err => this.error.set(errorMessage(err))
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
          this.message.set(`Đã cập nhật vai trò của ${member.displayName}.`);
          this.loadCollaboration();
        },
        error: err => this.error.set(errorMessage(err))
      });
  }

  removeMember(member: ChannelMember) {
    const channel = this.channel();
    if (!channel || member.roleCode === 'owner' || !this.can('member.remove')) return;
    if (!window.confirm(`Gỡ ${member.displayName} khỏi kênh?`)) return;
    this.busy.set(true);
    this.clearFeedback();
    this.channelService.removeMember(channel.channelId, member.userId)
      .pipe(finalize(() => this.busy.set(false)))
      .subscribe({
        next: () => {
          this.message.set('Đã gỡ thành viên khỏi kênh.');
          this.loadCollaboration();
        },
        error: err => this.error.set(errorMessage(err))
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
          this.message.set('Đã thu hồi lời mời.');
          this.loadCollaboration();
        },
        error: err => this.error.set(errorMessage(err))
      });
  }

  onConfirmDeleteChannel() {
    const channel = this.channel();
    if (!channel || this.busy() || !this.can('channel.delete')) return;
    if (this.confirmChannelName.trim() !== channel.name.trim()) {
      this.error.set('Tên kênh xác nhận chưa khớp chính xác.');
      return;
    }

    this.busy.set(true);
    this.clearFeedback();
    this.channelService.deleteChannel(channel.channelId).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => {
        this.showDeleteModal.set(false);
        void this.router.navigate(['/account']);
      },
      error: err => this.error.set(errorMessage(err))
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
      error: err => this.error.set(errorMessage(err))
    });
  }
}
