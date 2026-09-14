import { Component, ElementRef, OnInit, ViewChild, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { AuthService, Session, errorMessage } from '../../core/auth.service';
import { AccountService, NotificationSettings, UserPreferences, UserProfile } from '../../core/account.service';
import { ChannelDetail, ChannelService } from '../../core/channel.service';
import { ThemeService } from '../../core/theme.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';

export type AccountTab =
  | 'account'
  | 'notifications'
  | 'downloads'
  | 'privacy'
  | 'billing'
  | 'advanced';

@Component({
  selector: 'app-account-page',
  imports: [DatePipe, FormsModule, RouterLink, TranslatePipe],
  templateUrl: './account-page.html',
  styleUrl: './account-page.scss'
})
export class AccountPage implements OnInit {
  readonly auth = inject(AuthService);
  readonly account = inject(AccountService);
  readonly channelService = inject(ChannelService);
  readonly themeService = inject(ThemeService);
  readonly i18n = inject(I18nService);
  private router = inject(Router);

  @ViewChild('avatarInput') avatarInput?: ElementRef<HTMLInputElement>;

  readonly activeTab = signal<AccountTab>('account');
  readonly loading = signal(true);
  readonly myChannel = signal<ChannelDetail | null>(null);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly message = signal('');

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
  location = 'Việt Nam';

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
    location: 'Việt Nam'
  };

  // Sessions
  readonly sessions = signal<Session[]>([]);
  readonly pendingRevoke = signal<Session | null>(null);
  readonly apiState = signal('Đang kiểm tra kết nối…');

  ngOnInit() {
    this.topFanRanking.set(localStorage.getItem('hutube.privacy.topFanRanking') !== 'false');
    this.celebrateSuperChat.set(localStorage.getItem('hutube.privacy.celebrateSuperChat') !== 'false');
    const savedQuality = localStorage.getItem('hutube.downloads.quality') as 'ask' | '1080p' | '720p' | '480p' | '144p' | null;
    if (savedQuality) {
      this.downloadQuality.set(savedQuality);
    }
    this.smartDownloads.set(localStorage.getItem('hutube.downloads.smart') === 'true');
    this.loadAll();
    this.auth.info().subscribe({
      next: () => this.apiState.set('Đã kết nối'),
      error: () => this.apiState.set('Chưa kết nối được máy chủ')
    });
  }

  setTab(tab: AccountTab) {
    this.activeTab.set(tab);
    this.error.set('');
    this.message.set('');
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
      error: err => this.error.set(errorMessage(err))
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
        this.location = prefs.location ?? 'Việt Nam';
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
      error: err => this.error.set(errorMessage(err))
    });
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
      error: err => this.error.set(errorMessage(err))
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
      error: err => this.error.set(errorMessage(err))
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
      error: err => this.error.set(errorMessage(err))
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
      error: err => this.error.set(errorMessage(err))
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
        this.message.set(res.message);
        this.currentPassword = '';
        this.newPassword = '';
        this.confirmPassword = '';
        this.changingPassword.set(false);
        setTimeout(() => this.message.set(''), 3000);
      },
      error: err => this.error.set(errorMessage(err))
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
      error: err => this.error.set(errorMessage(err))
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
      error: error => this.error.set(errorMessage(error) + ' ' + this.i18n.t('account.retryLogout'))
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
      error: error => this.error.set(errorMessage(error))
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
      error: error => this.error.set(errorMessage(error))
    });
  }
}
