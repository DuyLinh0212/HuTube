import { DOCUMENT } from '@angular/common';
import { Component, DestroyRef, ElementRef, HostListener, Injector, Input, ViewChild, afterNextRender, afterRenderEffect, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { PlaylistService, PlaylistSummary } from '../../core/playlist.service';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-video-playlist-menu',
  imports: [TranslatePipe],
  templateUrl: './video-playlist-menu.component.html',
  styleUrl: './video-playlist-menu.component.scss',
})
export class VideoPlaylistMenuComponent {
  private static nextId = 0;
  @Input({ required: true }) videoId = '';
  @ViewChild('trigger', { static: true }) private trigger!: ElementRef<HTMLButtonElement>;
  @ViewChild('panel', { static: true }) private panel!: ElementRef<HTMLDivElement>;
  readonly menuId = `video-playlist-menu-${VideoPlaylistMenuComponent.nextId++}`;
  readonly panelLeft = signal(12);
  readonly panelTop = signal(12);

  readonly open = signal(false);
  readonly loading = signal(false);
  readonly addingId = signal<string | null>(null);
  readonly playlists = signal<PlaylistSummary[]>([]);
  readonly message = signal('');

  private readonly auth = inject(AuthService);
  private readonly playlistService = inject(PlaylistService);
  private readonly router = inject(Router);
  private readonly i18n = inject(I18nService);
  private readonly document = inject(DOCUMENT);
  private readonly injector = inject(Injector);
  private focusFirstItem = false;
  private anchorPosition?: { left: number; top: number };

  constructor() {
    afterRenderEffect(() => {
      if (!this.open()) return;
      this.loading(); this.playlists(); this.message(); this.addingId();
      this.positionPanel();
    });
    const onScroll = (event: Event) => {
      if (!this.open() || this.panel.nativeElement.contains(event.target as Node)) return;
      const button = this.trigger.nativeElement.getBoundingClientRect();
      // A scroll queued before opening may arrive after the click on a small screen.
      if (this.anchorPosition && (Math.abs(button.left - this.anchorPosition.left) > .5
        || Math.abs(button.top - this.anchorPosition.top) > .5)) this.close();
    };
    this.document.addEventListener('scroll', onScroll, true);
    inject(DestroyRef).onDestroy(() => this.document.removeEventListener('scroll', onScroll, true));
  }

  @HostListener('window:resize')
  close(): void {
    if (this.panel?.nativeElement.matches(':popover-open')) this.panel.nativeElement.hidePopover();
    this.open.set(false);
  }

  syncOpen(event: Event): void {
    this.open.set((event as ToggleEvent).newState === 'open');
  }

  toggle(event: Event): void {
    event.preventDefault();
    event.stopPropagation();
    this.message.set('');
    if (!this.auth.user()) {
      void this.router.navigate(['/login'], {
        queryParams: { returnUrl: typeof location === 'undefined' ? '/home' : location.pathname + location.search },
      });
      return;
    }
    if (this.panel.nativeElement.matches(':popover-open')) {
      if (event instanceof KeyboardEvent) {
        const first = this.panel.nativeElement.querySelector<HTMLButtonElement>('[role="menuitem"]:not(:disabled)');
        (first ?? this.panel.nativeElement).focus();
      } else this.close();
      return;
    }
    this.focusFirstItem = event instanceof KeyboardEvent;
    // Auto popovers dismiss the previous menu even when the click is stopped by a video card.
    this.panel.nativeElement.showPopover();
    this.open.set(true);
    this.positionPanel();
    if (this.focusFirstItem) this.panel.nativeElement.focus();
    this.focusMenuAfterRender();
    if (this.playlists().length === 0) void this.loadPlaylists();
  }

  private focusMenuAfterRender(): void {
    if (!this.focusFirstItem) return;
    afterNextRender(() => {
      if (!this.panel.nativeElement.matches(':popover-open')) return;
      const first = this.panel.nativeElement.querySelector<HTMLButtonElement>('[role="menuitem"]:not(:disabled)');
      if (first) { first.focus(); this.focusFirstItem = false; }
    }, { injector: this.injector });
  }

  onMenuKeydown(event: KeyboardEvent): void {
    if (event.key === 'Escape') {
      event.preventDefault(); event.stopPropagation();
      this.close(); this.trigger.nativeElement.focus();
      return;
    }
    if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault(); event.stopPropagation();
    const items = Array.from(this.panel.nativeElement.querySelectorAll<HTMLButtonElement>('[role="menuitem"]:not(:disabled)'));
    if (!items.length) return;
    const current = items.indexOf(this.document.activeElement as HTMLButtonElement);
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? items.length - 1
      : (current + (event.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length;
    items[next].focus();
  }

  private positionPanel(): void {
    const button = this.trigger.nativeElement.getBoundingClientRect();
    this.anchorPosition = { left: button.left, top: button.top };
    const panel = this.panel.nativeElement;
    const viewport = this.document.documentElement;
    const left = Math.max(12, Math.min(button.right - panel.offsetWidth, viewport.clientWidth - panel.offsetWidth - 12));
    const below = button.bottom + 6;
    const top = below + panel.offsetHeight <= viewport.clientHeight - 12
      ? below : Math.max(12, button.top - panel.offsetHeight - 6);
    this.panelLeft.set(left);
    this.panelTop.set(top);
  }

  async loadPlaylists(): Promise<void> {
    if (this.loading()) return;
    this.loading.set(true);
    try {
      this.playlists.set(await firstValueFrom(this.playlistService.mine()));
    } catch {
      this.message.set(this.i18n.t('watchPlaylist.loadError'));
    } finally {
      this.loading.set(false);
      this.focusMenuAfterRender();
    }
  }

  async addToPlaylist(event: MouseEvent, playlist: PlaylistSummary): Promise<void> {
    event.preventDefault();
    event.stopPropagation();
    if (this.addingId()) return;
    this.addingId.set(playlist.playlistId);
    this.message.set('');
    try {
      await firstValueFrom(this.playlistService.addVideo(playlist.playlistId, this.videoId));
      this.message.set(this.i18n.t('watchPlaylist.added').replace('{name}', playlist.name));
    } catch {
      this.message.set(this.i18n.t('watchPlaylist.addError').replace('{name}', playlist.name));
    } finally {
      this.addingId.set(null);
    }
  }

  stop(event: MouseEvent): void {
    event.preventDefault();
    event.stopPropagation();
  }
}
