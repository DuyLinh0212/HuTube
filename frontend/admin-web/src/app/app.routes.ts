import { Routes } from '@angular/router';
import { authGuard } from './core/auth.guard';
import { ADMIN_APP } from './core/runtime-config';
const authPage = () => import('./features/auth/auth-page').then(m => m.AuthPage);
export const routes: Routes = [
  { path: 'login', loadComponent: authPage, title: 'Đăng nhập · HuTube' },
  ...(!ADMIN_APP ? [{ path: 'register', loadComponent: authPage, title: 'Đăng ký · HuTube' }] : []),
  { path: 'verify-email', loadComponent: authPage, title: 'Xác minh email · HuTube' },
  { path: 'forgot-password', loadComponent: authPage, title: 'Quên mật khẩu · HuTube' },
  { path: 'reset-password', loadComponent: authPage, title: 'Đặt lại mật khẩu · HuTube' },
  { path: 'account', canActivate: [authGuard], loadComponent: () => import('./features/account/account-page').then(m => m.AccountPage), title: 'Tài khoản · HuTube' },
  { path: '', pathMatch: 'full', redirectTo: 'account' },
  { path: '**', redirectTo: 'account' }
];
