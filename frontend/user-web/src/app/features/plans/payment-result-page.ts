import { Component, DestroyRef, inject, signal } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { catchError, exhaustMap, of, take, takeWhile, tap, timer } from 'rxjs';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { PaymentSummary, PlanService } from '../../core/plan.service';
import { LocaleCurrencyPipe } from '../../core/locale-currency.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

type PaymentResultState = 'checking' | 'pending' | 'paid' | 'failed' | 'invalid' | 'unavailable';

@Component({
  selector: 'app-payment-result-page',
  imports: [LocaleCurrencyPipe, RouterLink, TranslatePipe],
  template: `
    <main class="payment-result" aria-live="polite">
      <section class="result-card">
        <div class="result-icon" [class.success]="state() === 'paid'" [class.failure]="state() === 'failed' || state() === 'invalid'">
          @if (state() === 'paid') { ✓ }
          @else if (state() === 'failed' || state() === 'invalid') { ! }
          @else { … }
        </div>
        <h1>{{ 'payment.resultTitle' | translate }}</h1>
        @switch (state()) {
          @case ('checking') { <p>{{ 'payment.resultChecking' | translate }}</p> }
          @case ('pending') { <p>{{ 'payment.resultPending' | translate }}</p> }
          @case ('paid') { <p>{{ 'payment.resultPaid' | translate }}</p> }
          @case ('failed') { <p>{{ 'payment.resultFailed' | translate }}</p> }
          @case ('invalid') { <p>{{ 'payment.resultInvalid' | translate }}</p> }
          @default { <p>{{ 'payment.resultUnavailable' | translate }}</p> }
        }
        @if (payment(); as p) {
          <div class="payment-summary">
            <strong>{{ p.planName }}</strong>
            <span>{{ p.amount | localeCurrency:p.currency }}</span>
          </div>
        }
        @if (state() === 'checking' || state() === 'pending') {
          <div class="progress" role="progressbar"><span></span></div>
        }
        <a routerLink="/plans" class="back-link">{{ 'payment.resultBackToPlans' | translate }}</a>
      </section>
    </main>
  `,
  styles: [`
    :host { display: block; min-height: 60vh; padding: 48px 20px; }
    .payment-result { max-width: 560px; margin: 0 auto; }
    .result-card { padding: 36px; border: 1px solid var(--border-subtle, #dedee5); border-radius: 18px; background: var(--surface-primary, #fff); text-align: center; box-shadow: 0 12px 36px rgba(20, 20, 35, .08); }
    .result-icon { display: grid; place-items: center; width: 64px; height: 64px; margin: 0 auto 18px; border-radius: 50%; background: rgba(80, 105, 242, .12); color: #5069f2; font-size: 34px; font-weight: 800; }
    .result-icon.success { color: #16834a; background: rgba(22, 131, 74, .12); }
    .result-icon.failure { color: #b42318; background: rgba(180, 35, 24, .12); }
    h1 { margin: 0 0 12px; font-size: clamp(1.35rem, 3vw, 1.8rem); }
    p { margin: 0; color: var(--text-secondary, #666); line-height: 1.6; }
    .payment-summary { display: flex; justify-content: space-between; gap: 16px; margin: 24px 0; padding: 16px; border-radius: 12px; background: var(--surface-secondary, #f6f6f9); text-align: left; }
    .progress { height: 3px; margin: 24px 0; overflow: hidden; border-radius: 8px; background: rgba(80, 105, 242, .14); }
    .progress span { display: block; width: 38%; height: 100%; background: #5069f2; animation: progress 1.4s ease-in-out infinite alternate; }
    .back-link { display: inline-flex; margin-top: 24px; color: var(--link-color, #4058dc); font-weight: 700; text-decoration: none; }
    @keyframes progress { to { transform: translateX(160%); } }
    @media (prefers-reduced-motion: reduce) { .progress span { animation: none; width: 100%; } }
  `]
})
export class PaymentResultPage {
  private readonly route = inject(ActivatedRoute);
  private readonly plansService = inject(PlanService);
  private readonly destroyRef = inject(DestroyRef);
  readonly state = signal<PaymentResultState>('checking');
  readonly payment = signal<PaymentSummary | null>(null);

  constructor() {
    const paymentId = this.route.snapshot.queryParamMap.get('paymentId') ?? '';
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(paymentId)) {
      this.state.set('invalid');
      return;
    }

    timer(0, 2000).pipe(
      take(20),
      exhaustMap(() => this.plansService.getPayment(paymentId).pipe(catchError(() => of(null)))),
      tap(result => {
        if (!result) {
          this.state.set('unavailable');
          return;
        }
        this.payment.set(result);
        this.state.set(result.status === 'paid' ? 'paid'
          : result.status === 'failed' || result.status === 'cancelled' ? 'failed' : 'pending');
      }),
      takeWhile(result => result?.status === 'pending', true),
      takeUntilDestroyed(this.destroyRef)
    ).subscribe({
      complete: () => {
        if (this.state() === 'checking' || this.state() === 'pending') this.state.set('pending');
      }
    });
  }
}
