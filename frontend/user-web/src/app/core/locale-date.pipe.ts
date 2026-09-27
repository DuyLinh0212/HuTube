import { DatePipe } from '@angular/common';
import { Pipe, PipeTransform, inject } from '@angular/core';
import { I18nService } from './i18n.service';

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
