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
  readonly isAccountRoute = signal(false);

  constructor() {
    this.updateRoute(this.router.url);
    this.router.events.pipe(filter(e => e instanceof NavigationEnd)).subscribe(e => {
      this.updateRoute((e as NavigationEnd).urlAfterRedirects || (e as NavigationEnd).url);
    });
  }

  private updateRoute(url: string) {
    const isAccount = url.startsWith('/account');
    this.isAccountRoute.set(isAccount);
    if (isAccount) {
      this.navOpen.set(false);
    }
  }

  closeNavigation() { this.navOpen.set(false); }
  setCollapsed(value: boolean) { this.navCollapsed.set(value); localStorage.setItem('hutube.user.sidebar-collapsed', String(value)); }
}
