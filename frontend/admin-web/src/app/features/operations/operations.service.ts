import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { RuntimeConfig } from '../../core/runtime-config';

export interface SystemSignal {
  key: string;
  category: 'runtime' | 'security' | 'moderation' | 'payments' | string;
  severity: 'normal' | 'warning' | 'critical' | string;
  title: string;
  description: string;
  currentValue: number;
  unit: string;
  threshold: number;
  actionUrl: string | null;
  isTriggered: boolean;
}

export interface RuntimeSetting { name: string; value: string; source: string; }
export interface SystemOverview {
  sampledAt: string;
  activeAlertCount: number;
  criticalAlertCount: number;
  signals: SystemSignal[];
  runtimeSettings: RuntimeSetting[];
}

export interface SystemMetric { total: number; inPeriod: number; }
export interface RevenueMetric { total: number; transactionsTotal: number; inPeriod: number; transactionsInPeriod: number; }
export interface ReportDay { date: string; newUsers: number; newVideos: number; views: number; comments: number; revenue: number; }
export interface ReportSlice { key: string; count: number; }
export interface SystemReport {
  generatedAt: string;
  days: number;
  users: SystemMetric;
  verifiedUsers: SystemMetric;
  videos: SystemMetric;
  publishedVideos: SystemMetric;
  channels: SystemMetric;
  views: SystemMetric;
  comments: SystemMetric;
  likes: SystemMetric;
  subscribers: SystemMetric;
  reports: SystemMetric;
  pendingReports: SystemMetric;
  pendingReviews: SystemMetric;
  pendingAppeals: SystemMetric;
  activeSessions: SystemMetric;
  shares: SystemMetric;
  revenue: RevenueMetric;
  daily: ReportDay[];
  videoStatuses: ReportSlice[];
  reportStatuses: ReportSlice[];
  paymentMethods: ReportSlice[];
}

export interface AuditLogItem {
  auditLogId: string;
  actorUserId: string | null;
  actorName: string | null;
  actorEmail: string | null;
  action: string;
  resourceType: string | null;
  resourceId: string | null;
  reason: string | null;
  ipAddress: string | null;
  userAgent: string | null;
  createdAt: string;
}

export interface AuditLogPage {
  page: number;
  pageSize: number;
  total: number;
  eventsLast24Hours: number;
  activeAdministratorsLast24Hours: number;
  loginsLast24Hours: number;
  actions: string[];
  runtimeSettings: RuntimeSetting[];
  items: AuditLogItem[];
}

export interface AuditLogQuery {
  page: number;
  pageSize: number;
  search?: string;
  action?: string;
  fromDate?: string;
  toDate?: string;
}

@Injectable({ providedIn: 'root' })
export class AdminOperationsService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);
  private readonly baseUrl = `${this.config.apiBaseUrl}/admin/operations`;

  getSystemOverview(): Observable<SystemOverview> {
    return this.http.get<SystemOverview>(`${this.baseUrl}/system`);
  }

  getReport(days: number): Observable<SystemReport> {
    return this.http.get<SystemReport>(`${this.baseUrl}/reports`, { params: { days } });
  }

  getAuditLogs(query: AuditLogQuery): Observable<AuditLogPage> {
    let params = new HttpParams().set('page', query.page).set('pageSize', query.pageSize);
    if (query.search?.trim()) params = params.set('search', query.search.trim());
    if (query.action && query.action !== 'all') params = params.set('action', query.action);
    if (query.fromDate) params = params.set('fromDate', query.fromDate);
    if (query.toDate) params = params.set('toDate', query.toDate);
    return this.http.get<AuditLogPage>(`${this.baseUrl}/audit-logs`, { params });
  }
}
