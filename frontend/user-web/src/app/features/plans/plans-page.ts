import { Component, inject, signal } from '@angular/core';
import { CurrencyPipe, DecimalPipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { MyPlan, Plan, PlanService } from '../../core/plan.service';

@Component({ selector: 'app-plans-page', imports: [CurrencyPipe, DecimalPipe, RouterLink], templateUrl: './plans-page.html', styleUrl: './plans-page.scss' })
export class PlansPage {
  private plansService = inject(PlanService);
  readonly auth = inject(AuthService);
  readonly plans = signal<Plan[]>([]);
  readonly myPlan = signal<MyPlan | null>(null);
  readonly loading = signal(true);
  readonly error = signal('');

  constructor() {
    this.plansService.getPlans().subscribe({
      next: plans => { this.plans.set(plans); this.loading.set(false); },
      error: () => { this.error.set('Không tải được danh sách gói dịch vụ.'); this.loading.set(false); }
    });
    if (this.auth.user()) {
      this.plansService.getMyPlan().subscribe({
        next: mp => this.myPlan.set(mp),
        error: () => {}
      });
    }
  }

  isCurrentPlan(planId: string): boolean {
    const mp = this.myPlan();
    if (!mp || mp.planId !== planId) return false;
    if (mp.subscription && mp.subscription.isExpired) return false;
    return true;
  }

  canSwitch(planId: string): boolean {
    const mp = this.myPlan();
    if (!mp || !mp.planId) return false;
    if (mp.subscription && mp.subscription.isExpired) return false;
    const target = this.plans().find(plan => plan.planId === planId);
    return mp.price > 0 && !!target && target.price >= mp.price && (mp.activePaidPlanIds ?? []).includes(planId);
  }

  formatBytes(bytes: number): string {
    if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toLocaleString('vi-VN', { maximumFractionDigits: 2 })} GB`;
    return `${(bytes / 1024 ** 2).toLocaleString('vi-VN', { maximumFractionDigits: 2 })} MB`;
  }
}