import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { RuntimeConfig } from '../../core/runtime-config';
import {
  CfSeedAccount,
  CfSeedAccountInput,
  CfSeedProvisionResponse,
  CfSeedVideoResponse,
  CfSeedVisibility,
} from './cf-seeder.models';

export interface UploadCfSeedVideoRequest {
  batchId: string;
  userId: string;
  channelId: string;
  categoryId: string;
  title: string;
  visibility: CfSeedVisibility;
  duration: number;
  sourceQuality: string;
  sequence: number;
  useExistingAccount: boolean;
  file: File;
}

export interface CfSeedUploadSession {
  uploadId: string;
  chunkSize: number;
}

@Injectable({ providedIn: 'root' })
export class CfSeederApiService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);

  createAccounts(accounts: CfSeedAccountInput[]): Observable<CfSeedProvisionResponse> {
    return this.http.post<CfSeedProvisionResponse>(
      `${this.config.apiBaseUrl}/admin/cf-seeder/accounts`,
      { accounts },
    );
  }

  getExistingAccounts(search = ''): Observable<CfSeedAccount[]> {
    const trimmed = search.trim();
    return this.http.get<CfSeedAccount[]>(`${this.config.apiBaseUrl}/admin/cf-seeder/users`, {
      params: trimmed ? { search: trimmed } : {},
    });
  }

  uploadVideo(request: UploadCfSeedVideoRequest): Observable<CfSeedVideoResponse> {
    const form = new FormData();
    form.append('batchId', request.batchId);
    form.append('userId', request.userId);
    form.append('channelId', request.channelId);
    form.append('categoryId', request.categoryId);
    form.append('title', request.title);
    form.append('visibility', request.visibility);
    form.append('duration', String(request.duration));
    form.append('sourceQuality', request.sourceQuality);
    form.append('sequence', String(request.sequence));
    form.append('useExistingAccount', String(request.useExistingAccount));
    form.append('video', request.file, request.file.name);
    return this.http.post<CfSeedVideoResponse>(
      `${this.config.apiBaseUrl}/admin/cf-seeder/videos`,
      form,
    );
  }

  startChunkedUpload(uploadId: string, file: File, totalChunks: number): Observable<CfSeedUploadSession> {
    return this.http.post<CfSeedUploadSession>(`${this.config.apiBaseUrl}/admin/cf-seeder/upload-sessions`, {
      uploadId,
      fileName: file.name,
      contentType: file.type,
      fileSize: file.size,
      totalChunks,
    });
  }

  uploadChunk(uploadId: string, chunkIndex: number, chunk: Blob): Observable<{ nextChunk: number }> {
    const form = new FormData();
    form.append('chunk', chunk, `chunk-${chunkIndex}.bin`);
    return this.http.post<{ nextChunk: number }>(
      `${this.config.apiBaseUrl}/admin/cf-seeder/upload-sessions/${uploadId}/chunks/${chunkIndex}`,
      form,
    );
  }

  completeChunkedUpload(uploadId: string, request: Omit<UploadCfSeedVideoRequest, 'file'>): Observable<CfSeedVideoResponse> {
    return this.http.post<CfSeedVideoResponse>(
      `${this.config.apiBaseUrl}/admin/cf-seeder/upload-sessions/${uploadId}/complete`,
      request,
    );
  }
}
