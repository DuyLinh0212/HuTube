import { Component, inject, signal } from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { filter } from 'rxjs';
import { AdminAuthLayoutComponent } from './layouts/auth-layout/admin-auth-layout.component';
import { AdminShellLayoutComponent } from './layouts/shell-layout/admin-shell-layout.component';

@Component({
  selector: 'app-root',
  imports: [AdminAuthLayoutComponent, AdminShellLayoutComponent],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App {
  readonly isAuthLayout = signal(true);
  private readonly router = inject(Router);

  constructor() {
    this.syncLayout(this.router.url);
    this.router.events
      .pipe(
        filter((event): event is NavigationEnd => event instanceof NavigationEnd),
        takeUntilDestroyed(),
      )
      .subscribe((event) => this.syncLayout(event.urlAfterRedirects));
  }

  private syncLayout(url: string) {
    this.isAuthLayout.set(
      ['/login', '/verify-email', '/forgot-password', '/reset-password'].some((route) =>
        url.startsWith(route),
      ),
    );
  }
}
