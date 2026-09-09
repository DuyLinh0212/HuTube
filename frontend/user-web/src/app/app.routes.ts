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

  {
    path: '',
    canActivate: [authGuard],
    children: [
      { path: 'account', loadComponent: () => import('./features/account/account-page').then(m => m.AccountPage), title: 'Hồ sơ · HuTube' },
      { path: 'channel/create', loadComponent: () => import('./features/channel/channel-create-page').then(m => m.ChannelCreatePage), title: 'Tạo kênh · HuTube' },
      { path: 'channel/:handle', loadComponent: () => import('./features/channel/channel-page').then(m => m.ChannelPage), title: 'Kênh · HuTube' },
      { path: 'channel/:handle/customize', loadComponent: () => import('./features/channel/channel-settings-page').then(m => m.ChannelSettingsPage), title: 'Tùy chỉnh kênh · HuTube' },
      { path: '', pathMatch: 'full', redirectTo: 'account' }
    ]
  },

  { path: '**', redirectTo: 'account' }
];
