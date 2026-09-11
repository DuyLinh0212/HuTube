import { Component, EventEmitter, Input, Output, inject } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-admin-sidebar',
  imports: [RouterLink, RouterLinkActive, TranslatePipe],
  templateUrl: './admin-sidebar.component.html',
  styleUrl: './admin-sidebar.component.scss'
})
export class AdminSidebarComponent {
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);

  @Input() open = false;
  @Input({ required: true }) collapsed = false;
  @Output() readonly collapsedChange = new EventEmitter<boolean>();
  @Output() readonly navigationClosed = new EventEmitter<void>();

  toggleCollapsed() { this.collapsedChange.emit(!this.collapsed); }
  closeNavigation() { this.navigationClosed.emit(); }
  can(permission: string): boolean { return this.auth.hasPermission(permission); }
}
