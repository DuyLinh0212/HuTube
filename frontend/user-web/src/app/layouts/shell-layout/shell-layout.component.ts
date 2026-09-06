import { Component, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { UserSidebarComponent } from '../../shared/sidebar/user-sidebar.component';
import { UserTopbarComponent } from '../../shared/topbar/user-topbar.component';

@Component({ selector: 'app-shell-layout', imports: [RouterOutlet, UserSidebarComponent, UserTopbarComponent], templateUrl: './shell-layout.component.html', styleUrl: './shell-layout.component.scss' })
export class ShellLayoutComponent {
  readonly navOpen = signal(false);
  readonly navCollapsed = signal(localStorage.getItem('hutube.user.sidebar-collapsed') === 'true');
  closeNavigation() { this.navOpen.set(false); }
  setCollapsed(value: boolean) { this.navCollapsed.set(value); localStorage.setItem('hutube.user.sidebar-collapsed', String(value)); }
}
