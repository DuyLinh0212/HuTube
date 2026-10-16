import { DOCUMENT } from '@angular/common';
import {
  Component, DestroyRef, ElementRef, ViewChild, afterRenderEffect,
  computed, effect, inject, input, signal,
} from '@angular/core';
import { EMPTY, Subscription, catchError, exhaustMap, filter, retry, take, timeout, timer } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { FeedbackSurveyService, FeedbackSurveyStatus } from '../../core/feedback-survey.service';
import { TranslatePipe } from '../../core/translate.pipe';

type SurveyPhase = 'closed' | 'invitation' | 'plea' | 'waiting' | 'thanks';
export const SURVEY_DELAY_MS = 120_000;

@Component({
  selector: 'app-feedback-survey',
  imports: [TranslatePipe],
  templateUrl: './feedback-survey.component.html',
  styleUrl: './feedback-survey.component.scss',
})
export class FeedbackSurveyComponent {
  readonly enabled = input(true);
  readonly phase = signal<SurveyPhase>('closed');
  readonly formUrl = signal<string | null>(null);
  readonly gifUnavailable = signal(false);
  @ViewChild('dialog', { static: true }) private dialog!: ElementRef<HTMLDialogElement>;

  private readonly auth = inject(AuthService);
  private readonly surveys = inject(FeedbackSurveyService);
  private readonly document = inject(DOCUMENT);
  private readonly userId = computed(() => this.auth.user()?.userId ?? null);
  private visit = new Subscription();
  private polling?: Subscription;
  private openedForm = false;
  private completed = false;
  private savedOverflow: string | null = null;

  constructor() {
    effect((onCleanup) => {
      const userId = this.userId();
      const enabled = this.enabled();
      this.visit = new Subscription();
      this.polling = undefined;
      this.openedForm = false;
      this.completed = false;
      this.phase.set('closed');
      this.formUrl.set(null);
      this.gifUnavailable.set(false);
      if (userId && enabled) {
        // Root component survives route changes; refresh/re-entry starts a new visit.
        this.visit.add(timer(SURVEY_DELAY_MS).subscribe(() => this.refreshStatus(true)));
        const onReturn = () => {
          if (this.openedForm && !this.completed && this.document.visibilityState === 'visible') this.refreshStatus();
        };
        this.document.addEventListener('visibilitychange', onReturn);
        this.document.defaultView?.addEventListener('focus', onReturn);
        this.visit.add(() => {
          this.document.removeEventListener('visibilitychange', onReturn);
          this.document.defaultView?.removeEventListener('focus', onReturn);
        });
      }
      onCleanup(() => this.visit.unsubscribe());
    });

    afterRenderEffect(() => {
      const phase = this.phase();
      const dialog = this.dialog.nativeElement;
      if (phase === 'closed') {
        dialog.close();
        this.restoreScroll();
      } else {
        // Wait until a background tab is visible before taking focus.
        if (!dialog.open) {
          this.savedOverflow = this.document.body.style.overflow;
          this.document.body.style.overflow = 'hidden';
          dialog.showModal();
        }
        dialog.querySelector<HTMLElement>('[data-primary-action]')?.focus({ preventScroll: true });
      }
    });

    inject(DestroyRef).onDestroy(() => {
      this.visit.unsubscribe();
      this.dialog.nativeElement.close();
      this.restoreScroll();
    });
  }

  requestClose(event?: Event): void {
    event?.preventDefault();
    this.phase.update(phase => phase === 'invitation' || phase === 'waiting' ? 'plea' : 'closed');
    if (this.phase() === 'closed') this.polling?.unsubscribe();
  }

  onBackdrop(event: MouseEvent): void {
    if (event.target === this.dialog.nativeElement) this.requestClose();
  }

  formOpened(): void {
    this.openedForm = true;
    this.phase.set('waiting');
    if (this.polling && !this.polling.closed) return;
    this.polling = timer(10_000, 10_000).pipe(
      // Bound polling to ten minutes. Returning to HuTube always checks again.
      take(60),
      filter(() => this.document.visibilityState === 'visible'),
      exhaustMap(() => this.surveys.getStatus().pipe(timeout(15_000), catchError(() => EMPTY))),
    ).subscribe(status => this.acceptStatus(status));
    this.visit.add(this.polling);
  }

  private refreshStatus(showInvitation = false): void {
    this.visit.add(this.surveys.getStatus().pipe(timeout(15_000), retry({ count: 2, delay: 5_000 }), catchError(() => EMPTY))
      .subscribe(status => this.acceptStatus(status, showInvitation)));
  }

  private acceptStatus(status: FeedbackSurveyStatus, showInvitation = false): void {
    if (status.hasCompleted) {
      this.completed = true;
      this.formUrl.set(null);
      this.polling?.unsubscribe();
      if (this.phase() !== 'closed') this.phase.set('thanks');
    } else if (!status.enabled || !status.formUrl) {
      this.phase.set('closed');
      this.polling?.unsubscribe();
    } else if (!this.completed) {
      this.formUrl.set(status.formUrl);
      if (showInvitation) this.showWhenVisible();
    }
  }

  private showWhenVisible(): void {
    if (this.document.visibilityState === 'visible') {
      this.phase.set('invitation');
      return;
    }
    const show = () => {
      if (this.document.visibilityState !== 'visible') return;
      this.document.removeEventListener('visibilitychange', show);
      // The survey may have been completed in another tab while this one was hidden.
      if (!this.completed) this.refreshStatus(true);
    };
    this.document.addEventListener('visibilitychange', show);
    this.visit.add(() => this.document.removeEventListener('visibilitychange', show));
  }

  private restoreScroll(): void {
    if (this.savedOverflow !== null) {
      this.document.body.style.overflow = this.savedOverflow;
      this.savedOverflow = null;
    }
  }
}
