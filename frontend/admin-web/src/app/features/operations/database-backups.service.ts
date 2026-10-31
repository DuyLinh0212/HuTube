import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { RuntimeConfig } from '../../core/runtime-config';

export interface DatabaseBackupSchedule {
  enabled: boolean;
  frequency: 'daily' | 'weekly' | string;
  dayOfWeek: number | null;
  time: string;
  timeZoneId: string;
  nextRunAt: string | null;
  lastRunAt: string | null;
  updatedAt: string;
}

export interface DatabaseBackupRun {
  runId: string;
  trigger: 'manual' | 'schedule' | string;
  status: 'queued' | 'running' | 'succeeded' | 'failed' | string;
  createdAt: string;
  startedAt: string | null;
  completedAt: string | null;
  fileName: string | null;
  sizeBytes: number | null;
  errorMessage: string | null;
  canDownload: boolean;
}

export interface DatabaseBackupOverview {
  schedule: DatabaseBackupSchedule;
  activeRun: DatabaseBackupRun | null;
  runs: DatabaseBackupRun[];
  storageConfigured: boolean;
}

export interface DatabaseBackupScheduleUpdate {
  enabled: boolean;
  frequency: 'daily' | 'weekly';
  dayOfWeek: number | null;
  time: string;
}

@Injectable({ providedIn: 'root' })
export class DatabaseBackupsService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);
  private readonly baseUrl = () => `${this.config.apiBaseUrl}/admin/database-backups`;

  getOverview(fromDate: string, toDate: string): Observable<DatabaseBackupOverview> {
    const params = new HttpParams().set('fromDate', fromDate).set('toDate', toDate);
    return this.http.get<DatabaseBackupOverview>(this.baseUrl(), { params });
  }

  updateSchedule(request: DatabaseBackupScheduleUpdate): Observable<DatabaseBackupSchedule> {
    return this.http.put<DatabaseBackupSchedule>(`${this.baseUrl()}/schedule`, request);
  }

  runNow(): Observable<DatabaseBackupRun> {
    return this.http.post<DatabaseBackupRun>(`${this.baseUrl()}/runs`, {});
  }

  getDownloadUrl(runId: string): Observable<{ url: string }> {
    return this.http.get<{ url: string }>(`${this.baseUrl()}/runs/${encodeURIComponent(runId)}/download-url`);
  }
}
