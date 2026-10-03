import { Component, ElementRef, OnInit, ViewChild, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { AuthService, LoginHistoryItem, Session, errorMessage } from '../../core/auth.service';
import { AccountService, NotificationSettings, UserPreferences, UserProfile } from '../../core/account.service';
import { ChannelDetail, ChannelService } from '../../core/channel.service';
import { ThemeService } from '../../core/theme.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleCurrencyPipe } from '../../core/locale-currency.pipe';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { MyPlan, PaymentSummary, PlanService } from '../../core/plan.service';
import { TranslatePipe } from '../../core/translate.pipe';

export type AccountTab =
  | 'account'
  | 'notifications'
  | 'downloads'
  | 'privacy'
  | 'billing'
  | 'advanced';

interface SessionGroup {
  key: string;
  latest: Session;
  count: number;
  isCurrent: boolean;
}

@Component({
  selector: 'app-account-page',
  imports: [LocaleCurrencyPipe, LocaleDatePipe, LocaleNumberPipe, FormsModule, RouterLink, TranslatePipe],
  templateUrl: './account-page.html',
  styleUrl: './account-page.scss'
})
export class AccountPage implements OnInit {
  readonly auth = inject(AuthService);
  readonly account = inject(AccountService);
  readonly channelService = inject(ChannelService);
  readonly themeService = inject(ThemeService);
  readonly i18n = inject(I18nService);
  readonly planService = inject(PlanService);
  private router = inject(Router);

  @ViewChild('avatarInput') avatarInput?: ElementRef<HTMLInputElement>;

  readonly activeTab = signal<AccountTab>('account');
  readonly loading = signal(true);
  readonly myChannel = signal<ChannelDetail | null>(null);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly message = signal('');

  // Billing data is loaded only when the user opens the billing tab/history.
  readonly currentPlan = signal<MyPlan | null>(null);
  readonly currentPlanLoading = signal(false);
  readonly currentPlanLoaded = signal(false);
  readonly billingPlanError = signal('');
  readonly purchaseHistoryVisible = signal(false);
  readonly paymentHistoryVisible = signal(false);
  readonly billingPayments = signal<PaymentSummary[]>([]);
  readonly billingPaymentsLoading = signal(false);
  readonly billingPaymentsLoaded = signal(false);
  readonly billingPaymentsError = signal('');
  readonly purchases = computed(() => this.billingPayments().filter(payment => payment.status.toLowerCase() === 'paid'));

  // Privacy toggles matching YouTube Image 2
  readonly keepSubscriptionsPrivate = signal(true);
  readonly allowMentions = signal(true);
  readonly topFanRanking = signal(true);
  readonly celebrateSuperChat = signal(true);

  // Downloads settings matching screenshot
  readonly downloadQuality = signal<'ask' | '1080p' | '720p' | '480p' | '144p'>('480p');
  readonly smartDownloads = signal(false);

  // Modals / toggles for account edit
  readonly editingProfile = signal(false);
  readonly changingPassword = signal(false);

  // Profile Form
  readonly profile = signal<UserProfile | null>(null);
  displayName = '';
  bio = '';
  location = this.i18n.t('account.locationVietnam');

  // Password Form
  currentPassword = '';
  newPassword = '';
  confirmPassword = '';

  // Notifications
  notifications: NotificationSettings = {
    inAppEnabled: true,
    emailEnabled: true,
    newVideoEnabled: true,
    commentReplyEnabled: true,
    reportResultEnabled: true,
    moderationEnabled: true,
    planEnabled: true,
    recommendationEnabled: true,
    mentionEnabled: true,
    channelActivityEnabled: true,
    paymentEnabled: true
  };

  // Preferences
  preferences: UserPreferences = {
    language: 'vi',
    theme: 'dark',
    keepSubscriptionsPrivate: true,
    keepPlaylistsPrivate: true,
    location: this.i18n.t('account.locationVietnam')
  };

  // Sessions
  readonly sessions = signal<Session[]>([]);
  readonly sessionGroups = computed<SessionGroup[]>(() => {
    const groups = new Map<string, Session[]>();
    for (const session of this.sessions()) {
      const deviceId = session.deviceId?.trim();
      const key = deviceId ? `${session.platform}:${deviceId}` : `session:${session.sessionId}`;
      const items = groups.get(key) ?? [];
      items.push(session);
      groups.set(key, items);
    }
    return [...groups.entries()].map(([key, items]) => {
      const latest = items.reduce((newest, item) => Date.parse(item.issuedAt) > Date.parse(newest.issuedAt) ? item : newest);
      return { key, latest, count: items.length, isCurrent: items.some(item => item.isCurrent) };
    }).sort((left, right) => Date.parse(right.latest.issuedAt) - Date.parse(left.latest.issuedAt));
  });
  readonly pendingRevoke = signal<Session | null>(null);
  readonly loginHistoryVisible = signal(false);
  readonly loginHistoryLoading = signal(false);
  readonly loginHistoryLoaded = signal(false);
  readonly loginHistoryItems = signal<LoginHistoryItem[]>([]);
  readonly loginHistoryPage = signal(1);
  readonly loginHistoryTotal = signal(0);
  readonly loginHistoryPageSize = 20;
  readonly loginHistoryPageCount = computed(() => Math.max(1, Math.ceil(this.loginHistoryTotal() / this.loginHistoryPageSize)));
  readonly apiState = signal(this.i18n.t('account.apiChecking'));

  constructor() {
    this.topFanRanking.set(localStorage.getItem('hutube.privacy.topFanRanking') !== 'false');
    this.celebrateSuperChat.set(localStorage.getItem('hutube.privacy.celebrateSuperChat') !== 'false');
    const savedQuality = localStorage.getItem('hutube.downloads.quality') as 'ask' | '1080p' | '720p' | '480p' | '144p' | null;
    if (savedQuality) {
      this.downloadQuality.set(savedQuality);
    }
    this.smartDownloads.set(localStorage.getItem('hutube.downloads.smart') === 'true');
    this.loadAll();
    this.auth.info().subscribe({
      next: () => this.apiState.set(this.i18n.t('account.apiConnected')),
      error: () => this.apiState.set(this.i18n.t('account.apiUnavailable'))
    });
  }

  ngOnInit() {}

  setTab(tab: AccountTab) {
    this.activeTab.set(tab);
    this.error.set('');
    this.message.set('');
    if (tab === 'billing') this.loadCurrentPlan();
  }

  loadCurrentPlan() {
    if (this.currentPlanLoaded() || this.currentPlanLoading()) return;
    this.currentPlanLoading.set(true);
    this.billingPlanError.set('');
    this.planService.getMyPlan().pipe(finalize(() => this.currentPlanLoading.set(false))).subscribe({
      next: plan => {
        this.currentPlan.set(plan);
        this.currentPlanLoaded.set(true);
      },
      error: err => this.billingPlanError.set(errorMessage(err, this.i18n))
    });
  }

  togglePurchaseHistory() {
    const visible = !this.purchaseHistoryVisible();
    this.purchaseHistoryVisible.set(visible);
    if (visible) this.loadBillingPayments();
  }

  togglePaymentHistory() {
    const visible = !this.paymentHistoryVisible();
    this.paymentHistoryVisible.set(visible);
    if (visible) this.loadBillingPayments();
  }

  loadBillingPayments() {
    if (this.billingPaymentsLoaded() || this.billingPaymentsLoading()) return;
    this.billingPaymentsLoading.set(true);
    this.billingPaymentsError.set('');
    this.planService.getMyPayments().pipe(finalize(() => this.billingPaymentsLoading.set(false))).subscribe({
      next: payments => {
        this.billingPayments.set(payments);
        this.billingPaymentsLoaded.set(true);
      },
      error: err => this.billingPaymentsError.set(errorMessage(err, this.i18n))
    });
  }

  paymentStatusKey(status: string): string {
    const normalized = status.trim().toLowerCase();
    return ['paid', 'pending', 'failed', 'cancelled'].includes(normalized)
      ? `account.paymentStatus.${normalized}`
      : 'account.paymentStatus.unknown';
  }

  isPlanActive(plan: MyPlan): boolean {
    if (plan.subscription) return !plan.subscription.isExpired;
    if (plan.price <= 0) return true;
    return plan.activePaidPlanIds?.includes(plan.planId) ?? false;
  }

  loadAll() {
    this.loading.set(true);
    this.error.set('');

    this.account.getProfile().subscribe({
      next: p => {
        this.profile.set(p);
        this.displayName = p.displayName;
        this.bio = p.bio ?? '';
      },
      error: err => this.error.set(errorMessage(err, this.i18n))
    });

    this.account.getNotificationSettings().subscribe({
      next: n => {
        this.notifications = { ...n };
        this.allowMentions.set(n.mentionEnabled ?? true);
      },
      error: () => {}
    });

    this.account.getPreferences().subscribe({
      next: prefs => {
        this.preferences = { ...prefs };
        this.location = prefs.location ?? this.i18n.t('account.locationVietnam');
        this.keepSubscriptionsPrivate.set(prefs.keepSubscriptionsPrivate ?? true);
        if (prefs.theme === 'light' || prefs.theme === 'dark') {
          this.themeService.setTheme(prefs.theme);
        }
        if (prefs.language === 'vi' || prefs.language === 'en') {
          this.i18n.setLang(prefs.language);
        }
      },
      error: () => {}
    });

    this.channelService.getMyChannel().subscribe({
      next: ch => this.myChannel.set(ch),
      error: () => this.myChannel.set(null)
    });

    this.loadSessions();
  }

  loadSessions() {
    this.auth.sessions().pipe(finalize(() => this.loading.set(false))).subscribe({
      next: result => this.sessions.set(result.items),
      error: err => this.error.set(errorMessage(err, this.i18n))
    });
  }

  toggleLoginHistory() {
    const visible = !this.loginHistoryVisible();
    this.loginHistoryVisible.set(visible);
    if (visible && !this.loginHistoryLoaded()) this.loadLoginHistory(1);
  }

  loadLoginHistory(page: number) {
    if (this.loginHistoryLoading()) return;
    this.loginHistoryLoading.set(true);
    this.auth.loginHistory(page, this.loginHistoryPageSize).pipe(finalize(() => this.loginHistoryLoading.set(false))).subscribe({
      next: result => {
        this.loginHistoryItems.set(result.items);
        this.loginHistoryPage.set(result.page);
        this.loginHistoryTotal.set(result.total);
        this.loginHistoryLoaded.set(true);
      },
      error: err => this.error.set(errorMessage(err, this.i18n))
    });
  }

  displayIpAddress(ipAddress: string): string {
    const normalized = ipAddress.trim().toLowerCase();
    return ['::1', '0:0:0:0:0:0:0:1', '127.0.0.1', '::ffff:127.0.0.1'].includes(normalized)
      ? this.i18n.t('account.localIpAddress')
      : ipAddress;
  }

  // Privacy Toggle Handlers
  onToggleSubscriptionPrivacy(val: boolean) {
    this.keepSubscriptionsPrivate.set(val);
    this.preferences.keepSubscriptionsPrivate = val;
    this.account.updatePreferences(this.preferences).subscribe({
      next: () => {
        this.message.set(this.i18n.t('account.privacySaved'));
        setTimeout(() => this.message.set(''), 3000);
      },
      error: err => this.error.set(errorMessage(err, this.i18n))
    });
  }

  onToggleMentions(val: boolean) {
    this.allowMentions.set(val);
    this.notifications.mentionEnabled = val;
    this.account.updateNotificationSettings(this.notifications).subscribe({
      next: () => {
        this.message.set(this.i18n.t('account.privacySaved'));
        setTimeout(() => this.message.set(''), 3000);
      },
      error: err => this.error.set(errorMessage(err, this.i18n))
    });
  }

  onToggleTopFanRanking(val: boolean) {
    this.topFanRanking.set(val);
    localStorage.setItem('hutube.privacy.topFanRanking', String(val));
    this.message.set(this.i18n.t('account.privacySaved'));
    setTimeout(() => this.message.set(''), 3000);
  }

  onToggleCelebrateSuperChat(val: boolean) {
    this.celebrateSuperChat.set(val);
    localStorage.setItem('hutube.privacy.celebrateSuperChat', String(val));
    this.message.set(this.i18n.t('account.privacySaved'));
    setTimeout(() => this.message.set(''), 3000);
  }

  setDownloadQuality(quality: 'ask' | '1080p' | '720p' | '480p' | '144p') {
    this.downloadQuality.set(quality);
    localStorage.setItem('hutube.downloads.quality', quality);
    this.message.set(this.i18n.t('account.downloadQualitySaved'));
    setTimeout(() => this.message.set(''), 3000);
  }

  onToggleSmartDownloads(val: boolean) {
    this.smartDownloads.set(val);
    localStorage.setItem('hutube.downloads.smart', String(val));
    this.message.set(this.i18n.t('account.smartDownloadsSaved'));
    setTimeout(() => this.message.set(''), 3000);
  }

  clearAllDownloads() {
    localStorage.removeItem('hutube.offline.videos');
    this.message.set(this.i18n.t('account.deleteAllDownloadsSuccess'));
    setTimeout(() => this.message.set(''), 3500);
  }

  onSaveProfile() {
    if (this.busy()) return;
    this.busy.set(true);
    this.error.set('');
    this.message.set('');

    this.account.updateProfile({
      displayName: this.displayName.trim(),
      bio: this.bio.trim()
    }).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: updated => {
        this.profile.set(updated);
        this.editingProfile.set(false);
        this.message.set(this.i18n.t('account.profileSaved'));
        setTimeout(() => this.message.set(''), 3000);
      },
      error: err => this.error.set(errorMessage(err, this.i18n))
    });
  }

  triggerAvatarUpload() {
    this.avatarInput?.nativeElement.click();
  }

  onAvatarSelected(event: Event) {
    const input = event.target as HTMLInputElement;
    if (!input.files || input.files.length === 0) return;

    const file = input.files[0];
    if (file.size > 5 * 1024 * 1024) {
      this.error.set(this.i18n.t('account.avatarSizeError'));
      return;
    }

    this.busy.set(true);
    this.error.set('');
    this.account.uploadAvatar(file).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: updated => {
        this.profile.set(updated);
        this.message.set(this.i18n.t('account.avatarUpdated'));
        setTimeout(() => this.message.set(''), 3000);
      },
      error: err => this.error.set(errorMessage(err, this.i18n))
    });
  }

  onChangePassword() {
    if (this.busy()) return;
    if (!this.currentPassword) {
      this.error.set(this.i18n.t('account.enterCurrentPassword'));
      return;
    }
    if (!this.newPassword || this.newPassword.length < 10) {
      this.error.set(this.i18n.t('account.newPasswordLength'));
      return;
    }
    if (this.newPassword !== this.confirmPassword) {
      this.error.set(this.i18n.t('account.passwordsDoNotMatch'));
      return;
    }

    this.busy.set(true);
    this.error.set('');
    this.message.set('');

    this.account.changePassword({
      currentPassword: this.currentPassword,
      newPassword: this.newPassword
    }).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: res => {
        this.message.set(this.i18n.t('account.passwordChanged'));
        this.currentPassword = '';
        this.newPassword = '';
        this.confirmPassword = '';
        this.changingPassword.set(false);
        setTimeout(() => this.message.set(''), 3000);
      },
      error: err => this.error.set(errorMessage(err, this.i18n))
    });
  }

  onSaveNotifications() {
    if (this.busy()) return;
    this.busy.set(true);
    this.error.set('');
    this.message.set('');

    this.account.updateNotificationSettings(this.notifications).pipe(
      finalize(() => this.busy.set(false))
    ).subscribe({
      next: () => {
        this.message.set(this.i18n.t('account.notifSaved'));
        setTimeout(() => this.message.set(''), 3000);
      },
      error: err => this.error.set(errorMessage(err, this.i18n))
    });
  }

  onThemeChange(theme: string) {
    if (theme === 'light' || theme === 'dark') {
      this.themeService.setTheme(theme);
      this.preferences.theme = theme;
      this.account.updatePreferences(this.preferences).subscribe();
    }
  }

  onLanguageChange(lang: string) {
    if (lang === 'vi' || lang === 'en') {
      this.i18n.setLang(lang);
      this.preferences.language = lang;
      this.account.updatePreferences(this.preferences).subscribe();
    }
  }

  copyUserId(id: string) {
    navigator.clipboard.writeText(id).then(() => {
      this.message.set(this.i18n.t('account.userIdCopied'));
      setTimeout(() => this.message.set(''), 3000);
    });
  }

  logout() {
    if (this.busy()) return;
    this.busy.set(true);
    this.error.set('');
    this.auth.logout().pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => void this.router.navigate(['/login']),
      error: error => this.error.set(errorMessage(error, this.i18n) + ' ' + this.i18n.t('account.retryLogout'))
    });
  }

  logoutOthers() {
    if (this.busy()) return;
    this.busy.set(true);
    this.error.set('');
    this.auth.logoutOthers().pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => {
        this.message.set(this.i18n.t('account.loggedOutOthers'));
        this.loadSessions();
      },
      error: error => this.error.set(errorMessage(error, this.i18n))
    });
  }

  logoutAll() {
    if (this.busy()) return;
    this.busy.set(true);
    this.error.set('');
    this.auth.logoutAll().pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => void this.router.navigate(['/login'], { queryParams: { reason: 'session-revoked' } }),
      error: error => this.error.set(errorMessage(error, this.i18n))
    });
  }

  revoke() {
    const session = this.pendingRevoke();
    if (!session || this.busy()) return;
    this.busy.set(true);
    this.error.set('');
    this.auth.revoke(session.sessionId).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => {
        this.pendingRevoke.set(null);
        this.message.set(this.i18n.t('account.sessionEnded'));
        this.loadSessions();
      },
      error: error => this.error.set(errorMessage(error, this.i18n))
    });
  }
}
