import { TestBed } from '@angular/core/testing';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter } from '@angular/router';
import { AdminRbacPage } from './admin-rbac-page';
import { AuthService } from '../../core/auth.service';
import { authInterceptor } from '../../core/auth.interceptor';
import { RuntimeConfig } from '../../core/runtime-config';

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
    const auth = TestBed.inject(AuthService);
    auth.accessToken.set('access-token');
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

  function setup() {
    const fixture = TestBed.createComponent(AdminRbacPage);
    http.expectOne(base + '/admin/roles').flush([role]);
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
});
