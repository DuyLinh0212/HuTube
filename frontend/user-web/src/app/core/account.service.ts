import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { RuntimeConfig } from './runtime-config';
import { Message } from './auth.service';

export interface UserProfile {
  userId: string;
  username: string;
  email: string;
  displayName: string;
  avatarUrl: string | null;
  bio: string | null;
  emailVerified: boolean;
  createdAt: string;
}

export interface UpdateProfileRequest {
  displayName?: string;
  bio?: string;
  avatarUrl?: string;
}

export interface ChangePasswordRequest {
  currentPassword: string;
  newPassword: string;
}

export interface NotificationSettings {
  inAppEnabled: boolean;
  emailEnabled: boolean;
  newVideoEnabled: boolean;
  commentReplyEnabled: boolean;
  reportResultEnabled: boolean;
  moderationEnabled: boolean;
  planEnabled: boolean;
  recommendationEnabled: boolean;
  mentionEnabled: boolean;
  channelActivityEnabled: boolean;
  paymentEnabled: boolean;
}

export interface UserPreferences {
  language: string;
  theme: string;
  keepSubscriptionsPrivate: boolean;
  keepPlaylistsPrivate: boolean;
  location: string | null;
}

@Injectable({ providedIn: 'root' })
export class AccountService {
  private http = inject(HttpClient);
  private config = inject(RuntimeConfig);
  private get base(): string {
    return this.config.apiBaseUrl + '/account';
  }

  getProfile(): Observable<UserProfile> {
    return this.http.get<UserProfile>(`${this.base}/profile`);
  }

  updateProfile(request: UpdateProfileRequest): Observable<UserProfile> {
    return this.http.patch<UserProfile>(`${this.base}/profile`, request);
  }

  changePassword(request: ChangePasswordRequest): Observable<Message> {
    return this.http.post<Message>(`${this.base}/change-password`, request);
  }

  getNotificationSettings(): Observable<NotificationSettings> {
    return this.http.get<NotificationSettings>(`${this.base}/notifications`);
  }

  updateNotificationSettings(settings: NotificationSettings): Observable<NotificationSettings> {
    return this.http.put<NotificationSettings>(`${this.base}/notifications`, settings);
  }

  getPreferences(): Observable<UserPreferences> {
    return this.http.get<UserPreferences>(`${this.base}/settings`);
  }

  updatePreferences(prefs: Partial<UserPreferences>): Observable<UserPreferences> {
    return this.http.put<UserPreferences>(`${this.base}/settings`, prefs);
  }

  uploadAvatar(file: File): Observable<UserProfile> {
    const formData = new FormData();
    formData.append('file', file);
    return this.http.post<UserProfile>(`${this.base}/avatar`, formData);
  }
}
