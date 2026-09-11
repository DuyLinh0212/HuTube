import { Component, inject } from '@angular/core';
import { UploadStateService } from '../../core/upload-state.service';

@Component({
  selector: 'app-upload-progress-tray',
  template: `
    @if (isVisible()) {
      <aside class="upload-tray" role="status" aria-live="polite">
        <div class="tray-heading">
          <div>
            <strong>{{ label() }}</strong>
            <span class="tray-file" [title]="upload.state().fileName">{{ upload.state().fileName }}</span>
          </div>
          @if (isActive()) {
            <button type="button" class="tray-cancel" (click)="upload.cancel()">Hủy</button>
          } @else {
            <button type="button" class="tray-close" aria-label="Đóng" (click)="upload.reset()">×</button>
          }
        </div>
        <div class="tray-progress" aria-hidden="true">
          <span [style.width.%]="upload.state().progress"></span>
        </div>
        <div class="tray-meta">
          <span>{{ upload.state().progress }}%</span>
          @if (isActive() && upload.state().total > 0) {
            <span>{{ bytes(upload.state().loaded) }} / {{ bytes(upload.state().total) }}</span>
          }
        </div>
        @if (upload.state().error) { <p class="tray-error">{{ upload.state().error }}</p> }
      </aside>
    }
  `,
  styles: [`
    :host { position: fixed; right: 24px; bottom: 24px; z-index: 1200; }
    .upload-tray { width: min(380px, calc(100vw - 32px)); padding: 16px; border: 1px solid var(--line, #e5e7eb); border-radius: 14px; background: var(--surface, #fff); color: var(--ink, #111827); box-shadow: 0 12px 40px rgba(15, 23, 42, .18); }
    .tray-heading, .tray-meta { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
    .tray-heading > div { min-width: 0; display: grid; gap: 4px; }
    .tray-file { overflow: hidden; color: var(--text-muted, #64748b); font-size: 12px; text-overflow: ellipsis; white-space: nowrap; }
    .tray-progress { height: 8px; margin: 14px 0 8px; overflow: hidden; border-radius: 999px; background: var(--line, #e5e7eb); }
    .tray-progress span { display: block; height: 100%; border-radius: inherit; background: var(--primary, #f72562); transition: width 180ms ease; }
    .tray-meta { color: var(--text-muted, #64748b); font-size: 12px; }
    .tray-cancel, .tray-close { border: 0; background: transparent; color: var(--primary, #f72562); cursor: pointer; font-weight: 700; }
    .tray-close { color: var(--text-muted, #64748b); font-size: 20px; line-height: 1; }
    .tray-error { margin: 10px 0 0; color: #b91c1c; font-size: 12px; }
    @media (max-width: 640px) { :host { right: 16px; bottom: 16px; } }
  `]
})
export class UploadProgressTrayComponent {
  readonly upload = inject(UploadStateService);

  isVisible() { return this.upload.state().phase !== 'idle'; }
  isActive() { return this.upload.state().phase === 'uploading' || this.upload.state().phase === 'processing'; }
  label() {
    return this.upload.state().phase === 'uploading' ? 'Đang tải video lên…'
      : this.upload.state().phase === 'processing' ? 'Đang tạo chất lượng video…'
      : this.upload.state().phase === 'completed' ? 'Tải video thành công'
      : 'Tải video thất bại';
  }
  bytes(value: number) {
    if (value < 1024) return `${value} B`;
    const units = ['KB', 'MB', 'GB', 'TB'];
    let size = value; let index = -1;
    do { size /= 1024; index++; } while (size >= 1024 && index < units.length - 1);
    return `${size.toFixed(size >= 10 ? 0 : 1)} ${units[index]}`;
  }
}
