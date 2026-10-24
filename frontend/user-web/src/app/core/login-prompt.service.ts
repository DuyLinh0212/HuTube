import { DOCUMENT } from '@angular/common';
import { Injectable, effect, inject, signal } from '@angular/core';
import { NavigationStart, Router } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { AuthService, safeReturnUrl } from './auth.service';

export interface LoginPrompt {
  anchor: HTMLElement | null;
  returnUrl: string;
  message: string;
}

@Injectable({ providedIn: 'root' })
export class LoginPromptService {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly document = inject(DOCUMENT);
  readonly prompt = signal<LoginPrompt | null>(null);

  constructor() {
    this.router.events.pipe(takeUntilDestroyed()).subscribe(event => {
      if (event instanceof NavigationStart) this.dismiss();
    });
    effect(() => { if (this.auth.user()) this.dismiss(); });
  }

  require(anchor?: HTMLElement | null, returnUrl?: string, message = ''): boolean {
    if (this.auth.user()) return true;
    this.prompt.set({
      anchor: anchor ?? (this.document.activeElement as HTMLElement | null),
      returnUrl: safeReturnUrl(returnUrl || this.router.url),
      message,
    });
    return false;
  }

  dismiss(): void { this.prompt.set(null); }

  signIn(): void {
    const prompt = this.prompt();
    if (!prompt) return;
    this.dismiss();
    void this.router.navigate(['/login'], { queryParams: { returnUrl: prompt.returnUrl } });
  }
}
