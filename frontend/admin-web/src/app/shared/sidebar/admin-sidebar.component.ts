import { Component, EventEmitter, Input, Output } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';

@Component({ selector: 'app-admin-sidebar', imports: [RouterLink, RouterLinkActive], templateUrl: './admin-sidebar.component.html', styleUrl: './admin-sidebar.component.scss' })
export class AdminSidebarComponent {
  @Input({ required: true }) collapsed = false;
  @Output() readonly collapsedChange = new EventEmitter<boolean>();
  @Output() readonly navigationClosed = new EventEmitter<void>();
  toggleCollapsed() { this.collapsedChange.emit(!this.collapsed); }
  closeNavigation() { this.navigationClosed.emit(); }
}
