import { Component, inject } from '@angular/core';
import { FeedbackService } from './feedback.service';
import { ConfirmDialogComponent } from './confirm-dialog.component';
import { ResultNoticeComponent } from './result-notice.component';

@Component({
  selector: 'app-feedback-host',
  imports: [ConfirmDialogComponent, ResultNoticeComponent],
  template: `
    @if (feedback.confirmation(); as request) {
      <app-confirm-dialog [title]="request.title" [description]="request.message" [confirmLabel]="request.confirmLabel" [cancelLabel]="request.cancelLabel"
        [tone]="request.tone || 'primary'" (confirmed)="feedback.resolve(true)" (cancelled)="feedback.resolve(false)" />
    }
    <div class="feedback-stack">
      @for (notice of feedback.notices(); track notice.id) {
        <app-result-notice [tone]="notice.tone" [message]="notice.message" [title]="notice.title" [details]="notice.details || []"
          [dismissible]="true" (dismissed)="feedback.dismiss(notice.id)" />
      }
    </div>`,
  styles: `.feedback-stack { position: fixed; top: calc(84px + env(safe-area-inset-top)); right: 20px; z-index: var(--z-feedback, 240); width: min(400px, calc(100vw - 32px)); max-height: calc(100dvh - 108px); overflow-y: auto; pointer-events: none; }
    app-result-notice { pointer-events: auto; }
    @media (max-width: 640px) { .feedback-stack { right: 12px; width: calc(100vw - 24px); } }`,
})
export class FeedbackHostComponent { readonly feedback = inject(FeedbackService); }
