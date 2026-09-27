import { Routes } from '@angular/router';
import { authGuard } from './core/auth.guard';
import { permissionGuard } from './core/permission.guard';
import { superAdminGuard } from './core/super-admin.guard';
import { ADMIN_APP } from './core/runtime-config';
const authPage = () => import('./features/auth/auth-page').then(m => m.AuthPage);
export const routes: Routes = [
  { path: 'login', loadComponent: authPage, title: 'route.title.login' },
  ...(!ADMIN_APP ? [{ path: 'register', loadComponent: authPage, title: 'route.title.register' }] : []),
  { path: 'verify-email', loadComponent: authPage, title: 'route.title.verifyEmail' },
  { path: 'forgot-password', loadComponent: authPage, title: 'route.title.forgotPassword' },
  { path: 'reset-password', loadComponent: authPage, title: 'route.title.resetPassword' },
  { path: 'forbidden', loadComponent: () => import('./features/error/forbidden-page').then(m => m.ForbiddenPage), title: 'route.title.forbidden' },
  { path: 'users', canActivate: [authGuard, permissionGuard], data: { permission: 'user.view' }, loadComponent: () => import('./features/users/admin-users-page').then(m => m.AdminUsersPage), title: 'route.title.users' },
  { path: 'channels', canActivate: [authGuard, permissionGuard], data: { permission: 'channel.view' }, loadComponent: () => import('./features/channels/admin-channels-page').then(m => m.AdminChannelsPage), title: 'route.title.channels' },
  { path: 'videos', canActivate: [authGuard, permissionGuard], data: { permission: 'video.view' }, loadComponent: () => import('./features/videos/admin-videos-page').then(m => m.AdminVideosPage), title: 'route.title.videos' },
  { path: 'roles', canActivate: [authGuard, permissionGuard], data: { permission: 'role.view' }, loadComponent: () => import('./features/rbac/admin-rbac-page').then(m => m.AdminRbacPage), title: 'route.title.roles' },
  { path: 'plans', canActivate: [authGuard, permissionGuard], data: { permission: 'plan.view' }, loadComponent: () => import('./features/plans/admin-plans-page').then(m => m.AdminPlansPage), title: 'route.title.plans' },
  { path: 'moderation/videos', canActivate: [authGuard, permissionGuard], data: { permission: 'moderation.view_queue' }, loadComponent: () => import('./features/moderation/admin-moderation-page').then(m => m.AdminModerationPage), title: 'route.title.moderationVideos' },
  { path: 'moderation/reports', canActivate: [authGuard, permissionGuard], data: { permission: 'report.view' }, loadComponent: () => import('./features/moderation/admin-reports-page').then(m => m.AdminReportsPage), title: 'route.title.reports' },
  { path: 'moderation/appeals', canActivate: [authGuard, permissionGuard], data: { permission: 'appeal.view' }, loadComponent: () => import('./features/moderation/admin-appeals-page').then(m => m.AdminAppealsPage), title: 'route.title.appeals' },
  { path: 'moderation/strikes', canActivate: [authGuard, permissionGuard], data: { permission: 'strike.view' }, loadComponent: () => import('./features/moderation/admin-strikes-page').then(m => m.AdminStrikesPage), title: 'route.title.strikes' },
  { path: 'topics', canActivate: [authGuard, permissionGuard], data: { permissionsAny: ['system.view_setting', 'taxonomy.manage'] }, loadComponent: () => import('./features/topics/admin-topics-page').then(m => m.AdminTopicsPage), title: 'route.title.topics' },
  { path: 'cf-seeder', canActivate: [authGuard, permissionGuard], data: { permission: 'cf_seed.manage' }, loadComponent: () => import('./features/cf-seeder/cf-seeder-page').then(m => m.CfSeederPage), title: 'route.title.cfSeeder' },
  { path: 'recommendations', canActivate: [authGuard, superAdminGuard], loadComponent: () => import('./features/recommendations/recommendations-page').then(m => m.RecommendationsPage), title: 'route.title.recommendations' },
  { path: 'policies', canActivate: [authGuard, permissionGuard], data: { permissionsAny: ['system.view_setting', 'policy.view', 'moderation.review', 'moderation.view_queue'] }, loadComponent: () => import('./features/policies/admin-policies-page').then(m => m.AdminPoliciesPage), title: 'route.title.policies' },
  { path: 'account', canActivate: [authGuard], loadComponent: () => import('./features/account/account-page').then(m => m.AccountPage), title: 'route.title.account' },
  { path: '', pathMatch: 'full', redirectTo: 'account' },
  { path: '**', redirectTo: 'account' }
];
