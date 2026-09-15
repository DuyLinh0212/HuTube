import { Routes } from '@angular/router';
import { authGuard } from './core/auth.guard';
import { ADMIN_APP } from './core/runtime-config';
import { studioChannelGuard } from './core/studio-channel.guard';
import { studioPermissionGuard } from './core/studio-permission.guard';

const authPage = () => import('./features/auth/auth-page').then(m => m.AuthPage);

export const routes: Routes = [
  { path: 'login', loadComponent: authPage },
  ...(!ADMIN_APP ? [{ path: 'register', loadComponent: authPage }] : []),
  { path: 'verify-email', loadComponent: authPage },
  { path: 'forgot-password', loadComponent: authPage },
  { path: 'reset-password', loadComponent: authPage },

  { path: 'home', loadComponent: () => import('./features/home/home-page').then(m => m.HomePage) },
  { path: 'explore', loadComponent: () => import('./features/explore/explore-page').then(m => m.ExplorePage) },
  { path: 'watch/:id', loadComponent: () => import('./features/video/watch-page').then(m => m.WatchPage) },
  { path: 'terms', loadComponent: () => import('./features/policy/public-policy-page').then(m => m.PublicPolicyPage) },
  { path: 'privacy', loadComponent: () => import('./features/policy/public-policy-page').then(m => m.PublicPolicyPage) },
  { path: 'guidelines', loadComponent: () => import('./features/policy/public-policy-page').then(m => m.PublicPolicyPage) },
  { path: 'policies', loadComponent: () => import('./features/policy/public-policy-page').then(m => m.PublicPolicyPage) },
  { path: 'plans', loadComponent: () => import('./features/plans/plans-page').then(m => m.PlansPage) },
  { path: 'plans/accept-invite', loadComponent: () => import('./features/plans/plan-invite-accept-page').then(m => m.PlanInviteAcceptPage) },
  { path: 'plans/:planId', loadComponent: () => import('./features/plans/plan-detail-page').then(m => m.PlanDetailPage) },
  { path: '', pathMatch: 'full', redirectTo: 'home' },

  {
    path: '',
    canActivate: [authGuard],
    children: [
      { path: 'profile', redirectTo: 'account', pathMatch: 'full' },
      { path: 'library', redirectTo: 'history', pathMatch: 'full' },
      { path: 'account', loadComponent: () => import('./features/account/account-page').then(m => m.AccountPage) },
      { path: 'my-plan', redirectTo: 'plans', pathMatch: 'full' },
      { path: 'history', data: { library: 'history' }, loadComponent: () => import('./features/library/library-page').then(m => m.LibraryPage) },
      { path: 'liked', data: { library: 'liked' }, loadComponent: () => import('./features/library/library-page').then(m => m.LibraryPage) },
      { path: 'channel/create', loadComponent: () => import('./features/channel/channel-create-page').then(m => m.ChannelCreatePage) },
      { path: 'channel-invitations', pathMatch: 'full', redirectTo: 'studio/invitations' },
      { path: 'channel/:handle', loadComponent: () => import('./features/channel/channel-page').then(m => m.ChannelPage) },
      { path: 'channel/:handle/customize', loadComponent: () => import('./features/channel/channel-settings-page').then(m => m.ChannelSettingsPage) },
      {
        path: 'studio',
        children: [
          { path: 'setup', loadComponent: () => import('./features/studio/pages/studio-setup-page').then(m => m.StudioSetupPage) },
          { path: 'overview', canActivate: [studioChannelGuard], loadComponent: () => import('./features/studio/pages/studio-overview-page').then(m => m.StudioOverviewPage) },
          { path: 'content', canActivate: [studioChannelGuard], loadComponent: () => import('./features/studio/pages/studio-content-page').then(m => m.StudioContentPage) },
          { path: 'upload', canActivate: [studioChannelGuard, studioPermissionGuard], data: { studioPermissions: 'video.upload' }, loadComponent: () => import('./features/studio/upload/video-upload-wizard.component').then(m => m.VideoUploadWizardComponent) },
          { path: 'analytics', canActivate: [studioChannelGuard, studioPermissionGuard], data: { studioPermissions: 'analytics.view' }, loadComponent: () => import('./features/studio/pages/studio-analytics-page').then(m => m.StudioAnalyticsPage) },
          { path: 'comments', canActivate: [studioChannelGuard, studioPermissionGuard], data: { studioPermissions: 'comment.manage' }, loadComponent: () => import('./features/studio/pages/studio-comments-page').then(m => m.StudioCommentsPage) },
          { path: 'subtitles', canActivate: [studioChannelGuard], loadComponent: () => import('./features/studio/pages/studio-subtitles-page').then(m => m.StudioSubtitlesPage) },
          { path: 'settings', canActivate: [studioChannelGuard, studioPermissionGuard], data: { studioPermissions: ['channel.setting.view', 'channel.setting.edit'] }, loadComponent: () => import('./features/studio/pages/studio-settings-page').then(m => m.StudioSettingsPage) },
          { path: 'invitations', loadComponent: () => import('./features/channel/channel-invitations-page').then(m => m.ChannelInvitationsPage) },
          { path: '', pathMatch: 'full', redirectTo: 'overview' }
        ]
      },
    ]
  },

  { path: '**', redirectTo: 'home' }
];
