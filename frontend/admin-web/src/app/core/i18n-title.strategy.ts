import { Injectable, effect, inject } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { RouterStateSnapshot, TitleStrategy } from '@angular/router';
import { I18nService } from './i18n.service';

@Injectable()
export class I18nTitleStrategy extends TitleStrategy {
  private readonly i18n = inject(I18nService);
  private readonly title = inject(Title);
  private currentTitleKey = '';

  constructor() {
    super();
    effect(() => {
      this.i18n.currentLang();
      this.applyTitle();
    });
  }

  override updateTitle(snapshot: RouterStateSnapshot): void {
    this.currentTitleKey = this.buildTitle(snapshot) ?? '';
    this.applyTitle();
  }

  private applyTitle(): void {
    this.title.setTitle(this.currentTitleKey
      ? `${this.i18n.t(this.currentTitleKey)} · HuTube`
      : 'HuTube Admin');
  }
}
