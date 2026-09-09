import { CommonModule } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Observable, finalize } from 'rxjs';
import { ChannelInvitation, ChannelRole, ChannelService } from '../../core/channel.service';

@Component({
  selector: 'app-channel-invitations-page',
  standalone: true,
  imports: [CommonModule, RouterLink],
  templateUrl: './channel-invitations-page.html',
  styleUrl: './channel-invitations-page.scss'
})
export class ChannelInvitationsPage implements OnInit {
  private readonly channelService = inject(ChannelService);

  readonly invitations = signal<ChannelInvitation[]>([]);
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
    this.channelService.getMyInvitations().pipe(finalize(() => this.loading.set(false))).subscribe({
      next: invitations => this.invitations.set(invitations),
      error: error => this.error.set(this.message(error, 'Không thể tải lời mời. Vui lòng thử lại.'))
    });
  }

  accept(invitation: ChannelInvitation): void {
    this.run(invitation, 'accept', `Bạn đã tham gia kênh ${invitation.channelName}.`);
  }

  decline(invitation: ChannelInvitation): void {
    this.run(invitation, 'decline', `Đã từ chối lời mời từ ${invitation.channelName}.`);
  }

  roleName(code: string): string {
    return this.roles().find(role => role.code === code)?.name ?? code;
  }

  roleDescription(code: string): string {
    return this.roles().find(role => role.code === code)?.description ?? '';
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
      },
      error: error => this.error.set(this.message(error, 'Không thể xử lý lời mời. Vui lòng thử lại.'))
    });
  }

  private message(error: unknown, fallback: string): string {
    if (error instanceof HttpErrorResponse) {
      return error.error?.detail ?? error.error?.message ?? fallback;
    }
    return fallback;
  }
}
