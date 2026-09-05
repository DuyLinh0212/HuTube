import { Component, inject, signal } from '@angular/core';
import { NavigationEnd, Router, RouterLink, RouterOutlet } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { filter } from 'rxjs';
import { AuthService } from './core/auth.service';

@Component({
  selector: 'app-root',
  imports: [RouterLink, RouterOutlet],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App {
  readonly auth = inject(AuthService);
  readonly isAuthLayout = signal(true);
  readonly navOpen = signal(false);
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

  closeNavigation() { this.navOpen.set(false); }

  private syncLayout(url: string) {
    this.isAuthLayout.set(
      ['/login', '/verify-email', '/forgot-password', '/reset-password'].some((route) =>
        url.startsWith(route),
      ),
    );
    this.closeNavigation();
  }
}
