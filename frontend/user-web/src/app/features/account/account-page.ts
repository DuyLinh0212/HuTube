import { Component, ElementRef, OnInit, ViewChild, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { AuthService, Session, errorMessage } from '../../core/auth.service';
import { AccountService, NotificationSettings, UserPreferences, UserProfile } from '../../core/account.service';
import { ChannelDetail, ChannelService } from '../../core/channel.service';

type AccountTab = 'profile' | 'password' | 'notifications' | 'preferences' | 'sessions';

@Component({
  selector: 'app-account-page',
  imports: [DatePipe, FormsModule, RouterLink],
  templateUrl: './account-page.html',
  styleUrl: './account-page.scss'
})
export class AccountPage {
  readonly auth = inject(AuthService);
  readonly account = inject(AccountService);
  readonly channelService = inject(ChannelService);
  private router = inject(Router);

  @ViewChild('avatarInput') avatarInput?: ElementRef<HTMLInputElement>;

  readonly activeTab = signal<AccountTab>('profile');
  readonly loading = signal(true);
  readonly myChannel = signal<ChannelDetail | null>(null);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly message = signal('');

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
    theme: 'light',
    keepSubscriptionsPrivate: true,
    keepPlaylistsPrivate: true,
    location: 'Việt Nam'
  };

  // Sessions
  readonly sessions = signal<Session[]>([]);
  readonly pendingRevoke = signal<Session | null>(null);
  readonly apiState = signal('Đang kiểm tra kết nối…');

  constructor() {
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
      next: n => this.notifications = { ...n },
      error: () => {}
    });

    this.account.getPreferences().subscribe({
      next: prefs => {
        this.preferences = { ...prefs };
        this.location = prefs.location ?? 'Việt Nam';
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
        this.message.set('Đã lưu thông tin hồ sơ thành công.');
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
      this.error.set('Kích thước ảnh đại diện tối đa là 5MB.');
      return;
    }

    this.busy.set(true);
    this.error.set('');
    this.account.uploadAvatar(file).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: updated => {
        this.profile.set(updated);
        this.message.set('Đã cập nhật ảnh đại diện mới.');
      },
      error: err => this.error.set(errorMessage(err))
    });
  }

  onChangePassword() {
    if (this.busy()) return;
    if (!this.currentPassword) {
      this.error.set('Vui lòng nhập mật khẩu hiện tại.');
      return;
    }
    if (!this.newPassword || this.newPassword.length < 10) {
      this.error.set('Mật khẩu mới cần từ 10 đến 128 ký tự.');
      return;
    }
    if (this.newPassword !== this.confirmPassword) {
      this.error.set('Mật khẩu xác nhận chưa khớp.');
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
      next: () => this.message.set('Đã lưu tùy chọn thông báo thành công.'),
      error: err => this.error.set(errorMessage(err))
    });
  }

  onSavePreferences() {
    if (this.busy()) return;
    this.busy.set(true);
    this.error.set('');
    this.message.set('');

    this.preferences.location = this.location;
    this.account.updatePreferences(this.preferences).pipe(
      finalize(() => this.busy.set(false))
    ).subscribe({
      next: updated => {
        this.preferences = { ...updated };
        this.message.set('Đã lưu cài đặt giao diện và ngôn ngữ.');
      },
      error: err => this.error.set(errorMessage(err))
    });
  }

  copyUserId(id: string) {
    navigator.clipboard.writeText(id).then(() => {
      this.message.set('Đã sao chép ID người dùng vào clipboard.');
    });
  }

  logout() {
    if (this.busy()) return;
    this.busy.set(true);
    this.error.set('');
    this.auth.logout().pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => void this.router.navigate(['/login']),
      error: error => this.error.set(errorMessage(error) + ' Hãy thử đăng xuất lại.')
    });
  }

  logoutOthers() {
    if (this.busy()) return;
    this.busy.set(true);
    this.error.set('');
    this.auth.logoutOthers().pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => {
        this.message.set('Đã đăng xuất khỏi các thiết bị khác.');
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
        this.message.set('Đã kết thúc phiên đăng nhập thiết bị.');
        this.loadSessions();
      },
      error: error => this.error.set(errorMessage(error))
    });
  }
}
