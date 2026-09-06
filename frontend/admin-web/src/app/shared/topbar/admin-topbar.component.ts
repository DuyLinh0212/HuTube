import { Component, EventEmitter, Output, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../core/auth.service';

@Component({ selector: 'app-admin-topbar', imports: [RouterLink], templateUrl: './admin-topbar.component.html', styleUrl: './admin-topbar.component.scss' })
export class AdminTopbarComponent {
  @Output() readonly menuOpened = new EventEmitter<void>();
  readonly auth = inject(AuthService);
}
