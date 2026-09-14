import { Component, inject, signal } from '@angular/core';
import { NavigationEnd, Router, RouterOutlet } from '@angular/router';
import { filter } from 'rxjs';
import { UserSidebarComponent } from '../../shared/sidebar/user-sidebar.component';
import { UserTopbarComponent } from '../../shared/topbar/user-topbar.component';

@Component({
  selector: 'app-shell-layout',
  imports: [RouterOutlet, UserSidebarComponent, UserTopbarComponent],
  templateUrl: './shell-layout.component.html',
  styleUrl: './shell-layout.component.scss'
})
export class ShellLayoutComponent {
  private readonly router = inject(Router);

  readonly navOpen = signal(false);
  readonly navCollapsed = signal(localStorage.getItem('hutube.user.sidebar-collapsed') === 'true');

  constructor() {
    this.router.events.pipe(filter(e => e instanceof NavigationEnd)).subscribe(() => this.closeNavigation());
  }

  closeNavigation() { this.navOpen.set(false); }
  setCollapsed(value: boolean) { this.navCollapsed.set(value); localStorage.setItem('hutube.user.sidebar-collapsed', String(value)); }
  toggleNavigation() {
    if (typeof window !== 'undefined' && window.innerWidth <= 960) {
      this.navOpen.set(true);
      return;
    }
    this.setCollapsed(!this.navCollapsed());
  }
}
