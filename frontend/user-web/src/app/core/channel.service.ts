import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { RuntimeConfig } from './runtime-config';

export interface ChannelSummary {
  channelId: string;
  ownerUserId: string;
  name: string;
  handle: string;
  description: string | null;
  avatarUrl: string | null;
  bannerUrl: string | null;
  contactEmail: string | null;
  watermarkUrl: string | null;
  status: string;
  createdAt: string;
}

export interface ChannelDetail {
  channelId: string;
  ownerUserId: string;
  name: string;
  handle: string;
  description: string | null;
  avatarUrl: string | null;
  bannerUrl: string | null;
  contactEmail: string | null;
  watermarkUrl: string | null;
  settings: string;
  status: string;
  subscriberCount: number;
  videoCount: number;
  isOwner: boolean;
  myRole: ChannelRoleCode | null;
  permissions: string[];
  createdAt: string;
}

export type ChannelRoleCode = 'owner' | 'manager' | 'editor' | 'moderator' | 'viewer';

export interface ChannelRole {
  code: Exclude<ChannelRoleCode, 'owner'>;
  name: string;
  description: string;
  permissions: string[];
}

export interface ChannelMember {
  channelMemberId: string;
  channelId: string;
  userId: string;
  username: string;
  email: string;
  displayName: string;
  avatarUrl: string | null;
  roleCode: ChannelRoleCode;
  permissions: string[];
  status: string;
  joinedAt: string;
}

export interface ChannelInvitation {
  channelInvitationId: string;
  channelId: string;
  channelName: string;
  channelHandle: string;
  invitedUserId: string | null;
  invitedEmail: string | null;
  invitedByUserId: string;
  roleCode: Exclude<ChannelRoleCode, 'owner'>;
  permissions: string[];
  status: 'pending' | 'accepted' | 'declined' | 'expired' | 'revoked';
  expiresAt: string;
  createdAt: string;
}

export interface CreateChannelRequest {
  name: string;
  handle: string;
  description?: string;
  avatarUrl?: string;
  bannerUrl?: string;
  contactEmail?: string;
}

export interface UpdateChannelRequest {
  name?: string;
  handle?: string;
  description?: string;
  avatarUrl?: string;
  bannerUrl?: string;
  contactEmail?: string;
  watermarkUrl?: string;
  settings?: string;
}

export interface CheckHandleResponse {
  handle: string;
  isAvailable: boolean;
  message: string;
}

@Injectable({ providedIn: 'root' })
export class ChannelService {
  private http = inject(HttpClient);
  private config = inject(RuntimeConfig);
  private base = this.config.apiBaseUrl + '/channels';

  getMyChannel(): Observable<ChannelDetail> {
    return this.http.get<ChannelDetail>(`${this.base}/me`);
  }

  getAccessibleChannels(): Observable<ChannelDetail[]> {
    return this.http.get<ChannelDetail[]>(`${this.base}/accessible`);
  }

  getChannel(handle: string): Observable<ChannelDetail> {
    const clean = handle.startsWith('@') ? handle.slice(1) : handle;
    return this.http.get<ChannelDetail>(`${this.base}/handle/${encodeURIComponent(clean)}`);
  }

  createChannel(request: CreateChannelRequest): Observable<ChannelSummary> {
    return this.http.post<ChannelSummary>(this.base, request);
  }

  updateChannel(channelId: string, request: UpdateChannelRequest): Observable<ChannelSummary> {
    return this.http.patch<ChannelSummary>(`${this.base}/${channelId}`, request);
  }

  deleteChannel(channelId: string): Observable<void> {
    return this.http.delete<void>(`${this.base}/${channelId}`);
  }

  checkHandle(handle: string, currentChannelId?: string): Observable<CheckHandleResponse> {
    let params = new HttpParams().set('handle', handle);
    if (currentChannelId) {
      params = params.set('currentChannelId', currentChannelId);
    }
    return this.http.get<CheckHandleResponse>(`${this.base}/check-handle`, { params });
  }

  uploadAvatar(channelId: string, file: File): Observable<ChannelSummary> {
    const formData = new FormData();
    formData.append('file', file);
    return this.http.post<ChannelSummary>(`${this.base}/${channelId}/avatar`, formData);
  }

  uploadBanner(channelId: string, file: File): Observable<ChannelSummary> {
    const formData = new FormData();
    formData.append('file', file);
    return this.http.post<ChannelSummary>(`${this.base}/${channelId}/banner`, formData);
  }

  getRoles(): Observable<ChannelRole[]> {
    return this.http.get<ChannelRole[]>(`${this.base}/roles`);
  }

  getMembers(channelId: string): Observable<ChannelMember[]> {
    return this.http.get<ChannelMember[]>(`${this.base}/${channelId}/members`);
  }

  getPendingInvitations(channelId: string): Observable<ChannelInvitation[]> {
    return this.http.get<ChannelInvitation[]>(`${this.base}/${channelId}/invitations`);
  }

  getMyInvitations(): Observable<ChannelInvitation[]> {
    return this.http.get<ChannelInvitation[]>(`${this.base}/invitations/me`);
  }

  inviteMember(channelId: string, email: string, roleCode: ChannelRole['code']): Observable<ChannelInvitation> {
    return this.http.post<ChannelInvitation>(`${this.base}/${channelId}/members/invite`, { email, roleCode });
  }

  acceptInvitation(invitationId: string): Observable<ChannelMember> {
    return this.http.post<ChannelMember>(`${this.base}/invitations/${invitationId}/accept`, {});
  }

  declineInvitation(invitationId: string): Observable<void> {
    return this.http.post<void>(`${this.base}/invitations/${invitationId}/decline`, {});
  }

  revokeInvitation(channelId: string, invitationId: string): Observable<void> {
    return this.http.delete<void>(`${this.base}/${channelId}/invitations/${invitationId}`);
  }

  changeMemberRole(channelId: string, userId: string, roleCode: ChannelRole['code']): Observable<ChannelMember> {
    return this.http.patch<ChannelMember>(`${this.base}/${channelId}/members/${userId}/role`, { roleCode });
  }

  removeMember(channelId: string, userId: string): Observable<void> {
    return this.http.delete<void>(`${this.base}/${channelId}/members/${userId}`);
  }
}
