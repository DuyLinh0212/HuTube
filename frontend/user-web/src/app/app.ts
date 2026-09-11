import { Component, inject, signal } from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { filter } from 'rxjs';
import { AuthLayoutComponent } from './layouts/auth-layout/auth-layout.component';
import { ShellLayoutComponent } from './layouts/shell-layout/shell-layout.component';
import { StudioLayoutComponent } from './layouts/studio-layout/studio-layout.component';
import { UploadProgressTrayComponent } from './shared/upload-progress/upload-progress-tray.component';

@Component({
  selector: 'app-root',
  imports: [AuthLayoutComponent, ShellLayoutComponent, StudioLayoutComponent, UploadProgressTrayComponent],
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App {
  readonly isAuthLayout = signal(true);
  readonly isStudioLayout = signal(false);
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
      ['/login', '/register', '/verify-email', '/forgot-password', '/reset-password'].some(
        (route) => url.startsWith(route),
      ),
    );
    this.isStudioLayout.set(url.startsWith('/studio'));
  }
}
