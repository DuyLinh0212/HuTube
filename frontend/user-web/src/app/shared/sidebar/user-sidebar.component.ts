import { Component, EventEmitter, Input, Output } from '@angular/core';
import { RouterLink } from '@angular/router';

@Component({ selector: 'app-user-sidebar', imports: [RouterLink], templateUrl: './user-sidebar.component.html', styleUrl: './user-sidebar.component.scss' })
export class UserSidebarComponent {
  @Input({ required: true }) collapsed = false;
  @Output() readonly collapsedChange = new EventEmitter<boolean>();
  @Output() readonly navigationClosed = new EventEmitter<void>();
  toggleCollapsed() { this.collapsedChange.emit(!this.collapsed); }
  closeNavigation() { this.navigationClosed.emit(); }
}
