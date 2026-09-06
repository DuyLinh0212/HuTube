import { Component, EventEmitter, Input, Output, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../core/auth.service';

@Component({ selector: 'app-admin-sidebar', imports: [RouterLink], templateUrl: './admin-sidebar.component.html', styleUrl: './admin-sidebar.component.scss' })
export class AdminSidebarComponent {
  @Input({ required: true }) collapsed = false;
  @Output() readonly collapsedChange = new EventEmitter<boolean>();
  @Output() readonly navigationClosed = new EventEmitter<void>();
  readonly auth = inject(AuthService);
  toggleCollapsed() { this.collapsedChange.emit(!this.collapsed); }
  closeNavigation() { this.navigationClosed.emit(); }
}
