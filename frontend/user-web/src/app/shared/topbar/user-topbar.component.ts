import { Component, ElementRef, EventEmitter, HostListener, Input, OnDestroy, OnInit, Output, ViewChild, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import type { AnimationItem } from 'lottie-web';
import { AuthService } from '../../core/auth.service';
import { ChannelDetail, ChannelInvitation, ChannelService } from '../../core/channel.service';
import { ThemeService } from '../../core/theme.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';
import { AccountService, UserProfile } from '../../core/account.service';
import { ContentService } from '../../core/content.service';
import { NotificationService } from '../../core/notification.service';
import { NotificationPanelComponent } from '../notifications/notification-panel.component';
import { PlaylistService } from '../../core/playlist.service';

@Component({
  selector: 'app-user-topbar',
  imports: [LocaleNumberPipe, RouterLink, TranslatePipe, NotificationPanelComponent, FormsModule],
  templateUrl: './user-topbar.component.html',
  styleUrl: './user-topbar.component.scss'
})
export class UserTopbarComponent implements OnDestroy, OnInit {
  @Output() readonly menuOpened = new EventEmitter<void>();
  @Input() sidebarCollapsed = false;
  @ViewChild('searchInputEl') private searchInputRef?: ElementRef<HTMLInputElement>;

  readonly auth = inject(AuthService);
  readonly themeService = inject(ThemeService);
  readonly i18n = inject(I18nService);
  private channelService = inject(ChannelService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);
  private elRef = inject(ElementRef);
  private account = inject(AccountService);
  private content = inject(ContentService);
  private playlists = inject(PlaylistService);
  readonly notifications = inject(NotificationService);

  topbarSearch = '';

  submitTopbarSearch() {
    const q = this.topbarSearch.trim();
    if (!q) return;
    void this.router.navigate(['/explore'], { queryParams: { q } });
    this.searchInputRef?.nativeElement.blur();
  }

  @HostListener('window:keydown', ['$event'])
  onGlobalKeydown(e: KeyboardEvent) {
    if (e.key === '/' && document.activeElement?.tagName !== 'INPUT' && document.activeElement?.tagName !== 'TEXTAREA') {
      e.preventDefault();
      this.searchInputRef?.nativeElement.focus();
    }
  }

  readonly myChannel = signal<ChannelDetail | null>(null);
  readonly accessibleChannels = signal<ChannelDetail[]>([]);
  readonly pendingInvitations = signal<ChannelInvitation[]>([]);
  readonly collaborationChannels = computed(() => this.accessibleChannels().filter(channel => !channel.isOwner));
  readonly collaborationChannel = computed(() => this.collaborationChannels()[0] ?? null);
  readonly accountDrawerOpen = signal(false);
  readonly accountDrawerMounted = signal(false);
  readonly logoutConfirmOpen = signal(false);
  readonly notificationsOpen = signal(false);
  readonly profile = signal<UserProfile | null>(null);
  readonly likedVideoCount = signal<number | null>(null);
  readonly playlistCount = signal<number | null>(null);
  @ViewChild('logoutAnimation') private logoutAnimation?: ElementRef<HTMLSpanElement>;
  private logoutAnimationItem: AnimationItem | null = null;
  private drawerCloseTimer: ReturnType<typeof setTimeout> | null = null;
  private readonly drawerAnimationDurationMs = 500;

  readonly socialLinks = computed(() => this.readSocialLinks(this.myChannel()?.settings));

  ngOnInit() {
    this.route.queryParamMap.subscribe(params => {
      this.topbarSearch = params.get('q') ?? '';
    });

    const loadAuthenticatedContext = () => {
      this.channelService.getMyChannel().subscribe({
        next: ch => this.myChannel.set(ch),
        error: () => this.myChannel.set(null)
      });
      this.channelService.getAccessibleChannels().subscribe({
        next: channels => this.accessibleChannels.set(channels),
        error: () => this.accessibleChannels.set([])
      });
      this.channelService.getMyInvitations().subscribe({
        next: invitations => this.pendingInvitations.set(invitations),
        error: () => this.pendingInvitations.set([])
      });
      this.account.getProfile().subscribe({
        next: profile => this.profile.set(profile),
        error: () => this.profile.set(null)
      });
      this.content.liked(null, 1, 1).subscribe({
        next: result => this.likedVideoCount.set(result.total ?? result.items?.length ?? 0),
        error: () => this.likedVideoCount.set(null)
      });
      this.playlists.mine().subscribe({
        next: lists => this.playlistCount.set(lists.length),
        error: () => this.playlistCount.set(0)
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
      // Public pages may still have a valid refresh cookie. Restore it before
      // requesting profile/channel data, while keeping guests anonymous.
      this.auth.restore().subscribe({
        next: authenticated => { if (authenticated) loadAuthenticatedContext(); },
        error: () => undefined
      });
    }
  }

  toggleAccountDrawer() {
    this.notificationsOpen.set(false);
    if (this.accountDrawerOpen()) {
      this.closeAccountDrawer();
      return;
    }

    this.cancelDrawerClose();
    this.accountDrawerMounted.set(true);
    this.accountDrawerOpen.set(true);
    setTimeout(() => void this.mountLogoutAnimation());
  }

  toggleNotifications() { this.closeAccountDrawer(); this.notificationsOpen.set(!this.notificationsOpen()); if (this.notificationsOpen()) this.notifications.loadInitial(); }

  closeAccountDrawer() {
    this.accountDrawerOpen.set(false);
    this.logoutConfirmOpen.set(false);
    this.destroyLogoutAnimation();
    if (!this.accountDrawerMounted()) return;

    this.cancelDrawerClose();
    this.drawerCloseTimer = setTimeout(() => {
      this.accountDrawerMounted.set(false);
      this.drawerCloseTimer = null;
    }, this.drawerAnimationDurationMs);
  }

  openLogoutConfirm() {
    this.logoutConfirmOpen.set(true);
  }

  cancelLogout() {
    this.logoutConfirmOpen.set(false);
  }

  ngOnDestroy() {
    this.cancelDrawerClose();
    this.destroyLogoutAnimation();
  }

  private cancelDrawerClose() {
    if (this.drawerCloseTimer === null) return;
    clearTimeout(this.drawerCloseTimer);
    this.drawerCloseTimer = null;
  }

  private async mountLogoutAnimation() {
    const container = this.logoutAnimation?.nativeElement;
    if (!container || !this.accountDrawerOpen() || this.logoutAnimationItem) return;
    try {
      const { default: lottie } = await import('lottie-web');
      if (!this.accountDrawerOpen() || this.logoutAnimation?.nativeElement !== container || this.logoutAnimationItem) return;
      this.logoutAnimationItem = lottie.loadAnimation({
        container,
        renderer: 'svg',
        loop: true,
        autoplay: true,
        path: '/assets/animations/lottieflow-arrow-02-000000-easey.json',
        rendererSettings: { preserveAspectRatio: 'xMidYMid meet', className: 'logout-lottie__svg' }
      });
    } catch {
      // The button stays empty if the player cannot initialize; its aria label remains available.
    }
  }

  private destroyLogoutAnimation() {
    this.logoutAnimationItem?.destroy();
    this.logoutAnimationItem = null;
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

  channelRole(role: string | null | undefined): string {
    if (role === 'owner') return this.i18n.t('studio.roleOwner');
    return ({
      manager: 'studio.roleManager',
      editor: 'studio.roleEditor',
      moderator: 'studio.roleModerator',
      viewer: 'studio.roleViewer'
    } as Record<string, string>)[role ?? '']
      ? this.i18n.t(({ manager: 'studio.roleManager', editor: 'studio.roleEditor', moderator: 'studio.roleModerator', viewer: 'studio.roleViewer' } as Record<string, string>)[role ?? ''])
      : this.i18n.t('studio.roleContributor');
  }

  logout() {
    this.closeAccountDrawer();
    this.auth.logout().subscribe({
      next: () => void this.router.navigate(['/login']),
      error: () => void this.router.navigate(['/login'])
    });
  }

  @HostListener('document:click', ['$event'])
  onDocumentClick(event: MouseEvent) {
    if (!this.elRef.nativeElement.contains(event.target)) {
      this.closeAccountDrawer();
      this.notificationsOpen.set(false);
    }
  }

  @HostListener('document:keydown.escape')
  onEscape() {
    if (this.logoutConfirmOpen()) {
      this.cancelLogout();
      return;
    }
    this.closeAccountDrawer();
    this.notificationsOpen.set(false);
  }

  socialPlatform(url: string, platform?: string): 'instagram' | 'facebook' | 'tiktok' | 'twitter' | 'youtube' | 'link' {
    if (platform === 'instagram' || platform === 'facebook' || platform === 'tiktok') return platform;
    if (platform === 'x') return 'twitter';
    const lower = url.toLowerCase();
    if (lower.includes('instagram.com')) return 'instagram';
    if (lower.includes('facebook.com') || lower.includes('fb.com')) return 'facebook';
    if (lower.includes('tiktok.com')) return 'tiktok';
    if (lower.includes('twitter.com') || lower.includes('x.com')) return 'twitter';
    if (lower.includes('youtube.com') || lower.includes('hutube')) return 'youtube';
    return 'link';
  }

  socialLabel(url: string, title: string, platform?: string): string {
    if (title.trim()) return title.trim();
    switch (this.socialPlatform(url, platform)) {
      case 'instagram': return 'Instagram';
      case 'facebook': return 'Facebook';
      case 'tiktok': return 'TikTok';
      case 'twitter': return 'X / Twitter';
      case 'youtube': return 'YouTube';
      default: return this.i18n.t('channel.platform.other');
    }
  }

  private readSocialLinks(settings: string | null | undefined): Array<{ platform?: string; title: string; url: string }> {
    if (!settings) return [];
    try {
      const parsed = JSON.parse(settings) as { links?: unknown };
      if (!Array.isArray(parsed?.links)) return [];
      return parsed.links
        .filter((link): link is { platform?: unknown; title?: unknown; url?: unknown } => !!link && typeof link === 'object')
        .map(link => ({ platform: typeof link.platform === 'string' ? link.platform : undefined, title: typeof link.title === 'string' ? link.title : '', url: typeof link.url === 'string' ? link.url : '' }))
        .filter(link => /^https?:\/\//i.test(link.url))
        .slice(0, 5);
    } catch {
      return [];
    }
  }
}
