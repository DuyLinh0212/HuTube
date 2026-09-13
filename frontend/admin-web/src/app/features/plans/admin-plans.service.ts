import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { RuntimeConfig } from '../../core/runtime-config';

export interface AdminPlan {
  planId: string;
  code: string;
  name: string;
  description: string | null;
  price: number;
  durationDays: number;
  storageLimit: number;
  maxUploadSize: number;
  maxVideoDuration: number;
  maxVideoQuality: string | null;
  maxDownloadQuality?: string | null;
  maxMembers: number;
  status: string;
  features?: Record<string, boolean>;
  displayOrder?: number;
}

export interface SavePlanRequest {
  code?: string;
  name: string;
  description: string;
  price: number;
  durationDays: number;
  storageLimit: number;
  maxUploadSize: number;
  maxVideoDuration: number;
  maxVideoQuality: string;
  maxDownloadQuality?: string;
  maxMembers: number;
  status?: string;
  features?: string;
  displayOrder?: number;
}

@Injectable({ providedIn: 'root' })
export class AdminPlansService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);
  private readonly base = this.config.apiBaseUrl + '/admin/plans';

  plans() { return this.http.get<AdminPlan[]>(this.base); }
  createPlan(request: SavePlanRequest) { return this.http.post<AdminPlan>(this.base, request); }
  updatePlan(planId: string, request: SavePlanRequest) { return this.http.put<AdminPlan>(`${this.base}/${planId}`, request); }
  archivePlan(planId: string) { return this.http.post<void>(`${this.base}/${planId}/archive`, {}); }
}
