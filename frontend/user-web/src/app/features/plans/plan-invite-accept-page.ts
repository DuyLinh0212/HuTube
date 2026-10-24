import { FeedbackService } from '@dalitu/ui/feedback.service';
import { Component, inject, signal } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { PlanService } from '../../core/plan.service';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({ selector: 'app-plan-invite-accept-page', imports: [RouterLink, TranslatePipe], templateUrl: './plan-invite-accept-page.html', styleUrl: './plan-invite-accept-page.scss' })
export class PlanInviteAcceptPage {
  private readonly feedback = inject(FeedbackService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly plans = inject(PlanService);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);
  readonly busy = signal(false);
  readonly message = signal('');
  readonly error = signal('');
  readonly memberId = this.route.snapshot.queryParamMap.get('memberId') ?? '';
  readonly token = this.route.snapshot.queryParamMap.get('token') ?? '';

  accept(confirmCancelPaidPlan = false) {
    if (!this.memberId || !this.token || this.busy()) return;
    this.busy.set(true); this.error.set('');
    this.plans.accept(this.memberId, this.token, confirmCancelPaidPlan).subscribe({
      next: () => { this.message.set(this.i18n.t('plans.joined')); this.busy.set(false); },
      error: async (err) => {
        this.busy.set(false);
        if (!confirmCancelPaidPlan && err?.error?.code === 'PAID_PLAN_CONFIRMATION_REQUIRED') {
          if ((await this.feedback.confirm(err.error.message || this.i18n.t('plans.paidJoinWarning')))) this.accept(true);
          return;
        }
        this.error.set(err?.error?.message || this.i18n.t('plans.inviteInvalid'));
      }
    });
  }

  loginUrl(): string {
    return '/login?returnUrl=' + encodeURIComponent(this.router.url);
  }
}
