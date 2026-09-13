import { Component, inject, signal } from '@angular/core';
import { DecimalPipe, DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { MyPlan, PlanMember, PlanService } from '../../core/plan.service';

@Component({ selector: 'app-my-plan-page', imports: [DecimalPipe, DatePipe, FormsModule, RouterLink], templateUrl: './my-plan-page.html', styleUrl: './my-plan-page.scss' })
export class MyPlanPage {
  private plansService = inject(PlanService);
  readonly plan = signal<MyPlan | null>(null);
  readonly loading = signal(true);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly message = signal('');
  inviteEmail = '';

  constructor() { this.load(); }
  quotaPercent(plan: MyPlan) { return plan.storageLimit ? Math.min(100, (plan.usedStorage / plan.storageLimit) * 100) : 0; }
  formatBytes(bytes: number): string {
    if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toLocaleString('vi-VN', { maximumFractionDigits: 2 })} GB`;
    return `${(bytes / 1024 ** 2).toLocaleString('vi-VN', { maximumFractionDigits: 2 })} MB`;
  }
  load() {
    this.loading.set(true);
    this.plansService.getMyPlan().pipe(finalize(() => this.loading.set(false))).subscribe({
      next: (plan: MyPlan | null) => this.plan.set(plan),
      error: () => this.error.set('Không tải được thông tin gói của bạn.')
    });
  }
  invite() {
    if (!this.inviteEmail.trim() || this.busy()) return;
    this.busy.set(true); this.error.set('');
    this.plansService.invite(this.inviteEmail.trim()).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: (member: PlanMember) => {
        this.plan.update((plan: MyPlan | null) => plan ? { ...plan, members: [...plan.members, member] } : plan);
        this.inviteEmail = '';
        this.message.set('Đã gửi lời mời qua email.');
      },
      error: (err: any) => this.error.set(err?.error?.message || 'Không thể gửi lời mời.')
    });
  }
  revoke(memberId: string) {
    if (this.busy()) return;
    this.busy.set(true);
    this.plansService.revoke(memberId).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => {
        this.plan.update((plan: MyPlan | null) => plan ? { ...plan, members: plan.members.filter((member: PlanMember) => member.planMemberId !== memberId) } : plan);
        this.message.set('Đã thu hồi lời mời.');
      },
      error: () => this.error.set('Không thể thu hồi thành viên.')
    });
  }
}