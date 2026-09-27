import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { RuntimeConfig } from '../../core/runtime-config';

export type AdminUserStatus = 'active' | 'banned' | 'suspended' | 'pending' | 'deleted';

export interface AdminUserItem {
  userId: string;
  displayName: string;
  username: string;
  email: string;
  avatarUrl: string | null;
  roleCode: string;
  roleName: string;
  planCode: string | null;
  planName: string | null;
  channelCount: number;
  warningCount: number;
  lastLoginAt: string | null;
  createdAt: string;
  status: AdminUserStatus;
  emailVerified: boolean;
  lockedUntil: string | null;
}

export interface AdminUserStats {
  total: number;
  active: number;
  blocked: number;
  creatorPro: number;
}

export interface AdminUsersResponse {
  items: AdminUserItem[];
  page: number;
  pageSize: number;
  total: number;
  hasMore: boolean;
  stats: AdminUserStats;
}

export interface AdminUserAuditItem {
  action: string;
  reason: string | null;
  createdAt: string;
}

export interface AdminUserChannel {
  channelId: string;
  name: string;
  handle: string;
  status: string;
}

export interface AdminUserDetail extends AdminUserItem {
  permissions: string[];
  auditHistory: AdminUserAuditItem[];
  channels: AdminUserChannel[];
}

export interface AdminUserStatisticsSummary {
  totalWatchSeconds: number;
  videosWatched: number;
  completionRate: number;
  likes: number;
  dislikes: number;
  comments: number;
  averageRating: number | null;
  ratings: number;
}

export interface AdminUserCategoryStatistic {
  categoryId: string | null;
  categoryName: string | null;
  interactionCount: number;
  percentage: number;
}

export interface AdminUserRecommendationComparison {
  videoId: string;
  title: string;
  thumbnailUrl: string | null;
  categoryName: string | null;
  rank: number;
  score: number;
  source: string;
  modelVersion: string;
  watched: boolean;
  latestProgress: number | null;
  reaction: string | null;
  rating: number | null;
  categoryInteractionCount: number;
  categoryInteractionPercentage: number;
}

export interface AdminUserStatistics {
  userId: string;
  from: string;
  to: string;
  summary: AdminUserStatisticsSummary;
  categories: AdminUserCategoryStatistic[];
  recommendations: AdminUserRecommendationComparison[];
  recommendationsAvailable: boolean;
  recommendationModelVersion: string | null;
}

export interface AdminUserActionRequest {
  reason: string;
  notify: boolean;
}

export interface UpdateAdminUserRoleRequest {
  roleCode: string;
  reason: string;
}

export interface AdminRoleOption {
  roleId: string;
  code: string;
  name: string;
  description?: string | null;
  permissions?: string[];
}

@Injectable({ providedIn: 'root' })
export class AdminUsersService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);
  private readonly baseUrl = `${this.config.apiBaseUrl}/admin/users`;

  getUsers(page = 1, pageSize = 10, search = '', role = 'ALL', status = 'ALL', refreshToken?: number): Observable<AdminUsersResponse> {
    let params = new HttpParams().set('page', page).set('pageSize', pageSize);
    if (search.trim()) params = params.set('search', search.trim());
    if (role !== 'ALL') params = params.set('role', role);
    if (status !== 'ALL') params = params.set('status', status);
    if (refreshToken !== undefined) params = params.set('_refresh', refreshToken);
    return this.http.get<AdminUsersResponse>(this.baseUrl, { params });
  }

  getUser(userId: string): Observable<AdminUserDetail> {
    return this.http.get<AdminUserDetail>(`${this.baseUrl}/${encodeURIComponent(userId)}`);
  }

  getStatistics(userId: string, from: string, to: string): Observable<AdminUserStatistics> {
    const params = new HttpParams().set('from', from).set('to', to);
    return this.http.get<AdminUserStatistics>(`${this.baseUrl}/${encodeURIComponent(userId)}/statistics`, { params });
  }

  getRoles(): Observable<AdminRoleOption[]> {
    return this.http.get<AdminRoleOption[]>(`${this.config.apiBaseUrl}/admin/roles`);
  }

  lock(userId: string, request: AdminUserActionRequest): Observable<AdminUserDetail> {
    return this.http.post<AdminUserDetail>(`${this.baseUrl}/${encodeURIComponent(userId)}/lock`, request);
  }

  unlock(userId: string, request: AdminUserActionRequest): Observable<AdminUserDetail> {
    return this.http.post<AdminUserDetail>(`${this.baseUrl}/${encodeURIComponent(userId)}/unlock`, request);
  }

  updateRole(userId: string, request: UpdateAdminUserRoleRequest): Observable<AdminUserDetail> {
    return this.http.put<AdminUserDetail>(`${this.baseUrl}/${encodeURIComponent(userId)}/role`, request);
  }
}
