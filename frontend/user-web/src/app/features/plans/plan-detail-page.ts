import { Component, inject, signal } from '@angular/core';
import { CurrencyPipe } from '@angular/common';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { MyPlan, Plan, PlanService, PlanShare } from '../../core/plan.service';

@Component({ selector: 'app-plan-detail-page', imports: [CurrencyPipe, RouterLink], templateUrl: './plan-detail-page.html', styleUrl: './plan-detail-page.scss' })
export class PlanDetailPage {
  private route = inject(ActivatedRoute);
  private plansService = inject(PlanService);
  readonly auth = inject(AuthService);
  readonly plan = signal<Plan | null>(null);
  readonly myPlan = signal<MyPlan | null>(null);
  readonly share = signal<PlanShare | null>(null);
  readonly loading = signal(true);
  readonly message = signal('');
  readonly error = signal('');
  readonly busy = signal(false);

  constructor() {
    const planId = this.route.snapshot.paramMap.get('planId');
    if (!planId) { this.error.set('Gói dịch vụ không hợp lệ.'); this.loading.set(false); return; }
    this.plansService.getPlan(planId).subscribe({
      next: plan => { this.plan.set(plan); this.loading.set(false); },
      error: () => { this.error.set('Không tìm thấy gói dịch vụ.'); this.loading.set(false); }
    });
    this.plansService.getShare(planId).subscribe({ next: share => this.share.set(share), error: () => {} });
    if (this.auth.user()) {
      this.plansService.getMyPlan().subscribe({ next: mp => this.myPlan.set(mp), error: () => {} });
    }
  }

  isCurrentActivePlan(): boolean {
    const p = this.plan();
    const mp = this.myPlan();
    if (!p || !mp || mp.planId !== p.planId) return false;
    if (mp.subscription && mp.subscription.isExpired) return false;
    return true;
  }

  canSwitchToThisPlan(): boolean {
    const p = this.plan();
    const mp = this.myPlan();
    if (!mp || !mp.planId) return true; // Chưa có gói -> đăng ký mới được
    if (mp.subscription && mp.subscription.isExpired) return true; // Gói cũ đã hết hạn -> đăng ký được
    if (mp.price === 0) return true; // Gói miễn phí -> được mua gói trả phí
    // Gói cũ chưa hết hạn -> không được hạ gói, chỉ đổi sang gói đã mua và còn hạn
    return mp.price > 0 && !!p && p.price >= mp.price && (mp.activePaidPlanIds ?? []).includes(p.planId);
  }

  async copyShareUrl() {
    const url = this.share()?.shareUrl;
    if (!url) return;
    try {
      if (!navigator.clipboard) throw new Error('clipboard-unavailable');
      await navigator.clipboard.writeText(url);
      this.message.set('Đã sao chép liên kết chia sẻ.');
    } catch {
      this.error.set('Không thể sao chép tự động. Hãy chọn và sao chép liên kết trong ô bên trên.');
    }
  }

  async nativeShare() {
    const share = this.share();
    if (!share || !navigator.share) return this.copyShareUrl();
    try {
      await navigator.share({ title: share.name, text: share.description || `Gói ${share.name} của HuTube`, url: share.shareUrl });
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') return;
      this.error.set('Không thể mở bảng chia sẻ trên thiết bị này.');
    }
  }

  formatBytes(bytes: number): string {
    if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toLocaleString('vi-VN', { maximumFractionDigits: 2 })} GB`;
    return `${(bytes / 1024 ** 2).toLocaleString('vi-VN', { maximumFractionDigits: 2 })} MB`;
  }

  formatDuration(seconds: number): string {
    const minutes = Math.max(1, Math.round((seconds || 0) / 60));
    const hours = Math.floor(minutes / 60);
    const remainder = minutes % 60;
    if (!hours) return `${minutes} phút`;
    return remainder ? `${hours} giờ ${remainder} phút` : `${hours} giờ`;
  }

  hasFeature(plan: Plan, key: string): boolean { return plan.features?.[key] === true; }

  subscribe() {
    const plan = this.plan();
    if (!plan || this.busy()) return;
    this.busy.set(true); this.error.set('');
    this.plansService.subscribe(plan.planId).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: () => {
        this.message.set('Đăng ký gói thành công. Bạn có thể quản lý quota và thành viên trong Gói của tôi.');
        this.plansService.getMyPlan().subscribe({ next: myPlan => this.myPlan.set(myPlan), error: () => {} });
      },
      error: err => this.error.set(err?.error?.detail || err?.error?.message || `${err?.error?.code || 'Lỗi'} (${err?.status || 500})`)
    });
  }
}
