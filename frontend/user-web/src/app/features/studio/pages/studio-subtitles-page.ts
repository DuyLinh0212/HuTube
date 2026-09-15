import { Component, OnInit, inject } from '@angular/core';
import { I18nService } from '../../../core/i18n.service';
import { LocaleNumberPipe } from '../../../core/locale-number.pipe';
import { StudioDataService } from '../../../core/studio-data.service';
import { TranslatePipe } from '../../../core/translate.pipe';

@Component({
  selector: 'app-studio-subtitles-page',
  imports: [LocaleNumberPipe, TranslatePipe],
  templateUrl: './studio-subtitles-page.html',
  styleUrl: './studio-subtitles-page.scss',
})
export class StudioSubtitlesPage implements OnInit {
  readonly data = inject(StudioDataService);
  readonly i18n = inject(I18nService);

  languageLabel(value: string | null | undefined): string {
    const code = String(value || '').toLowerCase();
    if (code.startsWith('en')) return this.i18n.t('upload.languageEnglish');
    if (code.startsWith('ja')) return this.i18n.t('upload.languageJapanese');
    if (code.startsWith('vi')) return this.i18n.t('upload.languageVietnamese');
    return value || this.i18n.t('studio.notSet');
  }

  ngOnInit() {
    this.data.load();
  }
}
