import { Component, inject } from '@angular/core';
import { UploadStateService } from '../../core/upload-state.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-upload-progress-tray',
  imports: [LocaleNumberPipe, TranslatePipe],
  templateUrl: './upload-progress-tray.component.html',
  styleUrl: './upload-progress-tray.component.scss',
})
export class UploadProgressTrayComponent {
  readonly upload = inject(UploadStateService);
  readonly i18n = inject(I18nService);

  isVisible() {
    return this.upload.state().phase !== 'idle';
  }

  isActive() {
    return this.upload.state().phase === 'uploading' || this.upload.state().phase === 'processing';
  }

  label() {
    return this.upload.state().phase === 'uploading'
      ? this.i18n.t('ui.uploading')
      : this.upload.state().phase === 'processing'
        ? this.i18n.t('ui.processingVideo')
        : this.upload.state().phase === 'completed'
          ? this.i18n.t('ui.uploadSuccess')
          : this.i18n.t('ui.uploadFailed');
  }

  bytes(value: number) {
    if (value < 1024) return this.i18n.formatNumber(value, { useGrouping: false }) + ' B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    let size = value;
    let index = -1;
    do {
      size /= 1024;
      index++;
    } while (size >= 1024 && index < units.length - 1);
    return this.i18n.formatNumber(size, { maximumFractionDigits: size >= 10 ? 0 : 1 }) + ' ' + units[index];
  }
}
