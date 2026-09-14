import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { RuntimeConfig } from '../../core/runtime-config';
import { Observable } from 'rxjs';

export interface ModerationQueueItem {
  moderationCaseId: string;
  videoId: string;
  videoTitle: string;
  videoDescription: string | null;
  videoUrl: string | null;
  thumbnailUrl: string | null;
  durationSeconds: number;
  visibility: string;
  channelId: string;
  channelName: string;
  channelAvatarUrl: string | null;
  caseType: string;
  status: 'pending' | 'reviewing' | 'resolved' | 'escalated';
  riskLevel: 'low' | 'high';
  ruleViolationsJson: string | null;
  reviewerId: string | null;
  reviewerName: string | null;
  submittedAt: string;
  claimedAt: string | null;
  reviewedAt: string | null;
  decision: string | null;
  internalNote: string | null;
}

export interface ResolveModerationRequest {
  decision: 'Approve' | 'AgeRestricted' | 'RecommendationRestricted' | 'Reject' | 'Escalate';
  policyCode?: string;
  policyVersion?: string;
  reason?: string;
  internalNote?: string;
  actionReason?: string;
}

export interface ModerationDecisionResponse {
  caseId: string;
  videoId: string;
  status: string;
  decision: string;
  resolvedAt: string;
  message: string;
}

export interface PolicyItem {
  policyId: string;
  code: string;
  name: string;
  group: string;
  content: string;
  severity: string;
  version: string;
  status: string;
  effectiveAt: string;
}

@Injectable({ providedIn: 'root' })
export class AdminModerationService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);

  getQueue(status?: string, riskLevel?: string, page = 1, pageSize = 50): Observable<ModerationQueueItem[]> {
    let params = new HttpParams()
      .set('page', page.toString())
      .set('pageSize', pageSize.toString());

    if (status && status !== 'ALL') {
      params = params.set('status', status);
    }
    if (riskLevel && riskLevel !== 'ALL') {
      params = params.set('riskLevel', riskLevel);
    }

    return this.http.get<ModerationQueueItem[]>(`${this.config.apiBaseUrl}/admin/moderation/queue`, { params });
  }

  claim(caseId: string): Observable<{ message: string }> {
    return this.http.post<{ message: string }>(`${this.config.apiBaseUrl}/admin/moderation/${caseId}/claim`, {});
  }

  release(caseId: string): Observable<{ message: string }> {
    return this.http.post<{ message: string }>(`${this.config.apiBaseUrl}/admin/moderation/${caseId}/release`, {});
  }

  resolve(caseId: string, request: ResolveModerationRequest): Observable<ModerationDecisionResponse> {
    return this.http.post<ModerationDecisionResponse>(`${this.config.apiBaseUrl}/admin/moderation/${caseId}/resolve`, request);
  }

  getPolicies(): Observable<PolicyItem[]> {
    return this.http.get<PolicyItem[]>(`${this.config.apiBaseUrl}/policies`);
  }
}
