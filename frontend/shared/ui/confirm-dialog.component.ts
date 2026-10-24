import { DOCUMENT } from '@angular/common';
import { Component, DestroyRef, ElementRef, ViewChild, afterRenderEffect, computed, inject, input, output } from '@angular/core';
import { FEEDBACK_LANGUAGE, FEEDBACK_TEXT } from './feedback-language';

@Component({
  selector: 'app-confirm-dialog',
  template: `
    <dialog #dialog role="dialog" aria-modal="true" [class]="'dalitu-confirm-dialog ' + panelClass()" [class.is-danger]="tone() === 'danger'"
      [attr.aria-labelledby]="id + '-title'" [attr.aria-describedby]="description() ? id + '-description' : null"
      (cancel)="onCancel($event)" (click)="onBackdrop($event)" (keydown)="$event.stopPropagation()">
      <form class="confirm-form" novalidate (submit)="submit($event)">
        <header class="confirm-header">
          <span class="confirm-symbol" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v6M12 17h.01"/></svg></span>
          <h2 [id]="id + '-title'">{{ title() || text().confirmation }}</h2>
          <button class="confirm-close" type="button" [disabled]="busy()" (click)="cancelled.emit()" [attr.aria-label]="text().close">×</button>
        </header>
        <div class="confirm-content">
          @if (description()) { <p class="confirm-description" [id]="id + '-description'">{{ description() }}</p> }
          <ng-content />
        </div>
        <footer class="confirm-footer">
          <button #cancelButton type="button" class="confirm-cancel" [disabled]="busy()" (click)="cancelled.emit()">{{ cancelLabel() || text().cancel }}</button>
          <button type="submit" class="confirm-submit" [disabled]="busy() || confirmDisabled()">{{ busy() ? text().working : (confirmLabel() || text().confirm) }}</button>
        </footer>
      </form>
    </dialog>`,
  styleUrl: './confirm-dialog.component.scss',
})
export class ConfirmDialogComponent {
  private static nextId = 0;
  private static locks = 0;
  private static previousOverflow = '';
  readonly id = `dalitu-confirm-${++ConfirmDialogComponent.nextId}`;
  readonly open = input(true);
  readonly title = input<string | null | undefined>('');
  readonly description = input<string | null | undefined>('');
  readonly confirmLabel = input<string | null | undefined>('');
  readonly cancelLabel = input<string | null | undefined>('');
  readonly tone = input<'primary' | 'danger'>('primary');
  readonly busy = input(false);
  readonly confirmDisabled = input(false);
  readonly panelClass = input('');
  readonly initialFocus = input<'cancel' | 'field'>('cancel');
  readonly cancelled = output<void>();
  readonly confirmed = output<void>();
  @ViewChild('dialog', { static: true }) private dialog!: ElementRef<HTMLDialogElement>;
  @ViewChild('cancelButton', { static: true }) private cancelButton!: ElementRef<HTMLButtonElement>;
  private readonly document = inject(DOCUMENT);
  private readonly language = inject(FEEDBACK_LANGUAGE);
  readonly text = computed(() => FEEDBACK_TEXT[this.language()]);
  private locked = false;

  constructor() {
    afterRenderEffect(() => {
      const dialog = this.dialog.nativeElement;
      if (this.open() && !dialog.open) {
        this.lockScroll();
        dialog.showModal();
        const field = this.initialFocus() === 'field' ? dialog.querySelector<HTMLElement>('input:not([type=hidden]):not(:disabled), textarea:not(:disabled), select:not(:disabled)') : null;
        (field ?? this.cancelButton.nativeElement).focus({ preventScroll: true });
      } else if (!this.open() && dialog.open) { dialog.close(); this.unlockScroll(); }
    });
    inject(DestroyRef).onDestroy(() => {
      if (this.dialog.nativeElement.open) this.dialog.nativeElement.close();
      this.unlockScroll();
    });
  }

  submit(event: Event): void { event.preventDefault(); if (!this.busy() && !this.confirmDisabled()) this.confirmed.emit(); }
  onCancel(event: Event): void { event.preventDefault(); event.stopPropagation(); if (!this.busy()) this.cancelled.emit(); }
  onBackdrop(event: MouseEvent): void {
    event.stopPropagation();
    if (event.target !== this.dialog.nativeElement || this.busy()) return;
    const rect = this.dialog.nativeElement.getBoundingClientRect();
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) this.cancelled.emit();
  }
  private lockScroll(): void {
    if (this.locked) return;
    if (ConfirmDialogComponent.locks++ === 0) {
      ConfirmDialogComponent.previousOverflow = this.document.body.style.overflow;
      this.document.body.style.overflow = 'hidden';
    }
    this.locked = true;
  }
  private unlockScroll(): void {
    if (!this.locked) return;
    this.locked = false;
    if (--ConfirmDialogComponent.locks === 0) this.document.body.style.overflow = ConfirmDialogComponent.previousOverflow;
  }
}
