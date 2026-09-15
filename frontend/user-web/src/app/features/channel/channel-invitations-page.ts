import { CommonModule } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, effect, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Observable, finalize, forkJoin } from 'rxjs';
import { ChannelDetail, ChannelInvitation, ChannelRole, ChannelService } from '../../core/channel.service';
import { NotificationService } from '../../core/notification.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-channel-invitations-page',
  standalone: true,
  imports: [CommonModule, LocaleDatePipe, RouterLink, TranslatePipe],
  templateUrl: './channel-invitations-page.html',
  styleUrl: './channel-invitations-page.scss'
})
export class ChannelInvitationsPage implements OnInit {
  private readonly channelService = inject(ChannelService);
  private readonly notifications = inject(NotificationService);
  readonly i18n = inject(I18nService);
  private readonly invitationRefresh = effect(() => {
    if (this.notifications.invitationVersion() > 0) this.load();
  });

  readonly invitations = signal<ChannelInvitation[]>([]);
  readonly accessibleChannels = signal<ChannelDetail[]>([]);
  readonly roles = signal<ChannelRole[]>([]);
  readonly loading = signal(true);
  readonly busyId = signal<string | null>(null);
  readonly error = signal('');
  readonly success = signal('');

  ngOnInit(): void {
    this.load();
    this.channelService.getRoles().subscribe({ next: roles => this.roles.set(roles) });
  }

  load(): void {
    this.loading.set(true);
    this.error.set('');
    forkJoin({
      invitations: this.channelService.getMyInvitations(),
      channels: this.channelService.getAccessibleChannels()
    }).pipe(finalize(() => this.loading.set(false))).subscribe({
      next: result => {
        this.invitations.set(result.invitations);
        this.accessibleChannels.set(result.channels);
      },
      error: error => this.error.set(this.message(error, this.i18n.t('channel.loadInvitationsError')))
    });
  }

  accept(invitation: ChannelInvitation): void {
    this.run(invitation, 'accept', this.i18n.t('channel.acceptSuccess', { channel: invitation.channelName }));
  }

  decline(invitation: ChannelInvitation): void {
    this.run(invitation, 'decline', this.i18n.t('channel.declineSuccess', { channel: invitation.channelName }));
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

  channelRole(channel: ChannelDetail): string {
    return channel.isOwner ? this.i18n.t('channel.roleOwner') : this.roleName(channel.myRole ?? 'viewer');
  }

  permissionSummary(channel: ChannelDetail): string {
    if (channel.isOwner) return this.i18n.t('channel.fullManagement');
    if (channel.permissions.includes('video.edit')) return this.i18n.t('channel.videoManagement');
    if (channel.permissions.includes('comment.manage')) return this.i18n.t('channel.commentManagement');
    return this.i18n.t('channel.viewGrantedData');
  }

  private run(invitation: ChannelInvitation, action: 'accept' | 'decline', success: string): void {
    this.busyId.set(invitation.channelInvitationId);
    this.error.set('');
    this.success.set('');
    const request: Observable<unknown> = action === 'accept'
      ? this.channelService.acceptInvitation(invitation.channelInvitationId)
      : this.channelService.declineInvitation(invitation.channelInvitationId);
    request.pipe(finalize(() => this.busyId.set(null))).subscribe({
      next: () => {
        this.success.set(success);
        this.invitations.update(items => items.filter(item => item.channelInvitationId !== invitation.channelInvitationId));
        this.channelService.getAccessibleChannels().subscribe({ next: channels => this.accessibleChannels.set(channels) });
      },
      error: error => this.error.set(this.message(error, this.i18n.t('channel.processInvitationError')))
    });
  }

  private message(error: unknown, fallback: string): string {
    if (error instanceof HttpErrorResponse && error.status === 0) return this.i18n.t('auth.serverUnavailable');
    return fallback;
  }
}
