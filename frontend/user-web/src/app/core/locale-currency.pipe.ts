import { CurrencyPipe } from '@angular/common';
import { Pipe, PipeTransform, inject } from '@angular/core';
import { I18nService } from './i18n.service';

@Pipe({
  name: 'localeCurrency',
  standalone: true,
  pure: false,
})
export class LocaleCurrencyPipe implements PipeTransform {
  private readonly i18n = inject(I18nService);
  private readonly currencyPipe = new CurrencyPipe('en-US');

  transform(
    value: number | string | null | undefined,
    currencyCode = 'VND',
    display: 'code' | 'symbol' | 'symbol-narrow' | string = 'symbol',
    digitsInfo = '1.0-0',
  ): string | null {
    return this.currencyPipe.transform(
      value,
      currencyCode,
      display,
      digitsInfo,
      this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US',
    );
  }
}
