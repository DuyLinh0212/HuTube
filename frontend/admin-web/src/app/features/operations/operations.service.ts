import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';
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
  apiTraffic: ApiTrafficOverview;
  liveMetrics: SystemLiveMetrics;
  services: SystemServiceStatus[];
  r2StorageUsage?: R2StorageUsage | null;
}

export interface R2StorageUsage {
  status: 'available' | 'unmonitored' | 'error' | string;
  bucketName: string;
  totalSizeBytes: number | null;
  payloadSizeBytes: number | null;
  metadataSizeBytes: number | null;
  objectCount: number | null;
  pendingUploadCount: number | null;
  sampledAt: string | null;
  detail: string;
}

export interface ApiTrafficBucket {
  bucketStart: string;
  isObserved: boolean;
  requests: number | null;
  clientErrors: number | null;
  serverErrors: number | null;
}

export interface ApiTrafficOverview {
  collectedSince: string;
  requestsThisMinute: number;
  requestsLast15Minutes: number;
  clientErrorsLast15Minutes: number;
  serverErrorsLast15Minutes: number;
  rateLimitedLast15Minutes: number;
  clientErrorRateLast15Minutes: number;
  serverErrorRateLast15Minutes: number;
  averageLatencyMsLast15Minutes: number | null;
  p95LatencyMsLast15Minutes: number | null;
  hourly: ApiTrafficBucket[];
}

export interface SystemLiveMetrics {
  activeSessions: number;
  pendingPayments: number;
  expiredPendingPayments: number;
  failedPaymentsLast24Hours: number;
  videosProcessing: number;
  failedVideosLast24Hours: number;
  renditionsProcessing: number;
  failedRenditionsLast24Hours: number;
  pendingVideoReviews: number;
  activeSignalRConnections: number;
}

export interface SystemServiceStatus {
  key: string;
  status: string;
  detail: string;
  responseTimeMs: number | null;
}

function canonicalFieldName(value: string): string {
  return value.replace(/[^a-z0-9]/gi, '').toLowerCase();
}

function readField(record: Record<string, unknown>, aliases: string[]): unknown {
  const wanted = new Set(aliases.map(canonicalFieldName));
  const entry = Object.entries(record).find(([key]) => wanted.has(canonicalFieldName(key)));
  return entry?.[1];
}

function normalizeServiceKey(value: unknown, index: number): string {
  if (typeof value !== 'string' || !value.trim()) return `service-${index + 1}`;
  const original = value.trim();
  const compact = canonicalFieldName(original);
  const aliases: Record<string, string> = {
    api: 'api', backend: 'api', backendapi: 'api',
    database: 'database', db: 'database', neon: 'database', neondatabase: 'database', neonpostgresql: 'database', postgres: 'database', postgresql: 'database',
    redis: 'redis', upstash: 'redis', upstashredis: 'redis', redisupstash: 'redis',
    vercel: 'vercel', vercelfrontend: 'vercel', render: 'render', renderbackend: 'render',
    storage: 'storage', r2: 'storage', cloudflarer2: 'storage', cloudflarer2storage: 'storage', cloudflarestorage: 'storage',
    signalr: 'signalr',
  };
  return aliases[compact] ?? original;
}

function normalizeServiceStatus(value: unknown): string {
  if (typeof value !== 'string' || !value.trim()) return 'unmonitored';
  const status = canonicalFieldName(value);
  if (['healthy', 'ok', 'operational', 'up', 'none'].includes(status)) return 'healthy';
  if (['warning', 'degraded', 'degradedperformance', 'partialoutage', 'maintenance', 'minor'].includes(status)) return 'warning';
  if (['error', 'unhealthy', 'down', 'unavailable', 'failed', 'majoroutage', 'critical', 'outage'].includes(status)) return 'error';
  if (['unmonitored', 'notmonitored', 'notconfigured', 'disabled', 'unknown', 'checking'].includes(status)) return 'unmonitored';
  return 'unmonitored';
}

function normalizeSystemService(value: unknown, index: number): SystemServiceStatus {
  const record = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const key = normalizeServiceKey(readField(record, ['key', 'serviceKey', 'providerKey', 'service', 'provider', 'name', 'serviceName']), index);
  const rawStatus = readField(record, ['status', 'state', 'health', 'healthStatus', 'indicator']);
  const detail = readField(record, ['detail', 'description', 'message', 'healthMessage', 'statusText']);
  const rawResponseTime = readField(record, ['responseTimeMs', 'latencyMs', 'responseTime', 'latency']);
  const parsedResponseTime = typeof rawResponseTime === 'number'
    ? rawResponseTime
    : typeof rawResponseTime === 'string' ? Number(rawResponseTime) : null;
  return {
    key,
    status: normalizeServiceStatus(rawStatus),
    detail: typeof detail === 'string' && detail.trim() ? detail.trim() : 'API chưa gửi mô tả cho dịch vụ này.',
    responseTimeMs: parsedResponseTime != null && Number.isFinite(parsedResponseTime) ? parsedResponseTime : null,
  };
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
    return this.http.get<SystemOverview>(`${this.baseUrl}/system`).pipe(map(overview => ({
      ...overview,
      services: Array.isArray((overview as { services?: unknown }).services)
        ? ((overview as { services: unknown[] }).services).map(normalizeSystemService)
        : [],
    })));
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
