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
  @ViewChild('shortcutsTrigger') private shortcutsTrigger?: ElementRef<HTMLButtonElement>;
  @ViewChild('shortcutsCloseButton') private shortcutsCloseButton?: ElementRef<HTMLButtonElement>;

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
    const current = this.router.parseUrl(this.router.url);
    const path = current.root.children['primary']?.segments.map(segment => segment.path).join('/');
    const channelMode = (path === 'explore' || path === 'search') && current.queryParams['type'] === 'channels';
    void this.router.navigate(['/search'], { queryParams: { q, type: channelMode ? 'channels' : null } });
    this.searchInputRef?.nativeElement.blur();
  }

  @HostListener('window:keydown', ['$event'])
  onGlobalKeydown(e: KeyboardEvent) {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      this.searchInputRef?.nativeElement.focus();
      this.searchInputRef?.nativeElement.select();
      return;
    }
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
  readonly accountDrawerReady = signal(false);
  readonly accountDrawerDragX = signal(0);
  readonly accountDrawerDragging = signal(false);
  readonly accountDrawerSettling = signal(false);
  readonly logoutConfirmOpen = signal(false);
  readonly shortcutsDialogOpen = signal(false);
  readonly notificationsOpen = signal(false);
  readonly profile = signal<UserProfile | null>(null);
  readonly likedVideoCount = signal<number | null>(null);
  readonly playlistCount = signal<number | null>(null);
  readonly subscribedChannelCount = signal<number | null>(null);
  @ViewChild('logoutAnimation') private logoutAnimation?: ElementRef<HTMLSpanElement>;
  private logoutAnimationItem: AnimationItem | null = null;
  private drawerCloseTimer: ReturnType<typeof setTimeout> | null = null;
  private drawerEntranceTimer: ReturnType<typeof setTimeout> | null = null;
  private drawerSettleTimer: ReturnType<typeof setTimeout> | null = null;
  private drawerPointerId: number | null = null;
  private drawerPointerStartX = 0;
  private drawerPointerStartY = 0;
  private drawerPointerStartTime = 0;
  private drawerPointerAxis: 'pending' | 'horizontal' | 'vertical' | null = null;
  private readonly drawerAnimationDurationMs = 500;

  readonly socialLinks = computed(() => {
    const channel = this.myChannel();
    return this.readSocialLinks(channel?.settings, channel?.channelId);
  });

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
      this.channelService.getSubscribedChannels().subscribe({
        next: channels => this.subscribedChannelCount.set(channels.length),
        error: () => this.subscribedChannelCount.set(null)
      });
      const preferencesVersion = this.account.preferencesVersion;
      this.account.getPreferences().subscribe({
        next: preferences => {
          if (preferencesVersion !== this.account.preferencesVersion) return;
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

    this.refreshMyChannel();
    this.cancelDrawerClose();
    this.resetDrawerGesture();
    this.accountDrawerReady.set(false);
    this.accountDrawerMounted.set(true);
    this.accountDrawerOpen.set(true);
    if (this.drawerEntranceTimer) clearTimeout(this.drawerEntranceTimer);
    this.drawerEntranceTimer = setTimeout(() => {
      this.drawerEntranceTimer = null;
      if (this.accountDrawerOpen()) this.accountDrawerReady.set(true);
    }, this.drawerAnimationDurationMs);
    setTimeout(() => void this.mountLogoutAnimation());
  }

  toggleNotifications() { this.closeAccountDrawer(); this.notificationsOpen.set(!this.notificationsOpen()); if (this.notificationsOpen()) this.notifications.loadInitial(); }

  closeAccountDrawer() {
    this.resetDrawerGesture();
    this.accountDrawerOpen.set(false);
    this.logoutConfirmOpen.set(false);
    this.shortcutsDialogOpen.set(false);
    this.destroyLogoutAnimation();
    if (!this.accountDrawerMounted()) return;

    this.cancelDrawerClose();
    this.drawerCloseTimer = setTimeout(() => {
      this.accountDrawerMounted.set(false);
      this.drawerCloseTimer = null;
    }, this.drawerAnimationDurationMs);
  }

  onDrawerPointerDown(event: PointerEvent) {
    if (!this.accountDrawerOpen() || !event.isPrimary || (event.pointerType === 'mouse' && event.button !== 0)) return;
    const target = event.target instanceof Element ? event.target : null;
    if (target?.closest('a, button, input, select, textarea, label, [role="button"], [role="link"], [contenteditable="true"]')) return;
    this.drawerPointerId = event.pointerId;
    this.drawerPointerStartX = event.clientX;
    this.drawerPointerStartY = event.clientY;
    this.drawerPointerStartTime = event.timeStamp;
    this.drawerPointerAxis = 'pending';
    try { target?.setPointerCapture(event.pointerId); } catch { /* Pointer capture is optional on older browsers. */ }
  }

  onDrawerPointerMove(event: PointerEvent) {
    if (this.drawerPointerId !== event.pointerId || !this.accountDrawerOpen()) return;
    const deltaX = event.clientX - this.drawerPointerStartX;
    const deltaY = event.clientY - this.drawerPointerStartY;
    if (this.drawerPointerAxis === 'pending' && Math.max(Math.abs(deltaX), Math.abs(deltaY)) >= 8) {
      this.drawerPointerAxis = Math.abs(deltaX) > Math.abs(deltaY) * 1.15 ? 'horizontal' : 'vertical';
      if (this.drawerPointerAxis === 'horizontal') this.accountDrawerDragging.set(true);
    }
    if (this.drawerPointerAxis !== 'horizontal') return;
    this.accountDrawerDragX.set(Math.max(0, deltaX));
    if (Math.abs(deltaX) >= 8) {
      event.preventDefault();
    }
  }

  onDrawerPointerUp(event: PointerEvent) {
    if (this.drawerPointerId !== event.pointerId) return;
    const deltaX = event.clientX - this.drawerPointerStartX;
    const elapsedMs = Math.max(1, event.timeStamp - this.drawerPointerStartTime);
    const width = document.getElementById('account-drawer')?.getBoundingClientRect().width || window.innerWidth;
    const quickSwipe = deltaX >= 40 && deltaX / elapsedMs >= 0.5;
    const longSwipe = deltaX >= width * 0.25;
    const wasHorizontalDrag = this.drawerPointerAxis === 'horizontal';
    this.drawerPointerId = null;
    this.drawerPointerAxis = null;

    if (wasHorizontalDrag && (quickSwipe || longSwipe)) {
      this.closeAccountDrawer();
      return;
    }
    if (wasHorizontalDrag) {
      this.accountDrawerDragging.set(false);
      this.accountDrawerSettling.set(true);
      this.accountDrawerDragX.set(0);
      if (this.drawerSettleTimer) clearTimeout(this.drawerSettleTimer);
      this.drawerSettleTimer = setTimeout(() => {
        this.drawerSettleTimer = null;
        this.accountDrawerSettling.set(false);
      }, 180);
    }
  }

  onDrawerPointerCancel(event: PointerEvent) {
    if (this.drawerPointerId !== event.pointerId) return;
    this.drawerPointerId = null;
    this.drawerPointerAxis = null;
    this.accountDrawerDragging.set(false);
    this.accountDrawerSettling.set(false);
    this.accountDrawerDragX.set(0);
  }

  drawerTransform(): string | null {
    return this.accountDrawerDragging() || this.accountDrawerSettling()
      ? `translateX(${this.accountDrawerDragX()}px)`
      : null;
  }

  private resetDrawerGesture() {
    this.drawerPointerId = null;
    this.drawerPointerAxis = null;
    this.accountDrawerDragX.set(0);
    this.accountDrawerDragging.set(false);
    this.accountDrawerSettling.set(false);
    if (this.drawerSettleTimer) clearTimeout(this.drawerSettleTimer);
    this.drawerSettleTimer = null;
  }

  openLogoutConfirm() {
    this.logoutConfirmOpen.set(true);
  }

  openShortcutsDialog() {
    this.shortcutsDialogOpen.set(true);
    setTimeout(() => this.shortcutsCloseButton?.nativeElement.focus());
  }

  closeShortcutsDialog() {
    this.shortcutsDialogOpen.set(false);
    setTimeout(() => this.shortcutsTrigger?.nativeElement.focus());
  }

  onShortcutsDialogKeydown(event: KeyboardEvent) {
    if (event.key !== 'Tab') return;
    const dialog = event.currentTarget as HTMLElement;
    const focusable = Array.from(dialog.querySelectorAll<HTMLElement>('button:not([disabled]), a[href], input:not([disabled]), [tabindex]:not([tabindex="-1"])'));
    if (!focusable.length) return;

    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  cancelLogout() {
    this.logoutConfirmOpen.set(false);
  }

  ngOnDestroy() {
    this.cancelDrawerClose();
    this.resetDrawerGesture();
    if (this.drawerEntranceTimer) clearTimeout(this.drawerEntranceTimer);
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
    if (this.shortcutsDialogOpen()) {
      this.closeShortcutsDialog();
      return;
    }
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

  private refreshMyChannel() {
    if (!this.auth.user()) return;
    this.channelService.getMyChannel().subscribe({
      next: channel => this.myChannel.set(channel),
      // Keep the last known channel visible when a transient refresh fails.
      error: () => undefined
    });
  }

  private readSocialLinks(settings: string | null | undefined, channelId?: string): Array<{ platform?: string; title: string; url: string }> {
    const normalize = (source: unknown): Array<{ platform?: string; title: string; url: string }> => {
      let parsed: unknown = source;
      if (typeof parsed === 'string') {
        try { parsed = JSON.parse(parsed); } catch { return []; }
      }

      const links = Array.isArray(parsed)
        ? parsed
        : parsed && typeof parsed === 'object' && Array.isArray((parsed as { links?: unknown }).links)
          ? (parsed as { links: unknown[] }).links
          : [];

      return links
        .filter((link): link is { platform?: unknown; title?: unknown; url?: unknown } => !!link && typeof link === 'object')
        .map(link => ({ platform: typeof link.platform === 'string' ? link.platform : undefined, title: typeof link.title === 'string' ? link.title : '', url: typeof link.url === 'string' ? link.url.trim() : '' }))
        .filter(link => /^https?:\/\//i.test(link.url));
    };

    let parsedSettings: unknown = settings;
    if (typeof parsedSettings === 'string') {
      try { parsedSettings = JSON.parse(parsedSettings); } catch { parsedSettings = null; }
    }
    const hasExplicitLinkList = !!parsedSettings
      && typeof parsedSettings === 'object'
      && !Array.isArray(parsedSettings)
      && Object.prototype.hasOwnProperty.call(parsedSettings, 'links')
      && Array.isArray((parsedSettings as { links?: unknown }).links);
    const serverLinks = normalize(settings);
    if (hasExplicitLinkList || serverLinks.length) return serverLinks.slice(0, 5);
    if (!channelId || typeof localStorage === 'undefined') return [];

    try {
      return normalize(localStorage.getItem(`hutube_channel_links_${channelId}`)).slice(0, 5);
    } catch {
      return [];
    }
  }
}
