import { Component, inject, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
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
  readonly navOpen = signal(false);
  readonly navCollapsed = signal(localStorage.getItem('hutube.studio.sidebar-collapsed') === 'true');

  constructor() { this.data.load(); }

  roleLabel(role: string | null | undefined): string {
    const key = ({ owner: 'studio.roleOwner', manager: 'studio.roleManager', editor: 'studio.roleEditor', moderator: 'studio.roleModerator', viewer: 'studio.roleViewer' } as Record<string, string>)[role ?? ''] ?? 'studio.roleContributor';
    return this.i18n.t(key);
  }

  closeNavigation() {
    this.navOpen.set(false);
  }

  setCollapsed(value: boolean) {
    this.navCollapsed.set(value);
    localStorage.setItem('hutube.studio.sidebar-collapsed', String(value));
  }
}
