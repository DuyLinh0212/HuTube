import { HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { AuthService } from './auth.service';
import { RuntimeConfig } from './runtime-config';

interface SaveHandle { createWritable(): Promise<WritableStream<Uint8Array>>; }
type SavePicker = (options: { suggestedName: string; types: { description: string; accept: Record<string, string[]> }[] }) => Promise<SaveHandle>;

@Injectable({ providedIn: 'root' })
export class VideoDownloadService {
  private readonly auth = inject(AuthService);
  private readonly config = inject(RuntimeConfig);

  async save(videoId: string, quality: string, title: string, fileExtension = '.mp4'): Promise<'saved' | 'started' | false> {
    const extension = ['.mp4', '.webm', '.mov', '.mkv'].includes(fileExtension) ? fileExtension : '.mp4';
    const filename = `${title.replace(/[<>:"/\\|?*\x00-\x1f]/g, '').trim().slice(0, 120) || 'Dalitu'}-${quality}${extension}`;
    const picker = (window as Window & { showSaveFilePicker?: SavePicker }).showSaveFilePicker;
    let handle: SaveHandle | undefined;
    // Open while the click still has user activation, before any API request.
    if (picker) {
      try {
        handle = await picker.call(window, { suggestedName: filename,
          types: [{ description: 'Video', accept: { 'video/*': [extension] } }] });
      } catch (error) {
        if (error instanceof DOMException && error.name === 'AbortError') return false;
        throw error;
      }
    }
    const version = this.auth.sessionVersion;
    const token = await firstValueFrom(this.auth.ensureFreshAccessToken());
    const request = (accessToken: string) => fetch(`${this.config.apiBaseUrl}/videos/${encodeURIComponent(videoId)}/download-file`, {
      method: 'POST', credentials: 'include',
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json', 'X-HuTube-Client': 'web' },
      body: JSON.stringify({ quality })
    });
    let response = await request(token);
    if (response.status === 401 && version === this.auth.sessionVersion) {
      const fresh = await firstValueFrom(this.auth.refresh());
      response = await request(fresh.accessToken);
    }
    if (version !== this.auth.sessionVersion) {
      await response.body?.cancel();
      throw new Error('Session changed during download.');
    }
    if (!response.ok) {
      const error = await response.json().catch(() => ({}));
      throw new HttpErrorResponse({ status: response.status, error });
    }
    if (handle && response.body) {
      // Stream to disk rather than buffering an entire large video in memory.
      await response.body.pipeTo(await handle.createWritable());
      return 'saved';
    } else {
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 60_000);
    }
    return 'started';
  }
}
