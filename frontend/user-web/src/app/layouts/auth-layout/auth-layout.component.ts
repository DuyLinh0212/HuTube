import { Component } from '@angular/core';
import { RouterLink, RouterOutlet } from '@angular/router';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-auth-layout',
  imports: [RouterLink, RouterOutlet, TranslatePipe],
  templateUrl: './auth-layout.component.html',
  styleUrl: './auth-layout.component.scss',
})
export class AuthLayoutComponent {}
