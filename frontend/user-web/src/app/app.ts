import { Component, DestroyRef, HostListener, effect, inject, signal } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { NavigationEnd, Router, Scroll } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { filter } from 'rxjs';
import { AuthLayoutComponent } from './layouts/auth-layout/auth-layout.component';
import { ShellLayoutComponent } from './layouts/shell-layout/shell-layout.component';
import { StudioLayoutComponent } from './layouts/studio-layout/studio-layout.component';
import { UploadProgressTrayComponent } from './shared/upload-progress/upload-progress-tray.component';
import { TranslatePipe } from './core/translate.pipe';
import { I18nService } from './core/i18n.service';
import { NetworkFallbackComponent } from './core/network/network-fallback.component';

@Component({
  selector: 'app-root',
  imports: [
    AuthLayoutComponent,
    ShellLayoutComponent,
    StudioLayoutComponent,
    UploadProgressTrayComponent,
    NetworkFallbackComponent,
    TranslatePipe,
  ],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App {
  readonly skipHref = signal("#main-content");
  skipToContent(event: Event) {
    event.preventDefault();
    const main = document.getElementById("main-content");
    if (!main) return;
    main.setAttribute("tabindex", "-1");
    main.focus();
    main.scrollIntoView({ block: "start" });
    window.history.replaceState(window.history.state, "", this.skipHref());
  }

  readonly isAuthLayout = signal(true);
  readonly isStudioLayout = signal(false);
  private readonly router = inject(Router);
  private readonly title = inject(Title);
  private readonly i18n = inject(I18nService);
  private scrollRestoreFrame: number | null = null;

  @HostListener('window:wheel')
  @HostListener('window:pointerdown')
  cancelScrollRestore() {
    if (this.scrollRestoreFrame !== null) cancelAnimationFrame(this.scrollRestoreFrame);
    this.scrollRestoreFrame = null;
  }

  private restoreLoadedScroll(position: [number, number]) {
    this.cancelScrollRestore();
    let frames = 0;
    let stable = 0;
    const restore = () => {
      window.scrollTo({ left: position[0], top: position[1], behavior: 'auto' });
      stable = Math.abs(window.scrollY - position[1]) < 2 ? stable + 1 : 0;
      // Router restoration can run while an asynchronous page is still too
      // short to reach its saved position. Retry briefly as real content loads.
      if (++frames < 120 && stable < 3) this.scrollRestoreFrame = requestAnimationFrame(restore);
      else this.scrollRestoreFrame = null;
    };
    this.scrollRestoreFrame = requestAnimationFrame(restore);
  }

  constructor() {
    inject(DestroyRef).onDestroy(() => this.cancelScrollRestore());
    this.syncLayout(this.router.url);
    effect(() => {
      this.i18n.currentLang();
      this.updateTitle(this.router.url);
    });
    this.router.events
      .pipe(
        filter((event): event is NavigationEnd => event instanceof NavigationEnd),
        takeUntilDestroyed(),
      )
      .subscribe((event) => {
        this.cancelScrollRestore();
        this.syncLayout(event.urlAfterRedirects);
        this.updateTitle(event.urlAfterRedirects);
      });
    this.router.events.pipe(
      filter((event): event is Scroll => event instanceof Scroll),
      takeUntilDestroyed(),
    ).subscribe(event => {
      if (event.position) this.restoreLoadedScroll(event.position);
    });
  }

  private updateTitle(url: string) {
    const path = url.split(/[?#]/, 1)[0];
    const key = path === '/login' ? 'title.login'
      : path === '/register' ? 'title.register'
      : path === '/verify-email' ? 'title.verifyEmail'
      : path === '/forgot-password' ? 'title.forgotPassword'
      : path === '/reset-password' ? 'title.resetPassword'
      : path === '/home' || path === '' ? 'title.home'
      : path === '/explore' ? 'title.explore'
      : path.startsWith('/watch/') ? 'title.watch'
      : path === '/terms' ? 'title.terms'
      : path === '/privacy' ? 'title.privacy'
      : path === '/guidelines' ? 'title.guidelines'
      : path === '/policies' ? 'title.policies'
      : path === '/plans' ? 'title.plans'
      : path === '/plans/accept-invite' ? 'title.planInvite'
      : path.startsWith('/plans/') ? 'title.planDetail'
      : path === '/account' ? 'title.account'
      : path === '/history' ? 'title.history'
      : path === '/liked' ? 'title.liked'
      : path === '/channel/create' ? 'title.channelCreate'
      : path.includes('/customize') ? 'title.channelCustomize'
      : path.startsWith('/channel/') ? 'title.channel'
      : path === '/studio/setup' ? 'title.studioSetup'
      : path === '/studio/overview' ? 'title.studioOverview'
      : path === '/studio/content' ? 'title.studioContent'
      : path === '/studio/upload' ? 'title.studioUpload'
      : path === '/studio/analytics' ? 'title.studioAnalytics'
      : path === '/studio/comments' ? 'title.studioComments'
      : path === '/studio/subtitles' ? 'title.studioSubtitles'
      : path === '/studio/settings' ? 'title.studioSettings'
      : path === '/studio/invitations' ? 'title.studioInvitations'
      : undefined;
    if (key) this.title.setTitle(this.i18n.t(key));
  }

  private syncLayout(url: string) {
    this.skipHref.set(url.split("#")[0] + "#main-content");
    this.isAuthLayout.set(
      ['/login', '/register', '/verify-email', '/forgot-password', '/reset-password'].some(
        (route) => url.startsWith(route),
      ),
    );
    this.isStudioLayout.set(url.startsWith('/studio'));
  }
}
