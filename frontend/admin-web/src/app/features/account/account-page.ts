import { Component, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { Router } from '@angular/router';
import { finalize } from 'rxjs';
import { AuthService, Session, errorMessage } from '../../core/auth.service';
import { ADMIN_APP } from '../../core/runtime-config';

@Component({ selector: 'app-account-page', imports: [DatePipe], templateUrl: './account-page.html' })
export class AccountPage {
  readonly auth = inject(AuthService);
  readonly admin = ADMIN_APP;
  private router = inject(Router);
  readonly sessions = signal<Session[]>([]);
  readonly loading = signal(true);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly message = signal('');
  readonly apiState = signal('Đang kiểm tra kết nối…');
  readonly pendingRevoke = signal<Session | null>(null);
  constructor() { this.load(); this.auth.info().subscribe({ next: () => this.apiState.set('Đã kết nối'), error: () => this.apiState.set('Chưa kết nối được máy chủ') }); }
  load() { this.loading.set(true); this.auth.sessions().pipe(finalize(() => this.loading.set(false))).subscribe({ next: result => this.sessions.set(result.items), error: error => this.error.set(errorMessage(error)) }); }
  logout() {
    if (this.busy()) return;
    this.busy.set(true); this.error.set('');
    this.auth.logout().pipe(finalize(() => this.busy.set(false))).subscribe({ next: () => void this.router.navigate(['/login']), error: error => this.error.set(errorMessage(error) + ' Hãy thử đăng xuất lại để kết thúc phiên trên máy chủ.') });
  }
  logoutOthers() {
    if (this.busy()) return;
    this.busy.set(true); this.error.set('');
    this.auth.logoutOthers().pipe(finalize(() => this.busy.set(false))).subscribe({ next: () => { this.message.set('Đã đăng xuất khỏi các thiết bị khác.'); this.load(); }, error: error => this.error.set(errorMessage(error)) });
  }
  revoke() {
    const session = this.pendingRevoke(); if (!session || this.busy()) return;
    this.busy.set(true); this.error.set('');
    this.auth.revoke(session.sessionId).pipe(finalize(() => this.busy.set(false))).subscribe({ next: () => { this.pendingRevoke.set(null); this.message.set('Đã kết thúc phiên đăng nhập.'); this.load(); }, error: error => this.error.set(errorMessage(error)) });
  }
}
