import { TestBed } from '@angular/core/testing';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter } from '@angular/router';
import { of } from 'rxjs';
import { AdminRbacPage } from './admin-rbac-page';
import { AuthService } from '../../core/auth.service';
import { authInterceptor } from '../../core/auth.interceptor';
import { RuntimeConfig } from '../../core/runtime-config';
import { I18nService } from '../../core/i18n.service';

describe('Admin RBAC page', () => {
  const base = 'http://localhost:5080/api/v1';
  const role = {
    roleId: 'role-admin',
    code: 'admin',
    name: 'Administrator',
    description: 'Quản trị vận hành',
    permissions: ['dashboard.view'],
  };
  const permissions = [
    { permissionId: 'permission-dashboard', code: 'dashboard.view', name: 'Xem Dashboard', description: null, status: 'active' },
    { permissionId: 'permission-user', code: 'user.view', name: 'Xem Người dùng', description: null, status: 'active' },
  ];
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [AdminRbacPage],
      providers: [provideHttpClient(withInterceptors([authInterceptor])), provideHttpClientTesting(), provideRouter([])],
    });
    TestBed.inject(RuntimeConfig).apiBaseUrl = base;
    TestBed.inject(I18nService).currentLang.set('vi');
    const auth = TestBed.inject(AuthService);
    auth.accessToken.set('access-token');
    spyOn(auth, 'ensureFreshAccessToken').and.returnValue(of('access-token'));
    auth.user.set({
      userId: 'admin-1',
      username: 'admin',
      email: 'admin@example.test',
      displayName: 'Admin',
      emailVerified: true,
      isAdmin: true,
      role: 'super_admin',
      permissions: ['role.view', 'role.edit'],
    });
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  function setup(roles = [role]) {
    const fixture = TestBed.createComponent(AdminRbacPage);
    http.expectOne(base + '/admin/roles').flush(roles);
    http.expectOne(base + '/admin/permissions').flush(permissions);
    fixture.detectChanges();
    return fixture;
  }

  it('loads roles and permissions from the protected admin endpoints', () => {
    const fixture = setup();
    expect(fixture.nativeElement.textContent).toContain('Administrator');
    expect(fixture.nativeElement.textContent).toContain('Xem Dashboard');
    expect(fixture.componentInstance.selectedRole()?.code).toBe('admin');
  });

  it('saves a changed permission set with an audit reason', () => {
    const fixture = setup();
    const page = fixture.componentInstance;
    page.beginEdit();
    page.togglePermission(permissions[1]);
    page.saveReason.set('Bổ sung quyền xem người dùng');
    page.saveRole();

    const request = http.expectOne(base + '/admin/roles/role-admin');
    expect(request.request.method).toBe('PUT');
    expect(request.request.body).toEqual({
      name: 'Administrator',
      description: 'Quản trị vận hành',
      permissionCodes: ['dashboard.view', 'user.view'],
      reason: 'Bổ sung quyền xem người dùng',
    });
    request.flush({ ...role, permissions: ['dashboard.view', 'user.view'] });
    fixture.detectChanges();

    expect(page.editing()).toBeFalse();
    expect(page.selectedRole()?.permissions).toEqual(['dashboard.view', 'user.view']);
  });

  it('creates a custom role with permissions and an audit reason', () => {
    const fixture = setup();
    const page = fixture.componentInstance;
    page.openCreate();
    page.createCode.set('content_reviewer');
    page.createName.set('Content reviewer');
    page.createDescription.set('Duyệt nội dung do người dùng báo cáo');
    page.createReason.set('Bổ sung nhóm quyền cho đội kiểm duyệt');
    page.toggleCreatePermission(permissions[0]);
    page.createRole();

    const request = http.expectOne(base + '/admin/roles');
    expect(request.request.method).toBe('POST');
    expect(request.request.body).toEqual({
      code: 'content_reviewer',
      name: 'Content reviewer',
      description: 'Duyệt nội dung do người dùng báo cáo',
      permissionCodes: ['dashboard.view'],
      reason: 'Bổ sung nhóm quyền cho đội kiểm duyệt',
    });
    request.flush({
      roleId: 'role-reviewer',
      code: 'content_reviewer',
      name: 'Content reviewer',
      description: 'Duyệt nội dung do người dùng báo cáo',
      permissions: ['dashboard.view'],
    });

    expect(page.createOpen()).toBeFalse();
    expect(page.selectedRole()?.code).toBe('content_reviewer');
  });

  it('confirms removal of assigned users before deleting and preserves the dialog for retry', () => {
    const custom = { ...role, roleId: 'custom-role', code: 'custom_role', name: 'Review team',
      isSystemRole: false, assignedUserCount: 2, status: 'active' };
    const fixture = setup([custom]);
    const page = fixture.componentInstance;
    const button = fixture.nativeElement.querySelector('.danger-action') as HTMLButtonElement;
    expect(button.disabled).toBeFalse();
    button.click();
    fixture.detectChanges();
    const dialog = fixture.nativeElement.querySelector('app-confirm-dialog');
    expect(dialog.textContent).toContain('2 người dùng');
    expect(dialog.textContent).toContain('không còn thuộc role nào');
    expect(dialog.textContent).toContain('Tài khoản của họ vẫn được giữ');
    http.expectNone(base + '/admin/roles/custom-role');
    page.deleteReason.set('Remove the review team');
    page.submitDeleteRole();
    page.submitDeleteRole();
    const request = http.expectOne(req => req.url === base + '/admin/roles/custom-role');
    expect(request.request.method).toBe('DELETE');
    expect(request.request.params.get('reason')).toBe('Remove the review team');
    request.flush({ message: 'Retry deletion' }, { status: 503, statusText: 'Unavailable' });
    expect(page.pendingDeleteRole()?.assignedUserCount).toBe(2);
    expect(page.deleteReason()).toBe('Remove the review team');
    page.submitDeleteRole();
    http.expectOne(req => req.url === base + '/admin/roles/custom-role').flush(null);
    expect(page.pendingDeleteRole()).toBeNull();
    expect(page.roles()).toEqual([]);
  });

  it('hides the User role from administrators even if an old API returns it', () => {
    const auth = TestBed.inject(AuthService);
    auth.user.update(user => ({ ...user!, role: 'admin' }));
    const userRole = { ...role, roleId: 'user-role', code: 'user', name: 'User', isSystemRole: true };
    const fixture = setup([userRole, role]);
    expect(fixture.componentInstance.roles().map(item => item.code)).toEqual(['admin']);
    expect(fixture.nativeElement.querySelector('.role-list').textContent).not.toContain('User');
  });

  it('shows the User role to Super Admin without allowing deletion', () => {
    const userRole = { ...role, roleId: 'user-role', code: 'user', name: 'User', isSystemRole: true };
    const fixture = setup([userRole]);
    expect(fixture.componentInstance.roles().map(item => item.code)).toEqual(['user']);
    expect(fixture.nativeElement.querySelector('.danger-action')).toBeNull();
    fixture.componentInstance.deleteSelectedRole();
    expect(fixture.componentInstance.pendingDeleteRole()).toBeNull();
  });
});
