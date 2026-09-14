import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { RuntimeConfig } from '../../core/runtime-config';
import { Observable } from 'rxjs';
import { PolicyItem } from '../moderation/admin-moderation.service';

export interface CreatePolicyRequest {
  code: string;
  name: string;
  group: string;
  content: string;
  severity: string;
  version?: string;
  status?: string;
}

export interface UpdatePolicyRequest {
  name: string;
  group: string;
  content: string;
  severity: string;
  status: string;
  version?: string;
}

@Injectable({ providedIn: 'root' })
export class AdminPoliciesService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);

  getAdminPolicies(group?: string, status?: string): Observable<PolicyItem[]> {
    let params = new HttpParams();
    if (group && group !== 'ALL') {
      params = params.set('group', group);
    }
    if (status && status !== 'ALL') {
      params = params.set('status', status);
    }

    return this.http.get<PolicyItem[]>(`${this.config.apiBaseUrl}/admin/policies`, { params });
  }

  createPolicy(request: CreatePolicyRequest): Observable<PolicyItem> {
    return this.http.post<PolicyItem>(`${this.config.apiBaseUrl}/admin/policies`, request);
  }

  publishPolicy(policyId: string, request?: UpdatePolicyRequest): Observable<PolicyItem> {
    return this.http.put<PolicyItem>(`${this.config.apiBaseUrl}/admin/policies/${policyId}/publish`, request || {});
  }
}
