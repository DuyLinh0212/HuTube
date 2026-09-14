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

  getUsers(page = 1, pageSize = 10, search = '', role = 'ALL', status = 'ALL'): Observable<AdminUsersResponse> {
    let params = new HttpParams().set('page', page).set('pageSize', pageSize);
    if (search.trim()) params = params.set('search', search.trim());
    if (role !== 'ALL') params = params.set('role', role);
    if (status !== 'ALL') params = params.set('status', status);
    return this.http.get<AdminUsersResponse>(this.baseUrl, { params });
  }

  getUser(userId: string): Observable<AdminUserDetail> {
    return this.http.get<AdminUserDetail>(`${this.baseUrl}/${encodeURIComponent(userId)}`);
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
