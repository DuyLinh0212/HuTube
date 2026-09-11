import { Component, ElementRef, EventEmitter, HostListener, OnInit, Output, inject, signal } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { ChannelDetail, ChannelService } from '../../core/channel.service';
import { ThemeService } from '../../core/theme.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';
import { AccountService, UserProfile } from '../../core/account.service';
import { NotificationService } from '../../core/notification.service';
import { NotificationPanelComponent } from '../../shared/notifications/notification-panel.component';

@Component({
  selector: 'app-studio-topbar',
  imports: [RouterLink, TranslatePipe, NotificationPanelComponent],
  templateUrl: './studio-topbar.component.html',
  styleUrl: './studio-topbar.component.scss'
})
export class StudioTopbarComponent implements OnInit {
  @Output() readonly menuOpened = new EventEmitter<void>();

  readonly auth = inject(AuthService);
  readonly themeService = inject(ThemeService);
  readonly i18n = inject(I18nService);
  private channelService = inject(ChannelService);
  private router = inject(Router);
  private elRef = inject(ElementRef);
  private account = inject(AccountService);
  readonly notifications = inject(NotificationService);

  readonly myChannel = signal<ChannelDetail | null>(null);
  readonly dropdownOpen = signal(false);
  readonly notificationsOpen = signal(false);
  readonly profile = signal<UserProfile | null>(null);

  ngOnInit() {
    const loadAuthenticatedContext = () => {
      this.channelService.getMyChannel().subscribe({
        next: ch => this.myChannel.set(ch),
        error: () => this.myChannel.set(null)
      });
      this.account.getProfile().subscribe({
        next: profile => this.profile.set(profile),
        error: () => this.profile.set(null)
      });
      this.account.getPreferences().subscribe({
        next: preferences => {
          if (preferences.theme === 'light' || preferences.theme === 'dark') this.themeService.setTheme(preferences.theme);
          if (preferences.language === 'vi' || preferences.language === 'en') this.i18n.setLang(preferences.language);
        },
        error: () => undefined
      });
      void this.notifications.connect();
    };

    if (this.auth.user()) {
      loadAuthenticatedContext();
    } else {
      this.auth.restore().subscribe({
        next: authenticated => { if (authenticated) loadAuthenticatedContext(); },
        error: () => undefined
      });
    }
  }

  toggleDropdown() {
    this.notificationsOpen.set(false);
    this.dropdownOpen.update(v => !v);
  }

  toggleNotifications() { this.dropdownOpen.set(false); this.notificationsOpen.update(value => !value); if (this.notificationsOpen()) this.notifications.loadInitial(); }

  closeDropdown() {
    this.dropdownOpen.set(false);
  }

  toggleTheme() {
    const theme = this.themeService.toggleTheme();
    this.account.updatePreferences({ theme }).subscribe();
  }

  toggleLanguage() {
    const next = this.i18n.currentLang() === 'vi' ? 'en' : 'vi';
    this.i18n.setLang(next);
    this.account.updatePreferences({ language: next }).subscribe();
  }

  logout() {
    this.closeDropdown();
    this.auth.logout().subscribe({
      next: () => void this.router.navigate(['/login']),
      error: () => void this.router.navigate(['/login'])
    });
  }

  @HostListener('document:click', ['$event'])
  onDocumentClick(event: MouseEvent) {
    if (!this.elRef.nativeElement.contains(event.target)) {
      this.closeDropdown();
      this.notificationsOpen.set(false);
    }
  }
}
