import { Component, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { Router } from '@angular/router';
import { finalize } from 'rxjs';
import { AuthService, Session, errorMessage } from '../../core/auth.service';
import { ADMIN_APP } from '../../core/runtime-config';
import { ThemeService, AppTheme } from '../../core/theme.service';
import { I18nService, AppLang } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-account-page',
  imports: [DatePipe, TranslatePipe],
  templateUrl: './account-page.html',
  styleUrl: './account-page.scss'
})
export class AccountPage {
  readonly auth = inject(AuthService);
  readonly admin = ADMIN_APP;
  readonly themeService = inject(ThemeService);
  readonly i18n = inject(I18nService);
  private router = inject(Router);

  readonly sessions = signal<Session[]>([]);
  readonly loading = signal(true);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly message = signal('');
  readonly apiState = signal(this.i18n.t('account.connectionChecking'));
  readonly pendingRevoke = signal<Session | null>(null);

  constructor() {
    this.load();
    this.auth.info().subscribe({
      next: () => this.apiState.set(this.i18n.t('account.connectionConnected')),
      error: () => this.apiState.set(this.i18n.t('account.connectionUnavailable'))
    });
  }

  load() {
    this.loading.set(true);
    this.auth.sessions().pipe(finalize(() => this.loading.set(false))).subscribe({
      next: result => this.sessions.set(result.items),
      error: error => this.error.set(errorMessage(error, this.i18n))
    });
  }

  onThemeChange(event: Event) {
    const val = (event.target as HTMLSelectElement).value as AppTheme;
    this.themeService.setTheme(val);
  }

  onLanguageChange(event: Event) {
    const val = (event.target as HTMLSelectElement).value as AppLang;
    this.i18n.setLang(val);
  }

  logout() {
    if (this.busy()) return;
    this.busy.set(true);
    this.error.set('');
    this.auth.logout().pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => void this.router.navigate(['/login']),
      error: error => this.error.set(`${errorMessage(error, this.i18n)} ${this.i18n.t('account.logoutAgainHint')}`)
    });
  }

  logoutOthers() {
    if (this.busy()) return;
    this.busy.set(true);
    this.error.set('');
    this.auth.logoutOthers().pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => {
        this.message.set(this.i18n.t('account.logoutOthersSuccess'));
        this.load();
      },
      error: error => this.error.set(errorMessage(error, this.i18n))
    });
  }

  revoke() {
    const session = this.pendingRevoke();
    if (!session || this.busy()) return;
    this.busy.set(true);
    this.error.set('');
    this.auth.revoke(session.sessionId).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => {
        this.pendingRevoke.set(null);
        this.message.set(this.i18n.t('account.sessionRevoked'));
        this.load();
      },
      error: error => this.error.set(errorMessage(error, this.i18n))
    });
  }
}
