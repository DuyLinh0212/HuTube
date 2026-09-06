import { Component, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { AdminSidebarComponent } from '../../shared/sidebar/admin-sidebar.component';
import { AdminTopbarComponent } from '../../shared/topbar/admin-topbar.component';

@Component({ selector: 'app-admin-shell-layout', imports: [RouterOutlet, AdminSidebarComponent, AdminTopbarComponent], templateUrl: './admin-shell-layout.component.html', styleUrl: './admin-shell-layout.component.scss' })
export class AdminShellLayoutComponent {
  readonly navOpen = signal(false);
  readonly navCollapsed = signal(localStorage.getItem('hutube.admin.sidebar-collapsed') === 'true');
  closeNavigation() { this.navOpen.set(false); }
  setCollapsed(value: boolean) { this.navCollapsed.set(value); localStorage.setItem('hutube.admin.sidebar-collapsed', String(value)); }
}
