import { Component, EventEmitter, HostListener, Input, Output, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { ThemeService } from '../../core/theme.service';
import { AppLang, I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-admin-topbar',
  imports: [RouterLink, TranslatePipe],
  templateUrl: './admin-topbar.component.html',
  styleUrl: './admin-topbar.component.scss'
})
export class AdminTopbarComponent {
  @Output() readonly menuOpened = new EventEmitter<void>();
  @Input() sidebarCollapsed = false;
  readonly auth = inject(AuthService);
  readonly themeService = inject(ThemeService);
  readonly i18n = inject(I18nService);
  readonly menuOpen = signal(false);
  readonly languageMenuOpen = signal(false);

  toggleTheme(): void {
    this.themeService.toggleTheme();
  }

  toggleMenu(): void {
    this.menuOpen.update(open => !open);
    if (!this.menuOpen()) this.languageMenuOpen.set(false);
  }

  closeMenu(): void {
    this.menuOpen.set(false);
    this.languageMenuOpen.set(false);
  }

  toggleLanguageMenu(): void {
    this.languageMenuOpen.update(open => !open);
  }

  selectLanguage(language: AppLang): void {
    this.i18n.setLang(language);
    this.closeMenu();
  }

  @HostListener('document:click')
  onDocumentClick(): void {
    this.closeMenu();
  }

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.closeMenu();
  }
}
