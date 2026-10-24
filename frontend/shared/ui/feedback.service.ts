import { Injectable, OnDestroy, computed, inject, signal } from '@angular/core';
import { NavigationStart, Router } from '@angular/router';
import { FeedbackDetail, FeedbackTone } from './feedback-language';

export interface ConfirmOptions {
  title?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  tone?: 'primary' | 'danger';
}
export interface ConfirmRequest extends ConfirmOptions { message: string; }
export interface FeedbackNotice {
  id: number; tone: FeedbackTone; message: string; title?: string; details?: readonly FeedbackDetail[];
}

@Injectable({ providedIn: 'root' })
export class FeedbackService implements OnDestroy {
  readonly confirmation = signal<ConfirmRequest | null>(null);
  readonly notices = signal<FeedbackNotice[]>([]);
  readonly visible = computed(() => !!this.confirmation() || this.notices().length > 0);
  private resolvePending?: (confirmed: boolean) => void;
  private nextId = 0;
  private readonly navigation = inject(Router).events.subscribe(event => {
    // A confirmation must never execute its original action after leaving the page.
    if (event instanceof NavigationStart) this.resolve(false);
  });

  confirm(message: string, options: ConfirmOptions = {}): Promise<boolean> {
    // Ignore repeated invocations until the current confirmation is answered.
    if (this.confirmation()) return Promise.resolve(false);
    this.confirmation.set({ ...options, message });
    return new Promise(resolve => { this.resolvePending = resolve; });
  }

  resolve(confirmed: boolean): void {
    const resolve = this.resolvePending;
    this.resolvePending = undefined;
    this.confirmation.set(null);
    resolve?.(confirmed);
  }

  show(tone: FeedbackTone, message: string, title?: string): void {
    if (!message) return;
    this.notices.update(items => [...items.filter(item => item.message !== message), { id: ++this.nextId, tone, message, title }].slice(-3));
  }
  success(message: string): void { this.show('success', message); }
  error(message: string): void { this.show('error', message); }
  warning(message: string): void { this.show('warning', message); }
  info(message: string): void { this.show('info', message); }
  dismiss(id: number): void { this.notices.update(items => items.filter(item => item.id !== id)); }
  ngOnDestroy(): void { this.resolve(false); this.navigation.unsubscribe(); }
}
