import { AfterViewChecked, Component, DestroyRef, ElementRef, ViewChild, inject, signal } from '@angular/core';
import { FormsModule, NgForm } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { finalize, Observable } from 'rxjs';
import { AuthService, errorMessage, safeReturnUrl } from '../../core/auth.service';
import { ADMIN_APP, RuntimeConfig } from '../../core/runtime-config';

declare global { interface Window { google?: { accounts: { id: { initialize(config: { client_id: string; callback: (response: { credential?: string }) => void; auto_select: boolean }): void; renderButton(parent: HTMLElement, options: { theme: string; size: string; width: number }): void; }; }; }; } }

@Component({ selector: 'app-auth-page', imports: [FormsModule, RouterLink], templateUrl: './auth-page.html' })
export class AuthPage implements AfterViewChecked {
  readonly admin = ADMIN_APP;
  readonly auth = inject(AuthService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);
  private destroyRef = inject(DestroyRef);
  private authConfig = inject(RuntimeConfig);
  readonly mode = signal('login');
  readonly busy = signal(false);
  readonly message = signal('');
  readonly error = signal('');
  readonly completed = signal(false);
  showPassword = false;
  email = ''; username = ''; displayName = ''; password = ''; confirmPassword = '';
  private token = '';
  private googleRendered = false;
  private googleLoading = false;
  @ViewChild('googleButton') googleButton?: ElementRef<HTMLDivElement>;
  readonly titles: Record<string, string> = { login: 'Đăng nhập', register: 'Tạo tài khoản', 'verify-email': 'Xác minh email', 'forgot-password': 'Quên mật khẩu?', 'reset-password': 'Đặt lại mật khẩu' };
  constructor() {
    this.route.url.pipe(takeUntilDestroyed()).subscribe(segments => {
      this.mode.set(segments[0]?.path || 'login'); this.googleRendered = false; this.googleLoading = false; this.message.set(''); this.error.set(''); this.completed.set(false); this.password = ''; this.confirmPassword = '';
      this.token = this.route.snapshot.queryParamMap.get('token') || '';
      if (this.route.snapshot.queryParamMap.get('reason') === 'expired') this.message.set('Phiên đăng nhập đã hết hạn. Đăng nhập lại để tiếp tục.');
      if (this.mode() === 'verify-email' && this.token) this.verify();
      if (this.mode() === 'reset-password' && !this.token) this.error.set('Liên kết thiếu mã xác nhận. Vui lòng yêu cầu đặt lại mật khẩu.');
    });
  }
  ngAfterViewChecked() {
    if (this.mode() !== 'login' || this.googleRendered || this.googleLoading || !this.googleButton || !this.authGoogleClientId()) return;
    this.googleLoading = true;
    this.loadGoogleScript().then(() => {
      if (!window.google || !this.googleButton || this.googleRendered) return;
      window.google.accounts.id.initialize({ client_id: this.authGoogleClientId(), auto_select: false, callback: response => {
        if (!response.credential) { this.error.set('Không nhận được thông tin xác thực từ Google.'); return; }
        this.run(this.auth.google(response.credential), () => void this.router.navigateByUrl(safeReturnUrl(this.route.snapshot.queryParamMap.get('returnUrl'))));
      }});
      window.google.accounts.id.renderButton(this.googleButton.nativeElement, { theme: 'outline', size: 'large', width: 360 });
      this.googleRendered = true;
    }).catch(() => this.error.set('Không tải được đăng nhập Google. Vui lòng thử lại.')).finally(() => this.googleLoading = false);
  }
  authGoogleClientId() { return this.authConfig.googleClientId; }
  private loadGoogleScript(): Promise<void> {
    if (window.google) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const existing = document.querySelector<HTMLScriptElement>('script[data-hutube-google]');
      if (existing) { existing.addEventListener('load', () => resolve(), { once: true }); existing.addEventListener('error', () => reject(), { once: true }); return; }
      const script = document.createElement('script'); script.src = 'https://accounts.google.com/gsi/client'; script.async = true; script.defer = true; script.dataset['hutubeGoogle'] = 'true'; script.onload = () => resolve(); script.onerror = () => reject(); document.head.appendChild(script);
    });
  }
  get title() { return this.titles[this.mode()]; }
  get hasResetToken() { return !!this.token; }
  get mobileResetLink() { return 'hutube://auth/reset-password?token=' + encodeURIComponent(this.token); }
  private run(request: Observable<unknown>, success: () => void) {
    this.busy.set(true); this.error.set(''); this.message.set('');
    request.pipe(takeUntilDestroyed(this.destroyRef), finalize(() => this.busy.set(false))).subscribe({ next: success, error: error => this.error.set(errorMessage(error)) });
  }
  submit(form: NgForm) {
    if (this.busy()) return;
    if (form.invalid) { form.control.markAllAsTouched(); this.error.set('Vui lòng kiểm tra các trường được đánh dấu.'); return; }
    if (['register', 'reset-password'].includes(this.mode()) && this.password !== this.confirmPassword) { this.error.set('Mật khẩu xác nhận chưa khớp.'); return; }
    switch (this.mode()) {
      case 'login': this.run(this.auth.login(this.email.trim(), this.password), () => { this.password = ''; void this.router.navigateByUrl(safeReturnUrl(this.route.snapshot.queryParamMap.get('returnUrl'))); }); break;
      case 'register': this.run(this.auth.register({ username: this.username.trim(), email: this.email.trim(), displayName: this.displayName.trim(), password: this.password }), () => { this.completed.set(true); this.password = ''; this.confirmPassword = ''; this.message.set('Tài khoản đã được tạo. Kiểm tra hộp thư để xác minh email trước khi đăng nhập.'); }); break;
      case 'forgot-password': this.run(this.auth.forgot(this.email.trim()), () => { this.message.set('Nếu email có trong hệ thống, hướng dẫn đặt lại mật khẩu sẽ được gửi đến bạn. Hãy kiểm tra cả thư rác.'); this.completed.set(true); }); break;
      case 'reset-password': if (this.token) this.run(this.auth.reset(this.token, this.password), () => { this.password = ''; this.confirmPassword = ''; this.completed.set(true); this.message.set('Đã đổi mật khẩu và kết thúc các phiên cũ. Bạn có thể đăng nhập bằng mật khẩu mới.'); }); break;
    }
  }
  verify() { this.run(this.auth.verify(this.token), () => { this.completed.set(true); this.message.set('Email đã được xác minh. Bạn có thể đăng nhập ngay.'); }); }
  resend(form: NgForm) {
    if (form.invalid || this.busy()) { form.control.markAllAsTouched(); return; }
    this.run(this.auth.resend(this.email.trim()), () => this.message.set('Nếu tài khoản cần xác minh, một liên kết mới sẽ được gửi đến email của bạn.'));
  }
}
