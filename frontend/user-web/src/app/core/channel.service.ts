import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { RuntimeConfig } from './runtime-config';
import { Message } from './auth.service';

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

  getChannel(handle: string): Observable<ChannelDetail> {
    const clean = handle.startsWith('@') ? handle.slice(1) : handle;
    return this.http.get<ChannelDetail>(`${this.base}/${encodeURIComponent(clean)}`);
  }

  createChannel(request: CreateChannelRequest): Observable<ChannelSummary> {
    return this.http.post<ChannelSummary>(this.base, request);
  }

  updateChannel(channelId: string, request: UpdateChannelRequest): Observable<ChannelSummary> {
    return this.http.patch<ChannelSummary>(`${this.base}/${channelId}`, request);
  }

  deleteChannel(channelId: string): Observable<Message> {
    return this.http.delete<Message>(`${this.base}/${channelId}`);
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
}
