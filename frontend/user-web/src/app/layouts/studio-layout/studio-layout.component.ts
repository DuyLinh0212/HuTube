import { Component, inject, signal } from '@angular/core';
import { Router, RouterOutlet } from '@angular/router';
import { StudioSidebarComponent } from './studio-sidebar.component';
import { StudioTopbarComponent } from './studio-topbar.component';
import { StudioDataService } from '../../core/studio-data.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-studio-layout',
  imports: [RouterOutlet, StudioSidebarComponent, StudioTopbarComponent, TranslatePipe],
  templateUrl: './studio-layout.component.html',
  styleUrl: './studio-layout.component.scss'
})
export class StudioLayoutComponent {
  readonly data = inject(StudioDataService);
  readonly i18n = inject(I18nService);
  private readonly router = inject(Router);
  readonly navOpen = signal(false);
  readonly navCollapsed = signal(localStorage.getItem('hutube.studio.sidebar-collapsed') === 'true');

  constructor() { this.data.load(undefined, false); }

  selectChannel(channelId: string) {
    const route = this.router.url.split(/[?#]/, 1)[0];
    this.data.selectChannel(channelId, route !== '/studio/content');
  }

  chooseChannel(channelId: string, menu: HTMLDetailsElement) {
    this.selectChannel(channelId);
    menu.open = false;
  }

  closeChannelMenu(menu: HTMLDetailsElement) {
    menu.open = false;
  }

  roleLabel(role: string | null | undefined): string {
    const key = ({ owner: 'studio.roleOwner', manager: 'studio.roleManager', editor: 'studio.roleEditor', moderator: 'studio.roleModerator', viewer: 'studio.roleViewer' } as Record<string, string>)[role ?? ''] ?? 'studio.roleContributor';
    return this.i18n.t(key);
  }

  closeNavigation() {
    this.navOpen.set(false);
  }

  toggleNavigation() {
    if (window.innerWidth <= 960) {
      this.navOpen.set(true);
      return;
    }

    this.setCollapsed(!this.navCollapsed());
  }

  setCollapsed(value: boolean) {
    this.navCollapsed.set(value);
    localStorage.setItem('hutube.studio.sidebar-collapsed', String(value));
  }
}
