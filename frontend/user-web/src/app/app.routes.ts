import { Routes } from '@angular/router';
import { authGuard } from './core/auth.guard';
import { ADMIN_APP } from './core/runtime-config';
import { studioChannelGuard } from './core/studio-channel.guard';

const authPage = () => import('./features/auth/auth-page').then(m => m.AuthPage);

export const routes: Routes = [
  { path: 'login', loadComponent: authPage, title: 'Đăng nhập · HuTube' },
  ...(!ADMIN_APP ? [{ path: 'register', loadComponent: authPage, title: 'Đăng ký · HuTube' }] : []),
  { path: 'verify-email', loadComponent: authPage, title: 'Xác minh email · HuTube' },
  { path: 'forgot-password', loadComponent: authPage, title: 'Quên mật khẩu · HuTube' },
  { path: 'reset-password', loadComponent: authPage, title: 'Đặt lại mật khẩu · HuTube' },

  { path: 'home', loadComponent: () => import('./features/video/home-page').then(m => m.HomePage), title: 'Trang chủ · HuTube' },
  { path: 'explore', loadComponent: () => import('./features/video/home-page').then(m => m.HomePage), title: 'Khám phá · HuTube' },
  { path: 'watch/:id', loadComponent: () => import('./features/video/watch-page').then(m => m.WatchPage), title: 'Xem video · HuTube' },
  { path: 'terms', loadComponent: () => import('./features/policy/public-policy-page').then(m => m.PublicPolicyPage), title: 'Điều khoản dịch vụ · HuTube' },
  { path: 'privacy', loadComponent: () => import('./features/policy/public-policy-page').then(m => m.PublicPolicyPage), title: 'Chính sách bảo mật · HuTube' },
  { path: 'guidelines', loadComponent: () => import('./features/policy/public-policy-page').then(m => m.PublicPolicyPage), title: 'Tiêu chuẩn cộng đồng · HuTube' },
  { path: 'policies', loadComponent: () => import('./features/policy/public-policy-page').then(m => m.PublicPolicyPage), title: 'Trung tâm chính sách · HuTube' },
  { path: 'plans', loadComponent: () => import('./features/plans/plans-page').then(m => m.PlansPage), title: 'Gói dịch vụ · HuTube' },
  { path: 'plans/accept-invite', loadComponent: () => import('./features/plans/plan-invite-accept-page').then(m => m.PlanInviteAcceptPage), title: 'Nhận lời mời gói · HuTube' },
  { path: 'plans/:planId', loadComponent: () => import('./features/plans/plan-detail-page').then(m => m.PlanDetailPage), title: 'Chi tiết gói · HuTube' },
  { path: '', pathMatch: 'full', redirectTo: 'home' },

  {
    path: '',
    canActivate: [authGuard],
    children: [
      { path: 'profile', redirectTo: 'account', pathMatch: 'full' },
      { path: 'library', redirectTo: 'history', pathMatch: 'full' },
      { path: 'account', loadComponent: () => import('./features/account/account-page').then(m => m.AccountPage), title: 'Cài đặt · HuTube' },
      { path: 'my-plan', redirectTo: 'plans', pathMatch: 'full' },
      { path: 'history', data: { library: 'history' }, loadComponent: () => import('./features/library/library-page').then(m => m.LibraryPage), title: 'Lịch sử xem · HuTube' },
      { path: 'liked', data: { library: 'liked' }, loadComponent: () => import('./features/library/library-page').then(m => m.LibraryPage), title: 'Video đã thích · HuTube' },
      { path: 'channel/create', loadComponent: () => import('./features/channel/channel-create-page').then(m => m.ChannelCreatePage), title: 'Tạo kênh · HuTube' },
      { path: 'channel-invitations', loadComponent: () => import('./features/channel/channel-invitations-page').then(m => m.ChannelInvitationsPage), title: 'Lời mời kênh · HuTube' },
      { path: 'channel/:handle', loadComponent: () => import('./features/channel/channel-page').then(m => m.ChannelPage), title: 'Kênh · HuTube' },
      { path: 'channel/:handle/customize', loadComponent: () => import('./features/channel/channel-settings-page').then(m => m.ChannelSettingsPage), title: 'Tùy chỉnh kênh · HuTube' },
      {
        path: 'studio',
        children: [
          { path: 'setup', loadComponent: () => import('./features/studio/pages/studio-setup-page').then(m => m.StudioSetupPage), title: 'Thiết lập kênh · Studio' },
          { path: 'overview', canActivate: [studioChannelGuard], loadComponent: () => import('./features/studio/pages/studio-overview-page').then(m => m.StudioOverviewPage), title: 'Creator Studio · HuTube' },
          { path: 'content', canActivate: [studioChannelGuard], loadComponent: () => import('./features/studio/pages/studio-content-page').then(m => m.StudioContentPage), title: 'Nội dung kênh · Studio' },
          { path: 'upload', canActivate: [studioChannelGuard], loadComponent: () => import('./features/studio/upload/video-upload-wizard.component').then(m => m.VideoUploadWizardComponent), title: 'Tải lên video · Studio' },
          { path: 'analytics', canActivate: [studioChannelGuard], loadComponent: () => import('./features/studio/pages/studio-analytics-page').then(m => m.StudioAnalyticsPage), title: 'Số liệu phân tích · Studio' },
          { path: 'comments', canActivate: [studioChannelGuard], loadComponent: () => import('./features/studio/pages/studio-comments-page').then(m => m.StudioCommentsPage), title: 'Bình luận · Studio' },
          { path: 'subtitles', canActivate: [studioChannelGuard], loadComponent: () => import('./features/studio/pages/studio-subtitles-page').then(m => m.StudioSubtitlesPage), title: 'Phụ đề · Studio' },
          { path: 'settings', canActivate: [studioChannelGuard], loadComponent: () => import('./features/studio/pages/studio-settings-page').then(m => m.StudioSettingsPage), title: 'Cài đặt · Studio' },
          { path: 'invitations', loadComponent: () => import('./features/channel/channel-invitations-page').then(m => m.ChannelInvitationsPage), title: 'Lời mời kênh · Studio' },
          { path: '', pathMatch: 'full', redirectTo: 'overview' }
        ]
      },
    ]
  },

  { path: '**', redirectTo: 'home' }
];
