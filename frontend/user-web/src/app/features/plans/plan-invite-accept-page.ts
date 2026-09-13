import { Component, inject, signal } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { PlanService } from '../../core/plan.service';
import { AuthService } from '../../core/auth.service';

@Component({ selector: 'app-plan-invite-accept-page', imports: [RouterLink], templateUrl: './plan-invite-accept-page.html', styleUrl: './plan-invite-accept-page.scss' })
export class PlanInviteAcceptPage {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly plans = inject(PlanService);
  readonly auth = inject(AuthService);
  readonly busy = signal(false);
  readonly message = signal('');
  readonly error = signal('');
  readonly memberId = this.route.snapshot.queryParamMap.get('memberId') ?? '';
  readonly token = this.route.snapshot.queryParamMap.get('token') ?? '';

  accept() {
    if (!this.memberId || !this.token || this.busy()) return;
    this.busy.set(true); this.error.set('');
    this.plans.accept(this.memberId, this.token).subscribe({
      next: () => { this.message.set('Đã tham gia gói dịch vụ.'); this.busy.set(false); },
      error: error => { this.error.set(error?.error?.detail || error?.error?.message || 'Lời mời không hợp lệ hoặc đã hết hạn.'); this.busy.set(false); }
    });
  }

  loginUrl(): string {
    return '/login?returnUrl=' + encodeURIComponent(this.router.url);
  }
}
