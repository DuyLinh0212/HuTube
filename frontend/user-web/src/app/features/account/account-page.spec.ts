import { TestBed } from '@angular/core/testing';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter, Router } from '@angular/router';
import { AccountPage } from './account-page';
import { AuthService } from '../../core/auth.service';
import { authInterceptor } from '../../core/auth.interceptor';
import { ADMIN_APP, RuntimeConfig } from '../../core/runtime-config';

describe('Active device management', () => {
  const base = 'http://localhost:5080/api/v1';
  let http: HttpTestingController;
  beforeEach(() => {
    TestBed.configureTestingModule({imports:[AccountPage],providers:[provideHttpClient(withInterceptors([authInterceptor])),provideHttpClientTesting(),provideRouter([])]});
    TestBed.inject(RuntimeConfig).apiBaseUrl=base; http=TestBed.inject(HttpTestingController);
    const auth=TestBed.inject(AuthService);
    auth.accessToken.set('access-token'); auth.user.set({userId:'1',username:'linh',email:'linh@example.test',displayName:'Linh',emailVerified:true,isAdmin:ADMIN_APP});
  });
  afterEach(()=>http.verify());
  function setup() {
    const fixture=TestBed.createComponent(AccountPage);
    const current={sessionId:'current',deviceName:'Chrome',platform:'web',issuedAt:'2026-09-01T00:00:00Z',lastActiveAt:'2026-09-05T00:00:00Z',expiresAt:'2026-10-01T00:00:00Z',isCurrent:true};
    const other={...current,sessionId:'other',deviceName:'Điện thoại',platform:'mobile',isCurrent:false};
    http.expectOne(base+'/auth/sessions').flush({items:[current,other]}); http.expectOne(base+'/system/info').flush({name:'HuTube'}); fixture.detectChanges();
    return {fixture,current,other};
  }
  it('shows the current device and requires confirmation before revoking another',()=>{
    const {fixture,other}=setup(); expect(fixture.nativeElement.textContent).toContain('Thiết bị này');
    fixture.componentInstance.pendingRevoke.set(other); fixture.detectChanges(); http.expectNone(base+'/auth/sessions/other');
    expect(fixture.nativeElement.textContent).toContain('Kết thúc phiên trên'); fixture.componentInstance.revoke();
    const request=http.expectOne(base+'/auth/sessions/other'); expect(request.request.method).toBe('DELETE'); request.flush({message:'revoked'});
    http.expectOne(base+'/auth/sessions').flush({items:[]}); fixture.detectChanges(); expect(fixture.componentInstance.pendingRevoke()).toBeNull();
  });
  it('refreshes device data after ending all other sessions',()=>{
    const {fixture,current}=setup(); fixture.componentInstance.logoutOthers(); http.expectOne(base+'/auth/logout-others').flush({message:'ok'});
    http.expectOne(base+'/auth/sessions').flush({items:[current]}); fixture.detectChanges(); expect(fixture.componentInstance.sessions().length).toBe(1); expect(fixture.nativeElement.textContent).toContain('Đã đăng xuất khỏi các thiết bị khác');
  });
  it('revokes the current session and returns to login',()=>{
    const {fixture}=setup(); const navigate=spyOn(TestBed.inject(Router),'navigate').and.resolveTo(true);
    fixture.componentInstance.logout(); http.expectOne(base+'/auth/logout').flush({message:'ok'});
    expect(TestBed.inject(AuthService).accessToken()).toBeNull(); expect(navigate).toHaveBeenCalledWith(['/login']);
  });
  it('keeps a retry action if server-side logout fails',()=>{
    const {fixture}=setup(); fixture.componentInstance.logout(); http.expectOne(base+'/auth/logout').flush({}, {status:503,statusText:'Unavailable'}); fixture.detectChanges();
    expect(fixture.componentInstance.busy()).toBeFalse(); expect(fixture.nativeElement.textContent).toContain('Hãy thử đăng xuất lại');
  });
});
