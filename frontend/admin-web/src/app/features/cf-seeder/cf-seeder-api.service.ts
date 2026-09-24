import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { RuntimeConfig } from '../../core/runtime-config';
import {
  CfSeedAccount,
  CfSeedAccountInput,
  CfSeedProvisionResponse,
  CfSeedVideoProcessingResponse,
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
  sourceWidth: number;
  sourceHeight: number;
  description?: string;
  sequence: number;
  useExistingAccount: boolean;
  file: File;
}

export interface UploadCfSeedRenditionRequest {
  quality: string;
  width: number;
  height: number;
  bitrateKbps?: number;
  codec?: string;
  file: File;
}

export interface CfSeedRenditionResponse {
  videoId: string;
  quality: string;
  width: number;
  height: number;
  fileSize: number;
  status: string;
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
    form.append('sourceWidth', String(request.sourceWidth));
    form.append('sourceHeight', String(request.sourceHeight));
    if (request.description) form.append('description', request.description);
    form.append('sequence', String(request.sequence));
    form.append('useExistingAccount', String(request.useExistingAccount));
    form.append('video', request.file, request.file.name);
    return this.http.post<CfSeedVideoResponse>(
      `${this.config.apiBaseUrl}/admin/cf-seeder/videos`,
      form,
    );
  }

  uploadRendition(videoId: string, request: UploadCfSeedRenditionRequest): Observable<CfSeedRenditionResponse> {
    const form = new FormData();
    form.append('quality', request.quality);
    form.append('width', String(request.width));
    form.append('height', String(request.height));
    if (request.bitrateKbps !== undefined) form.append('bitrateKbps', String(request.bitrateKbps));
    if (request.codec) form.append('codec', request.codec);
    form.append('video', request.file, request.file.name);
    return this.http.post<CfSeedRenditionResponse>(
      `${this.config.apiBaseUrl}/admin/cf-seeder/videos/${videoId}/renditions`,
      form,
    );
  }

  getVideoProcessing(videoId: string): Observable<CfSeedVideoProcessingResponse> {
    return this.http.get<CfSeedVideoProcessingResponse>(
      `${this.config.apiBaseUrl}/admin/cf-seeder/videos/${videoId}/processing`,
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

  completeChunkedRenditionUpload(uploadId: string, videoId: string,
    request: Omit<UploadCfSeedRenditionRequest, 'file'>): Observable<CfSeedRenditionResponse> {
    return this.http.post<CfSeedRenditionResponse>(
      `${this.config.apiBaseUrl}/admin/cf-seeder/upload-sessions/${uploadId}/complete-rendition`,
      { videoId, ...request },
    );
  }
}
