import { CurrencyPipe, DatePipe, DecimalPipe } from '@angular/common';
import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { MyPlan, Plan, PlanMember, PlanService } from '../../core/plan.service';

export type PlansView = 'overview' | 'catalog';

@Component({
  selector: 'app-plans-page',
  imports: [CurrencyPipe, DatePipe, DecimalPipe, FormsModule, RouterLink],
  templateUrl: './plans-page.html',
  styleUrl: './plans-page.scss'
})
export class PlansPage {
  private readonly plansService = inject(PlanService);
  readonly auth = inject(AuthService);

  readonly view = signal<PlansView>('overview');
  readonly plans = signal<Plan[]>([]);
  readonly myPlan = signal<MyPlan | null>(null);
  readonly loading = signal(true);
  readonly planLoading = signal(false);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly message = signal('');
  inviteEmail = '';

  constructor() {
    this.load();
  }

  setView(view: PlansView) {
    this.view.set(view);
  }

  load() {
    this.loading.set(true);
    this.planLoading.set(false);
    this.error.set('');
    this.message.set('');
    this.myPlan.set(null);

    this.plansService.getPlans().pipe(finalize(() => this.loading.set(false))).subscribe({
      next: plans => this.plans.set(plans),
      error: () => this.error.set('Không tải được danh sách gói dịch vụ.')
    });

    const loadCurrentPlan = () => {
      this.planLoading.set(true);
      this.plansService.getMyPlan().pipe(finalize(() => this.planLoading.set(false))).subscribe({
        next: plan => this.myPlan.set(plan),
        error: () => this.myPlan.set(null)
      });
    };

    if (this.auth.user()) {
      loadCurrentPlan();
    } else {
      this.auth.restore().subscribe({
        next: authenticated => { if (authenticated) loadCurrentPlan(); },
        error: () => undefined
      });
    }
  }

  isCurrentPlan(planId: string): boolean {
    const current = this.myPlan();
    if (!current || current.planId !== planId) return false;
    return !current.subscription || !current.subscription.isExpired;
  }

  canSwitch(planId: string): boolean {
    const current = this.myPlan();
    if (!current || !current.planId || (current.subscription && current.subscription.isExpired)) return false;
    const target = this.plans().find(plan => plan.planId === planId);
    return current.price > 0 && !!target && target.price >= current.price && (current.activePaidPlanIds ?? []).includes(planId);
  }

  quotaPercent(plan: MyPlan) {
    return plan.storageLimit ? Math.min(100, (plan.usedStorage / plan.storageLimit) * 100) : 0;
  }

  featureEnabled(plan: Plan, key: string): boolean {
    return plan.features?.[key] === true;
  }

  formatBytes(bytes: number): string {
    if (bytes >= 1024 ** 3) return (bytes / 1024 ** 3).toLocaleString('vi-VN', { maximumFractionDigits: 2 }) + ' GB';
    return (bytes / 1024 ** 2).toLocaleString('vi-VN', { maximumFractionDigits: 2 }) + ' MB';
  }

  formatDuration(seconds: number): string {
    const minutes = Math.max(1, Math.round((seconds || 0) / 60));
    const hours = Math.floor(minutes / 60);
    const remainder = minutes % 60;
    if (!hours) return minutes + ' phút';
    return remainder ? hours + ' giờ ' + remainder + ' phút' : hours + ' giờ';
  }

  invite() {
    const plan = this.myPlan();
    if (!plan || !this.inviteEmail.trim() || this.busy()) return;

    this.busy.set(true);
    this.error.set('');
    this.plansService.invite(this.inviteEmail.trim()).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: (member: PlanMember) => {
        this.myPlan.update(current => current ? { ...current, members: [...current.members, member] } : current);
        this.inviteEmail = '';
        this.message.set('Đã gửi lời mời qua email.');
      },
      error: (err: any) => this.error.set(err?.error?.detail || err?.error?.message || 'Không thể gửi lời mời.')
    });
  }

  revoke(memberId: string) {
    if (this.busy()) return;

    this.busy.set(true);
    this.error.set('');
    this.plansService.revoke(memberId).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => {
        this.myPlan.update(plan => plan ? { ...plan, members: plan.members.filter(member => member.planMemberId !== memberId) } : plan);
        this.message.set('Đã thu hồi lời mời.');
      },
      error: () => this.error.set('Không thể thu hồi thành viên.')
    });
  }
}
