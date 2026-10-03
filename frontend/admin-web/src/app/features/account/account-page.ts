import { Component, computed, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { Router } from '@angular/router';
import { finalize } from 'rxjs';
import { AuthService, LoginHistoryItem, Session, errorMessage } from '../../core/auth.service';
import { ADMIN_APP } from '../../core/runtime-config';
import { ThemeService, AppTheme } from '../../core/theme.service';
import { I18nService, AppLang } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';

interface SessionGroup {
  key: string;
  latest: Session;
  count: number;
  isCurrent: boolean;
}

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
  readonly sessionGroups = computed<SessionGroup[]>(() => {
    const groups = new Map<string, Session[]>();
    for (const session of this.sessions()) {
      const deviceId = session.deviceId?.trim();
      const key = deviceId ? `${session.platform}:${deviceId}` : `session:${session.sessionId}`;
      const items = groups.get(key) ?? [];
      items.push(session);
      groups.set(key, items);
    }
    return [...groups.entries()].map(([key, items]) => {
      const latest = items.reduce((newest, item) => Date.parse(item.issuedAt) > Date.parse(newest.issuedAt) ? item : newest);
      return { key, latest, count: items.length, isCurrent: items.some(item => item.isCurrent) };
    }).sort((left, right) => Date.parse(right.latest.issuedAt) - Date.parse(left.latest.issuedAt));
  });
  readonly loading = signal(true);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly message = signal('');
  readonly apiState = signal(this.i18n.t('account.connectionChecking'));
  readonly pendingRevoke = signal<Session | null>(null);
  readonly loginHistoryVisible = signal(false);
  readonly loginHistoryLoading = signal(false);
  readonly loginHistoryLoaded = signal(false);
  readonly loginHistoryItems = signal<LoginHistoryItem[]>([]);
  readonly loginHistoryPage = signal(1);
  readonly loginHistoryTotal = signal(0);
  readonly loginHistoryPageSize = 20;
  readonly loginHistoryPageCount = computed(() => Math.max(1, Math.ceil(this.loginHistoryTotal() / this.loginHistoryPageSize)));

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

  toggleLoginHistory() {
    const visible = !this.loginHistoryVisible();
    this.loginHistoryVisible.set(visible);
    if (visible && !this.loginHistoryLoaded()) this.loadLoginHistory(1);
  }

  loadLoginHistory(page: number) {
    if (this.loginHistoryLoading()) return;
    this.loginHistoryLoading.set(true);
    this.auth.loginHistory(page, this.loginHistoryPageSize).pipe(finalize(() => this.loginHistoryLoading.set(false))).subscribe({
      next: result => {
        this.loginHistoryItems.set(result.items);
        this.loginHistoryPage.set(result.page);
        this.loginHistoryTotal.set(result.total);
        this.loginHistoryLoaded.set(true);
      },
      error: error => this.error.set(errorMessage(error, this.i18n))
    });
  }

  displayIpAddress(ipAddress: string): string {
    const normalized = ipAddress.trim().toLowerCase();
    return ['::1', '0:0:0:0:0:0:0:1', '127.0.0.1', '::ffff:127.0.0.1'].includes(normalized)
      ? this.i18n.t('account.localIpAddress')
      : ipAddress;
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
