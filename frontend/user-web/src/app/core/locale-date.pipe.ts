import { DatePipe, registerLocaleData } from '@angular/common';
import localeVi from '@angular/common/locales/vi';
import { Pipe, PipeTransform, inject } from '@angular/core';
import { I18nService } from './i18n.service';

registerLocaleData(localeVi, 'vi-VN');

@Pipe({
  name: 'localeDate',
  standalone: true,
  pure: false,
})
export class LocaleDatePipe implements PipeTransform {
  private readonly i18n = inject(I18nService);
  private readonly datePipe = new DatePipe('en-US');

  transform(
    value: string | number | Date | null | undefined,
    format = 'mediumDate',
    timezone?: string,
  ): string | null {
    return this.datePipe.transform(value, format, timezone, this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US');
  }
}
