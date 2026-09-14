import { Routes } from '@angular/router';
import { authGuard } from './core/auth.guard';
import { permissionGuard } from './core/permission.guard';
import { ADMIN_APP } from './core/runtime-config';
const authPage = () => import('./features/auth/auth-page').then(m => m.AuthPage);
export const routes: Routes = [
  { path: 'login', loadComponent: authPage, title: 'Đăng nhập · HuTube' },
  ...(!ADMIN_APP ? [{ path: 'register', loadComponent: authPage, title: 'Đăng ký · HuTube' }] : []),
  { path: 'verify-email', loadComponent: authPage, title: 'Xác minh email · HuTube' },
  { path: 'forgot-password', loadComponent: authPage, title: 'Quên mật khẩu · HuTube' },
  { path: 'reset-password', loadComponent: authPage, title: 'Đặt lại mật khẩu · HuTube' },
  { path: 'forbidden', loadComponent: () => import('./features/error/forbidden-page').then(m => m.ForbiddenPage), title: 'Không có quyền truy cập · HuTube' },
  { path: 'users', canActivate: [authGuard, permissionGuard], data: { permission: 'user.view' }, loadComponent: () => import('./features/users/admin-users-page').then(m => m.AdminUsersPage), title: 'Người dùng · HuTube' },
  { path: 'roles', canActivate: [authGuard, permissionGuard], data: { permission: 'role.view' }, loadComponent: () => import('./features/rbac/admin-rbac-page').then(m => m.AdminRbacPage), title: 'Nhóm quyền & vai trò · HuTube' },
  { path: 'plans', canActivate: [authGuard, permissionGuard], data: { permission: 'plan.view' }, loadComponent: () => import('./features/plans/admin-plans-page').then(m => m.AdminPlansPage), title: 'Gói dịch vụ · HuTube' },
  { path: 'moderation/videos', canActivate: [authGuard, permissionGuard], data: { permission: 'moderation.view_queue' }, loadComponent: () => import('./features/moderation/admin-moderation-page').then(m => m.AdminModerationPage), title: 'Kiểm duyệt video · HuTube' },
  { path: 'topics', canActivate: [authGuard, permissionGuard], data: { permission: 'system.view_setting' }, loadComponent: () => import('./features/topics/admin-topics-page').then(m => m.AdminTopicsPage), title: 'Danh mục & chủ đề · HuTube' },
  { path: 'policies', canActivate: [authGuard, permissionGuard], data: { permission: 'system.view_setting' }, loadComponent: () => import('./features/policies/admin-policies-page').then(m => m.AdminPoliciesPage), title: 'Chính sách hệ thống · HuTube' },
  { path: 'account', canActivate: [authGuard], loadComponent: () => import('./features/account/account-page').then(m => m.AccountPage), title: 'Tài khoản · HuTube' },
  { path: '', pathMatch: 'full', redirectTo: 'account' },
  { path: '**', redirectTo: 'account' }
];
