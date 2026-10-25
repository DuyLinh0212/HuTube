import { FeedbackHostComponent } from '@dalitu/ui/feedback-host.component';
import { FeedbackService } from '@dalitu/ui/feedback.service';
import { Component, inject, signal } from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { filter } from 'rxjs';
import { AdminAuthLayoutComponent } from './layouts/auth-layout/admin-auth-layout.component';
import { AdminShellLayoutComponent } from './layouts/shell-layout/admin-shell-layout.component';
import { TranslatePipe } from './core/translate.pipe';

@Component({
  selector: 'app-root',
  imports: [FeedbackHostComponent, AdminAuthLayoutComponent, AdminShellLayoutComponent, TranslatePipe],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App {
  readonly feedback = inject(FeedbackService);
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
      ['/login', '/verify-email', '/forgot-password', '/reset-password', '/load-error'].some((route) =>
        url.startsWith(route),
      ),
    );
  }
}
