import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { AuthService } from '../../core/auth.service';
import { RuntimeConfig } from '../../core/runtime-config';
import { I18nService } from '../../core/i18n.service';
import { AdminUsersPage } from './admin-users-page';
import { AdminUserDetail } from './admin-users.service';

describe('Users without a role', () => {
  const base = 'http://localhost:5080/api/v1';
  const user: AdminUserDetail = { userId: 'no-role', displayName: 'Unassigned user', username: 'unassigned',
    email: 'unassigned@example.test', avatarUrl: null, roleCode: null, roleName: null,
    planCode: null, planName: null, channelCount: 0, warningCount: 0, lastLoginAt: null,
    createdAt: '2026-10-25T00:00:00Z', status: 'active', emailVerified: true, lockedUntil: null,
    permissions: [], auditHistory: [], channels: [] };
  const roles = [{ roleId: 'user-role', code: 'user', name: 'User' }, { roleId: 'reviewer-role', code: 'reviewer', name: 'Reviewer' }];
  const actor = signal({ role: 'admin' });
  let http: HttpTestingController;

  beforeEach(() => {
    actor.set({ role: 'admin' });
    TestBed.configureTestingModule({ imports: [AdminUsersPage], providers: [provideHttpClient(), provideHttpClientTesting(),
      { provide: AuthService, useValue: { user: actor, hasPermission: () => true } }] });
    TestBed.inject(RuntimeConfig).apiBaseUrl = base;
    TestBed.inject(I18nService).currentLang.set('vi');
    http = TestBed.inject(HttpTestingController);
  });
  afterEach(() => http.verify());

  function setup(failRoles = false) {
    const fixture = TestBed.createComponent(AdminUsersPage);
    fixture.detectChanges();
    http.expectOne(req => req.url === base + '/admin/users').flush({ items: [user], page: 1, pageSize: 10,
      total: 1, hasMore: false, stats: { total: 1, active: 1, blocked: 0, creatorPro: 0 } });
    http.expectOne(base + '/admin/users/no-role').flush(user);
    const request = http.expectOne(base + '/admin/roles');
    if (failRoles) request.flush({}, { status: 503, statusText: 'Unavailable' });
    else request.flush(roles);
    fixture.detectChanges();
    return fixture;
  }

  it('keeps unassigned users visible, filters them and permits assigning a new role', () => {
    const fixture = setup();
    const page = fixture.componentInstance;
    expect(fixture.nativeElement.textContent).toContain('Chưa có role');
    expect(page.roles().map(role => role.code)).toEqual(['reviewer']);
    page.selectedRole.set('__unassigned');
    expect(page.filteredUsers().map(item => item.userId)).toEqual(['no-role']);
    page.selectedUser.set(user);
    page.openAction('role', user);
    expect(page.actionRole()).toBe('');
    page.actionReason.set('Assign to review team');
    page.submitAction();
    http.expectNone(base + '/admin/users/no-role/role');
    page.actionRole.set('reviewer');
    page.submitAction();
    const request = http.expectOne(base + '/admin/users/no-role/role');
    expect(request.request.body).toEqual({ roleCode: 'reviewer', reason: 'Assign to review team' });
    request.flush({ ...user, roleCode: 'reviewer', roleName: 'Reviewer' });
    // Successful updates reload the current users page.
    for (const reload of http.match(req => req.url === base + '/admin/users')) {
      reload.flush({ items: [{ ...user, roleCode: 'reviewer', roleName: 'Reviewer' }], page: 1, pageSize: 10,
        total: 1, hasMore: false, stats: { total: 1, active: 1, blocked: 0, creatorPro: 0 } });
    }
    for (const detail of http.match(base + '/admin/users/no-role')) {
      detail.flush({ ...user, roleCode: 'reviewer', roleName: 'Reviewer' });
    }
  });

  it('does not expose the User role in fallback options for administrators', () => {
    const fixture = setup(true);
    expect(fixture.componentInstance.roles().some(role => role.code === 'user')).toBeFalse();
  });

  it('includes the User role for Super Admin', () => {
    actor.set({ role: 'super_admin' });
    const fixture = setup();
    expect(fixture.componentInstance.roles().some(role => role.code === 'user')).toBeTrue();
  });
});
