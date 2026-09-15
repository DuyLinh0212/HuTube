import { HttpEventType, HttpResponse } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import { Subscription } from 'rxjs';
import { ContentService, VideoDetail } from './content.service';
import { I18nService } from './i18n.service';

export type UploadPhase = 'idle' | 'uploading' | 'processing' | 'completed' | 'failed';

export interface UploadState {
  phase: UploadPhase;
  progress: number;
  loaded: number;
  total: number;
  fileName: string;
  video: VideoDetail | null;
  error: string;
}

const initialState = (): UploadState => ({
  phase: 'idle', progress: 0, loaded: 0, total: 0, fileName: '', video: null, error: ''
});

@Injectable({ providedIn: 'root' })
export class UploadStateService {
  private readonly content = inject(ContentService);
  private readonly i18n = inject(I18nService);
  private request?: Subscription;
  private idempotencyKey?: string;
  readonly state = signal<UploadState>(initialState());

  start(data: FormData, fileName: string, publishUnlisted: boolean): boolean {
    const current = this.state().phase;
    if (current === 'uploading' || current === 'processing') return false;

    const total = this.findFileSize(data);
    if (!this.idempotencyKey || current === 'idle') this.idempotencyKey = crypto.randomUUID();
    this.state.set({ ...initialState(), phase: 'uploading', progress: 1, total, fileName });
    this.request = this.content.upload(data, this.idempotencyKey).subscribe({
      next: event => {
        if (event.type === HttpEventType.UploadProgress) {
          const loaded = event.loaded;
          const knownTotal = event.total ?? total;
          const ratio = knownTotal > 0 ? loaded / knownTotal : 0;
          const progress = Math.max(this.state().progress, Math.min(90, Math.round(ratio * 90)));
          this.state.update(value => ({ ...value, phase: ratio >= 0.999 ? 'processing' : 'uploading', progress: Math.max(1, progress), loaded, total: knownTotal }));
          return;
        }
        if (event.type !== HttpEventType.Response) return;
        const response = event as HttpResponse<VideoDetail>;
        if (!response.body) {
          this.fail(this.i18n.t('upload.serverNoVideo'));
          return;
        }
        this.state.update(value => ({ ...value, phase: 'processing', progress: 95, video: response.body, error: '' }));
        if (publishUnlisted && response.body.visibility === 'unlisted') {
          this.content.publish(response.body.videoId).subscribe({
            next: video => this.finish(video),
            error: error => this.fail(this.readError(error), response.body)
          });
        } else {
          this.finish(response.body);
        }
      },
      error: error => this.fail(this.readError(error)),
      complete: () => { this.request = undefined; }
    });
    return true;
  }

  cancel() {
    this.request?.unsubscribe();
    this.request = undefined;
    this.idempotencyKey = undefined;
    this.state.set(initialState());
  }

  reset() {
    this.request?.unsubscribe();
    this.request = undefined;
    this.idempotencyKey = undefined;
    this.state.set(initialState());
  }

  private finish(video: VideoDetail) {
    this.idempotencyKey = undefined;
    this.state.update(value => ({ ...value, phase: 'completed', progress: 100, video, error: '' }));
  }

  private fail(message: string, video: VideoDetail | null = null) {
    this.state.update(value => ({ ...value, phase: 'failed', video, error: message }));
    this.request = undefined;
  }

  private findFileSize(data: FormData): number {
    const value = data.get('Video');
    return value instanceof File ? value.size : 0;
  }

  private readError(_error: any): string {
    return this.i18n.t('upload.uploadError');
  }
}
