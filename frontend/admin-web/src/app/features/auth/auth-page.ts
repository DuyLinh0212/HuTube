import { ResultNoticeComponent } from '@dalitu/ui/result-notice.component';
import { DOCUMENT } from '@angular/common';
import { Component, DestroyRef, inject, signal } from '@angular/core';
import { FormsModule, NgForm, NgModel } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { finalize, Observable } from 'rxjs';
import { AuthService, captureBrowserLocation, errorMessage, safeReturnUrl } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { ADMIN_APP } from '../../core/runtime-config';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({ selector: 'app-auth-page', imports: [ResultNoticeComponent, FormsModule, RouterLink, TranslatePipe], templateUrl: './auth-page.html', styleUrl: './auth-page.scss' })
export class AuthPage {
  readonly admin = ADMIN_APP;
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);
  private destroyRef = inject(DestroyRef);
  private document = inject(DOCUMENT);
  readonly mode = signal('login');
  readonly busy = signal(false);
  readonly message = signal('');
  readonly error = signal('');
  readonly completed = signal(false);
  readonly connectionIssue = signal(false);
  showPassword = false;
  email = ''; code = ''; username = ''; displayName = ''; password = ''; confirmPassword = '';
  private token = '';
  constructor() {
    this.route.url.pipe(takeUntilDestroyed()).subscribe(segments => {
      this.mode.set(segments[0]?.path || 'login'); this.message.set(''); this.error.set(''); this.completed.set(false); this.password = ''; this.confirmPassword = ''; this.code = '';
      this.email = this.route.snapshot.queryParamMap.get('email') || '';
      this.token = this.mode() === 'verify-email' ? this.route.snapshot.queryParamMap.get('token') || '' : '';
      if (this.route.snapshot.queryParamMap.get('reason') === 'expired') this.message.set(this.i18n.t('auth.expiredSession'));
      const reason = this.route.snapshot.queryParamMap.get('reason');
      this.connectionIssue.set(reason === 'unavailable' || reason === 'rate-limited');
      if (this.connectionIssue()) this.error.set(this.i18n.t(reason === 'rate-limited' ? 'auth.error.rateLimited' : 'auth.error.serverUnavailable'));
      if (this.mode() === 'verify-email' && this.token) this.verify();
    });
  }
  get title(): string {
    const mode = this.mode();
    const suffix = mode === 'verify-email' ? 'verifyEmail'
      : mode === 'forgot-password' ? 'forgotPassword'
        : mode === 'reset-password' ? 'resetPassword' : mode;
    return this.i18n.t(`auth.title.${suffix}`);
  }
  get tagline(): string {
    const mode = this.mode();
    const suffix = mode === 'verify-email' ? 'verifyEmail'
      : mode === 'forgot-password' ? 'forgotPassword'
        : mode === 'reset-password' ? 'resetPassword' : mode;
    return this.i18n.t(`auth.tagline.${suffix}`);
  }
  retryRestore() {
    this.run(this.auth.restore(), () => {
      this.connectionIssue.set(false);
      if (this.auth.accessToken()) void this.router.navigateByUrl(safeReturnUrl(this.route.snapshot.queryParamMap.get('returnUrl')));
    });
  }
  private run(request: Observable<unknown>, success: () => void) {
    this.busy.set(true); this.error.set(''); this.message.set('');
    request.pipe(takeUntilDestroyed(this.destroyRef), finalize(() => this.busy.set(false))).subscribe({ next: success, error: error => this.error.set(errorMessage(error, this.i18n)) });
  }
  submit(form: NgForm) {
    if (this.busy()) return;
    this.syncAutofilledEmail(form, 'email');
    if (form.invalid) { form.control.markAllAsTouched(); this.error.set(this.i18n.t('auth.formInvalid')); return; }
    if (['register', 'reset-password'].includes(this.mode()) && this.password !== this.confirmPassword) { this.error.set(this.i18n.t('auth.passwordMismatch')); return; }
    switch (this.mode()) {
      case 'login':
        this.busy.set(true);
        captureBrowserLocation().then(loc => {
          this.run(this.auth.login(this.email.trim(), this.password, loc), () => {
            this.password = '';
            void this.router.navigateByUrl(safeReturnUrl(this.route.snapshot.queryParamMap.get('returnUrl')));
          });
        });
        break;
      case 'register': this.run(this.auth.register({ username: this.username.trim(), email: this.email.trim(), displayName: this.displayName.trim(), password: this.password }), () => { this.completed.set(true); this.password = ''; this.confirmPassword = ''; this.message.set(this.i18n.t('auth.accountCreated')); }); break;
      case 'forgot-password': this.run(this.auth.forgot(this.email.trim()), () => { this.message.set(this.i18n.t('auth.checkResetEmail')); this.completed.set(true); }); break;
      case 'reset-password': this.run(this.auth.reset(this.email.trim(), this.code.trim(), this.password), () => { this.password = ''; this.confirmPassword = ''; this.code = ''; this.completed.set(true); this.message.set(this.i18n.t('auth.passwordChanged')); }); break;
    }
  }
  verify() { this.run(this.auth.verify(this.token), () => { this.completed.set(true); this.message.set(this.i18n.t('auth.emailVerified')); }); }
  resend(form: NgForm) {
    this.syncAutofilledEmail(form, 'resendEmail');
    if (form.invalid || this.busy()) { form.control.markAllAsTouched(); return; }
    this.run(this.auth.resend(this.email.trim()), () => this.message.set(this.i18n.t('auth.resendIfNeeded')));
  }

  private syncAutofilledEmail(form: NgForm, controlName: string) {
    const input = this.document.querySelector<HTMLInputElement>(`input[name="${controlName}"]`);
    const domValue = input?.value.trim();
    if (!domValue || domValue === this.email.trim()) return;

    this.email = domValue;
    form.controls[controlName]?.setValue(domValue);
    form.control.updateValueAndValidity();
  }

  syncAutofilledEmailControl(control: NgModel) {
    const input = this.document.querySelector<HTMLInputElement>('#email');
    const domValue = input?.value.trim() ?? '';
    if (domValue === this.email && control.control.value === domValue) return;
    this.email = domValue;
    control.control.setValue(domValue);
    control.control.updateValueAndValidity();
  }
}
