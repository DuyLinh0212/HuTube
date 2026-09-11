import { Component, EventEmitter, Output, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { ThemeService } from '../../core/theme.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-admin-topbar',
  imports: [RouterLink, TranslatePipe],
  templateUrl: './admin-topbar.component.html',
  styleUrl: './admin-topbar.component.scss'
})
export class AdminTopbarComponent {
  @Output() readonly menuOpened = new EventEmitter<void>();
  readonly auth = inject(AuthService);
  readonly themeService = inject(ThemeService);
  readonly i18n = inject(I18nService);

  toggleTheme(): void {
    this.themeService.toggleTheme();
  }

  toggleLanguage(): void {
    const next = this.i18n.currentLang() === 'vi' ? 'en' : 'vi';
    this.i18n.setLang(next);
  }
}
