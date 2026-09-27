import { Component } from '@angular/core';
import { RouterLink, RouterOutlet } from '@angular/router';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({ selector: 'app-admin-auth-layout', imports: [RouterLink, RouterOutlet, TranslatePipe], templateUrl: './admin-auth-layout.component.html', styleUrl: './admin-auth-layout.component.scss' })
export class AdminAuthLayoutComponent {}
