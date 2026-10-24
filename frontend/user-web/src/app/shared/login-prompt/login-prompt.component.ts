import { DOCUMENT } from '@angular/common';
import { Component, DestroyRef, ElementRef, HostListener, ViewChild, afterRenderEffect, inject, signal } from '@angular/core';
import { LoginPromptService } from '../../core/login-prompt.service';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-login-prompt',
  imports: [TranslatePipe],
  template: `
    <section #panel class="login-prompt" popover="auto" role="dialog" aria-labelledby="login-prompt-title" aria-describedby="login-prompt-description"
      [style.left.px]="left()" [style.top.px]="top()" (toggle)="onToggle($event)" (keydown)="onKeydown($event)">
      <div class="prompt-heading">
        <strong id="login-prompt-title">{{ 'guest.signInTitle' | translate }}</strong>
        <button class="prompt-close" type="button" (click)="close(true)" [attr.aria-label]="'common.close' | translate">×</button>
      </div>
      <p id="login-prompt-description">{{ login.prompt()?.message || ('guest.signInDescription' | translate) }}</p>
      <button #signIn type="button" class="prompt-sign-in" (click)="login.signIn()">{{ 'ui.signIn' | translate }} <span aria-hidden="true">→</span></button>
    </section>
  `,
  styleUrl: './login-prompt.component.scss',
})
export class LoginPromptComponent {
  readonly login = inject(LoginPromptService);
  private readonly document = inject(DOCUMENT);
  @ViewChild('panel', { static: true }) private panel!: ElementRef<HTMLElement>;
  @ViewChild('signIn', { static: true }) private signIn!: ElementRef<HTMLButtonElement>;
  readonly left = signal(12);
  readonly top = signal(12);
  private anchor: HTMLElement | null = null;

  constructor() {
    afterRenderEffect(() => {
      const prompt = this.login.prompt();
      const panel = this.panel.nativeElement;
      if (!prompt) {
        if (panel.matches(':popover-open')) panel.hidePopover();
        return;
      }
      this.anchor = prompt.anchor;
      if (!panel.matches(':popover-open')) panel.showPopover();
      this.position();
      this.signIn.nativeElement.focus({ preventScroll: true });
    });
    const onScroll = () => { if (this.login.prompt()) this.position(); };
    this.document.addEventListener('scroll', onScroll, true);
    inject(DestroyRef).onDestroy(() => this.document.removeEventListener('scroll', onScroll, true));
  }

  @HostListener('window:resize')
  position(): void {
    const panel = this.panel.nativeElement;
    const anchor = this.anchor;
    if (!anchor?.isConnected) { this.close(); return; }
    const rect = anchor.getBoundingClientRect();
    const width = this.document.documentElement.clientWidth;
    const height = window.innerHeight;
    const gap = 8;
    const margin = 12;
    this.left.set(Math.max(margin, Math.min(rect.left, width - panel.offsetWidth - margin)));
    const below = rect.bottom + gap;
    this.top.set(Math.max(margin, Math.min(below + panel.offsetHeight <= height - margin
      ? below : rect.top - panel.offsetHeight - gap, height - panel.offsetHeight - margin)));
  }

  onToggle(event: Event): void {
    if ((event as ToggleEvent).newState === 'closed' && !this.panel.nativeElement.matches(':popover-open')) this.login.dismiss();
  }

  onKeydown(event: KeyboardEvent): void {
    event.stopPropagation();
    if (event.key === 'Escape') { event.preventDefault(); this.close(true); }
  }

  close(restoreFocus = false): void {
    this.login.dismiss();
    if (restoreFocus) this.anchor?.focus({ preventScroll: true });
  }
}
