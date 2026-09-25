import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { RuntimeConfig } from '../../core/runtime-config';
import { Observable } from 'rxjs';

export type ModerationDecision =
  | 'approve'
  | 'age_restricted'
  | 'recommendation_restricted'
  | 'reject'
  | 'escalate';

export interface ModerationQueueItem {
  moderationCaseId: string;
  videoId: string;
  title: string;
  description: string | null;
  videoUrl: string;
  thumbnailUrl: string | null;
  duration: number;
  channelId: string;
  channelName: string;
  channelHandle: string | null;
  channelAvatarUrl: string | null;
  categoryName: string | null;
  caseType: string;
  status: 'pending' | 'reviewing' | 'approved' | 'rejected' | 'resolved' | 'escalated';
  riskLevel: 'low' | 'high';
  reviewerId: string | null;
  reviewerName: string | null;
  submittedAt: string;
  claimedAt: string | null;
  note: string | null;
}

export interface ResolveModerationRequest {
  decision: ModerationDecision;
  policyCode?: string;
  reason?: string;
  internalNote?: string;
}

export interface ModerationDecisionResponse {
  moderationCaseId: string;
  videoId: string;
  status: string;
  decision: string;
  policyCode: string | null;
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

export interface ReportItem {
  reportId: string;
  userId: string;
  reporterName: string | null;
  targetType: 'video' | 'comment' | 'channel';
  targetId: string;
  targetTitle: string | null;
  violationTypeId: string;
  violationTypeCode: string | null;
  violationTypeName: string | null;
  description: string;
  status: string;
  reviewerId: string | null;
  reviewerName: string | null;
  createdAt: string;
  updatedAt: string;
  targetUrl?: string | null;
  targetThumbnailUrl?: string | null;
  targetChannelName?: string | null;
  targetChannelHandle?: string | null;
  contextText?: string | null;
  disposition?: string | null;
  abuseFlag?: boolean;
}

export interface ReportViolationCount { code: string | null; name: string | null; count: number; }
export interface ReportCaseSummary {
  caseId: string; targetType: 'video' | 'comment' | 'channel'; targetId: string; targetTitle: string | null;
  targetUrl: string | null; targetThumbnailUrl: string | null; targetChannelName: string | null; targetChannelHandle: string | null;
  status: string; reportCount: number; reporterCount: number; unclassifiedCount: number; violationCounts: ReportViolationCount[];
  reviewerId: string | null; reviewerName: string | null; submittedAt: string; updatedAt: string;
}
export interface ReportCaseReportDetail {
  reportId: string; userId: string; reporterName: string | null; violationTypeId: string; violationTypeCode: string | null;
  violationTypeName: string | null; description: string; status: string; disposition: string | null; dispositionReason: string | null;
  dispositionByUserId: string | null; dispositionAt: string | null; abuseFlag: boolean; createdAt: string; updatedAt: string;
}
export interface ReportCaseDetail { case: ReportCaseSummary; reports: ReportCaseReportDetail[]; }
export interface UpdateReportDispositionsRequest { reportIds: string[]; disposition: 'accepted' | 'rejected'; reason: string; }
export interface ResolveReportCaseRequest { decision: string; reason: string; internalNote?: string; policyCode?: string; restrictionDays?: number; }

export interface ResolveReportRequest {
  decision: string;
  reason?: string;
  internalNote?: string;
  policyCode?: string;
}

export interface ReportResolutionResponse {
  reportId: string;
  status: string;
  decision: string;
  message: string;
}

export interface AppealItem {
  appealId: string;
  userId: string;
  userName: string | null;
  targetType: string;
  targetId: string;
  targetTitle: string | null;
  appealNumber: number;
  reviewerId: string | null;
  reviewerName: string | null;
  reason: string;
  status: string;
  reviewNote: string | null;
  evidenceUrl: string | null;
  evidenceNote: string | null;
  moderationCaseId: string | null;
  strikeId: string | null;
  createdAt: string;
  resolvedAt: string | null;
}

export interface ResolveAppealRequest {
  decision: 'approve' | 'reject' | 'escalate';
  reviewNote?: string;
}

export interface AppealResolutionResponse {
  appealId: string;
  status: string;
  decision: string;
  message: string;
}

export interface StrikeItem {
  strikeId: string;
  channelId: string;
  channelName: string | null;
  userId: string;
  strikeNumber: number;
  severity: string;
  policyCode: string | null;
  reason: string;
  internalNote: string | null;
  status: string;
  expiresAt: string;
  createdAt: string;
  revokedAt: string | null;
  revokedByUserId: string | null;
  revocationReason: string | null;
  channelHandle?: string | null;
  channelStatus?: string | null;
}

export interface CreateStrikeRequest {
  channelId: string;
  policyCode?: string;
  severity: string;
  reason: string;
  internalNote?: string;
}

export interface RevokeStrikeRequest {
  reason: string;
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

  // Reports
  getReports(targetType?: string, status?: string, page = 1, pageSize = 50): Observable<ReportItem[]> {
    let params = new HttpParams().set('page', page.toString()).set('pageSize', pageSize.toString());
    if (targetType && targetType !== 'ALL') params = params.set('targetType', targetType);
    if (status && status !== 'ALL') params = params.set('status', status);
    return this.http.get<ReportItem[]>(`${this.config.apiBaseUrl}/admin/reports`, { params });
  }

  getReportCases(targetType?: string, status?: string, page = 1, pageSize = 50) {
    let params = new HttpParams().set('page', page).set('pageSize', pageSize);
    if (targetType && targetType !== 'ALL') params = params.set('targetType', targetType);
    if (status && status !== 'ALL') params = params.set('status', status);
    return this.http.get<{ items: ReportCaseSummary[]; page: number; pageSize: number; total: number }>(`${this.config.apiBaseUrl}/admin/reports/cases`, { params });
  }

  getReportCase(caseId: string) { return this.http.get<ReportCaseDetail>(`${this.config.apiBaseUrl}/admin/reports/cases/${caseId}`); }
  claimReportCase(caseId: string): Observable<void> { return this.http.post<void>(`${this.config.apiBaseUrl}/admin/reports/cases/${caseId}/claim`, {}); }
  releaseReportCase(caseId: string): Observable<void> { return this.http.post<void>(`${this.config.apiBaseUrl}/admin/reports/cases/${caseId}/release`, {}); }
  updateReportDispositions(caseId: string, request: UpdateReportDispositionsRequest): Observable<void> {
    return this.http.post<void>(`${this.config.apiBaseUrl}/admin/reports/cases/${caseId}/dispositions`, request);
  }
  resolveReportCase(caseId: string, request: ResolveReportCaseRequest): Observable<ReportResolutionResponse> {
    return this.http.post<ReportResolutionResponse>(`${this.config.apiBaseUrl}/admin/reports/cases/${caseId}/resolve`, request);
  }

  claimReport(reportId: string): Observable<void> {
    return this.http.post<void>(`${this.config.apiBaseUrl}/admin/reports/${reportId}/claim`, {});
  }

  releaseReport(reportId: string): Observable<void> {
    return this.http.post<void>(`${this.config.apiBaseUrl}/admin/reports/${reportId}/release`, {});
  }

  resolveReport(reportId: string, request: ResolveReportRequest): Observable<ReportResolutionResponse> {
    return this.http.post<ReportResolutionResponse>(`${this.config.apiBaseUrl}/admin/reports/${reportId}/resolve`, request);
  }

  // Appeals
  getAppeals(targetType?: string, status?: string, page = 1, pageSize = 50): Observable<AppealItem[]> {
    let params = new HttpParams().set('page', page.toString()).set('pageSize', pageSize.toString());
    if (targetType && targetType !== 'ALL') params = params.set('targetType', targetType);
    if (status && status !== 'ALL') params = params.set('status', status);
    return this.http.get<AppealItem[]>(`${this.config.apiBaseUrl}/admin/appeals`, { params });
  }

  getAppealEvidence(appealId: string): Observable<Blob> {
    return this.http.get(`${this.config.apiBaseUrl}/admin/appeals/${appealId}/evidence`, { responseType: 'blob' });
  }

  claimAppeal(appealId: string): Observable<void> {
    return this.http.post<void>(`${this.config.apiBaseUrl}/admin/appeals/${appealId}/claim`, {});
  }

  releaseAppeal(appealId: string): Observable<void> {
    return this.http.post<void>(`${this.config.apiBaseUrl}/admin/appeals/${appealId}/release`, {});
  }

  resolveAppeal(appealId: string, request: ResolveAppealRequest): Observable<AppealResolutionResponse> {
    return this.http.post<AppealResolutionResponse>(`${this.config.apiBaseUrl}/admin/appeals/${appealId}/resolve`, request);
  }

  // Strikes
  getStrikes(channelId?: string, status?: string, page = 1, pageSize = 50): Observable<StrikeItem[]> {
    let params = new HttpParams().set('page', page.toString()).set('pageSize', pageSize.toString());
    if (channelId) params = params.set('channelId', channelId);
    if (status && status !== 'ALL') params = params.set('status', status);
    return this.http.get<StrikeItem[]>(`${this.config.apiBaseUrl}/admin/strikes`, { params });
  }

  createStrike(request: CreateStrikeRequest): Observable<StrikeItem> {
    return this.http.post<StrikeItem>(`${this.config.apiBaseUrl}/admin/strikes`, request);
  }

  revokeStrike(strikeId: string, request: RevokeStrikeRequest): Observable<StrikeItem> {
    return this.http.post<StrikeItem>(`${this.config.apiBaseUrl}/admin/strikes/${strikeId}/revoke`, request);
  }

  // Channel Lock / Unlock
  lockChannel(channelId: string, reason: string): Observable<void> {
    return this.http.post<void>(`${this.config.apiBaseUrl}/admin/channels/${channelId}/lock`, { reason });
  }

  unlockChannel(channelId: string, reason: string): Observable<void> {
    return this.http.post<void>(`${this.config.apiBaseUrl}/admin/channels/${channelId}/unlock`, { reason });
  }
}

