import { Component, EventEmitter, Output, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../core/auth.service';

@Component({ selector: 'app-user-topbar', imports: [RouterLink], templateUrl: './user-topbar.component.html', styleUrl: './user-topbar.component.scss' })
export class UserTopbarComponent {
  @Output() readonly menuOpened = new EventEmitter<void>();
  readonly auth = inject(AuthService);
}
