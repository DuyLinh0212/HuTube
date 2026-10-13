import { Component, ElementRef, HostListener, Injector, ViewChild, afterNextRender, inject, signal } from '@angular/core';
import { NavigationEnd, Router, RouterOutlet } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { filter } from 'rxjs';
import { AdminSidebarComponent } from '../../shared/sidebar/admin-sidebar.component';
import { AdminTopbarComponent } from '../../shared/topbar/admin-topbar.component';

import { TranslatePipe } from '../../core/translate.pipe';

@Component({ selector: 'app-admin-shell-layout', imports: [RouterOutlet, AdminSidebarComponent, AdminTopbarComponent, TranslatePipe], templateUrl: './admin-shell-layout.component.html', styleUrl: './admin-shell-layout.component.scss' })
export class AdminShellLayoutComponent {
  private readonly injector = inject(Injector);
  @ViewChild('navigation', { read: ElementRef }) private navigation?: ElementRef<HTMLElement>;
  @ViewChild('stage') private stage?: ElementRef<HTMLElement>;
  readonly mobileNavigation = signal(window.innerWidth <= 1040);
  readonly navOpen = signal(false);
  readonly navCollapsed = signal(localStorage.getItem('hutube.admin.sidebar-collapsed') === 'true');
  constructor() {
    inject(Router).events.pipe(filter(event => event instanceof NavigationEnd), takeUntilDestroyed()).subscribe(() => {
      this.closeNavigation();
      this.stage?.nativeElement.scrollTo({ top: 0 });
    });
  }
  closeNavigation() {
    const wasOpen = this.navOpen();
    this.navOpen.set(false);
    if (wasOpen) afterNextRender(() => document.querySelector<HTMLButtonElement>('.menu-button')?.focus(), { injector: this.injector });
  }
  setCollapsed(value: boolean) { this.navCollapsed.set(value); localStorage.setItem('hutube.admin.sidebar-collapsed', String(value)); }
  toggleNavigation() {
    if (this.mobileNavigation()) {
      if (this.navOpen()) { this.closeNavigation(); return; }
      this.navOpen.set(true);
      afterNextRender(() => this.navigation?.nativeElement.querySelector<HTMLButtonElement>('.nav-close')?.focus(), { injector: this.injector });
      return;
    }
    this.setCollapsed(!this.navCollapsed());
  }
  @HostListener('window:resize') onResize() {
    const mobile = window.innerWidth <= 1040;
    if (mobile !== this.mobileNavigation()) this.closeNavigation();
    this.mobileNavigation.set(mobile);
  }
  @HostListener('document:keydown', ['$event']) onKeydown(event: KeyboardEvent) {
    if (!this.navOpen()) return;
    if (event.key === 'Escape') { event.preventDefault(); this.closeNavigation(); return; }
    if (event.key !== 'Tab') return;
    const controls = Array.from(this.navigation?.nativeElement.querySelectorAll<HTMLElement>('a[href], button:not([disabled])') ?? []);
    const first = controls[0], last = controls[controls.length - 1];
    if (!first || !last) return;
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  }
}
