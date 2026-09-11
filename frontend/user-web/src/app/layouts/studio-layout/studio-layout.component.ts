import { Component, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { StudioSidebarComponent } from './studio-sidebar.component';
import { StudioTopbarComponent } from './studio-topbar.component';

@Component({
  selector: 'app-studio-layout',
  imports: [RouterOutlet, StudioSidebarComponent, StudioTopbarComponent],
  templateUrl: './studio-layout.component.html',
  styleUrl: './studio-layout.component.scss'
})
export class StudioLayoutComponent {
  readonly navOpen = signal(false);
  readonly navCollapsed = signal(localStorage.getItem('hutube.studio.sidebar-collapsed') === 'true');

  closeNavigation() {
    this.navOpen.set(false);
  }

  setCollapsed(value: boolean) {
    this.navCollapsed.set(value);
    localStorage.setItem('hutube.studio.sidebar-collapsed', String(value));
  }
}
