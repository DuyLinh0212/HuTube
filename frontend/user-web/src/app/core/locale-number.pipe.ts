import { DecimalPipe } from '@angular/common';
import { Pipe, PipeTransform, inject } from '@angular/core';
import { I18nService } from './i18n.service';

@Pipe({
  name: 'localeNumber',
  standalone: true,
  pure: false,
})
export class LocaleNumberPipe implements PipeTransform {
  private readonly i18n = inject(I18nService);
  private readonly numberPipe = new DecimalPipe('en-US');

  transform(value: number | string | null | undefined, digitsInfo?: string): string | null {
    return this.numberPipe.transform(value, digitsInfo, this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US');
  }
}
