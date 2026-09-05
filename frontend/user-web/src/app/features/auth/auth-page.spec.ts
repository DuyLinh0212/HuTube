import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { RuntimeConfig } from '../../core/runtime-config';
import { authInterceptor } from '../../core/auth.interceptor';
import { AuthPage } from './auth-page';

describe('Vietnamese auth forms', () => {
  const base='http://localhost:5080/api/v1';
  let controller: HttpTestingController;
  beforeEach(() => {
    TestBed.configureTestingModule({providers:[provideRouter(['login','register','forgot-password','reset-password','verify-email'].map(path=>({path,component:AuthPage}))),provideHttpClient(withInterceptors([authInterceptor])),provideHttpClientTesting()]});
    TestBed.inject(RuntimeConfig).apiBaseUrl=base; controller=TestBed.inject(HttpTestingController);
  });
  afterEach(()=>controller.verify());
  async function fill(harness: RouterTestingHarness, values: Record<string,string>) {
    for (const [name,value] of Object.entries(values)) { const input=harness.routeNativeElement!.querySelector<HTMLInputElement>('[name="'+name+'"]')!; input.value=value; input.dispatchEvent(new Event('input')); }
    harness.detectChanges(); await harness.fixture.whenStable();
  }
  async function submit(harness: RouterTestingHarness) { harness.routeNativeElement!.querySelector('form')!.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true})); harness.detectChanges(); await harness.fixture.whenStable(); }
  it('prevents empty login submissions and provides an actionable error', async()=>{
    const harness=await RouterTestingHarness.create('/login'); await submit(harness);
    controller.expectNone(base+'/auth/login'); expect(harness.routeNativeElement!.textContent).toContain('Vui lòng kiểm tra');
  });
  it('rejects mismatched registration passwords before calling the API', async()=>{
    const harness=await RouterTestingHarness.create('/register');
    await fill(harness,{displayName:'Linh',username:'linh',email:'linh@example.test',password:'Password123',confirmPassword:'OtherPassword123'}); await submit(harness);
    controller.expectNone(base+'/auth/register'); expect(harness.routeNativeElement!.textContent).toContain('Mật khẩu xác nhận chưa khớp');
  });
  it('shows verification instructions and never auto-logs-in after registration', async()=>{
    const harness=await RouterTestingHarness.create('/register');
    await fill(harness,{displayName:'Linh',username:'linh',email:'linh@example.test',password:'Password123',confirmPassword:'Password123'}); await submit(harness);
    const request=controller.expectOne(base+'/auth/register'); expect(request.request.body.username).toBe('linh'); request.flush({message:'registered'}); harness.detectChanges();
    expect(harness.routeNativeElement!.textContent).toContain('Kiểm tra hộp thư'); controller.expectNone(base+'/auth/login');
  });
  it('consumes an email verification link and displays success', async()=>{
    const harness=await RouterTestingHarness.create('/verify-email?token=verification-secret');
    const request=controller.expectOne(base+'/auth/verify-email'); expect(request.request.body).toEqual({token:'verification-secret'}); request.flush({message:'verified'}); harness.detectChanges();
    expect(harness.routeNativeElement!.textContent).toContain('Email đã được xác minh'); expect(harness.routeNativeElement!.textContent).not.toContain('verification-secret');
  });
  it('reports the expired-session state and supports requesting a new verification email', async()=>{
    const harness=await RouterTestingHarness.create('/login?reason=expired'); expect(harness.routeNativeElement!.textContent).toContain('Phiên đăng nhập đã hết hạn');
    await harness.navigateByUrl('/verify-email'); await fill(harness,{resendEmail:'linh@example.test'}); await submit(harness);
    controller.expectOne(base+'/auth/resend-verification').flush({message:'sent'}); harness.detectChanges(); expect(harness.routeNativeElement!.textContent).toContain('một liên kết mới');
  });
  it('handles forgotten passwords with an enumeration-safe confirmation', async()=>{
    const harness=await RouterTestingHarness.create('/forgot-password'); await fill(harness,{email:'unknown@example.test'}); await submit(harness);
    controller.expectOne(base+'/auth/forgot-password').flush({message:'sent'}); harness.detectChanges(); expect(harness.routeNativeElement!.textContent).toContain('Nếu email có trong hệ thống');
  });
  it('requires a reset token and shows recovery navigation', async()=>{
    const harness=await RouterTestingHarness.create('/reset-password'); expect(harness.routeNativeElement!.textContent).toContain('Liên kết thiếu mã xác nhận'); expect(harness.routeNativeElement!.querySelector('a[href="/forgot-password"]')).not.toBeNull();
  });
  it('sets a new password using the link token and clears password fields after success', async()=>{
    const harness=await RouterTestingHarness.create('/reset-password?token=reset-secret');
    await fill(harness,{password:'NewPassword123',confirmPassword:'NewPassword123'}); await submit(harness);
    const request=controller.expectOne(base+'/auth/reset-password'); expect(request.request.body).toEqual({token:'reset-secret',password:'NewPassword123'});
    request.flush({message:'reset'}); harness.detectChanges(); expect(harness.routeNativeElement!.textContent).toContain('Đã đổi mật khẩu'); expect(harness.routeNativeElement!.querySelector('input[type="password"]')).toBeNull();
  });
  it('shows invalid credentials without dropping the email or leaving the form busy', async()=>{
    const harness=await RouterTestingHarness.create('/login'); await fill(harness,{email:'linh@example.test',password:'WrongPassword123'}); await submit(harness);
    controller.expectOne(base+'/auth/login').flush({code:'INVALID_CREDENTIALS'}, {status:401,statusText:'Unauthorized'}); harness.detectChanges();
    expect(harness.routeNativeElement!.textContent).toContain('Email hoặc mật khẩu chưa đúng'); expect(harness.routeNativeElement!.querySelector<HTMLInputElement>('#email')!.value).toBe('linh@example.test'); expect(harness.routeNativeElement!.querySelector<HTMLButtonElement>('button[type="submit"]')!.disabled).toBeFalse();
  });
});
