import { Component, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdminPlan, AdminPlansService, SavePlanRequest } from './admin-plans.service';
import { AuthService, errorMessage } from '../../core/auth.service';

const emptyDraft = (): SavePlanRequest => ({ code: '', name: '', description: '', price: 0, durationDays: 30, storageLimit: 10, maxUploadSize: 1, maxVideoDuration: 720, maxVideoQuality: '720p', maxMembers: 1, status: 'active', features: '{}' });

@Component({ selector: 'app-admin-plans-page', imports: [FormsModule, DecimalPipe], templateUrl: './admin-plans-page.html', styleUrl: './admin-plans-page.scss' })
export class AdminPlansPage {
  private readonly service = inject(AdminPlansService);
  readonly auth = inject(AuthService);
  readonly plans = signal<AdminPlan[]>([]);
  readonly loading = signal(true);
  readonly saving = signal(false);
  readonly error = signal('');
  readonly message = signal('');
  readonly editing = signal<AdminPlan | null>(null);
  readonly creating = signal(false);
  draft: SavePlanRequest = emptyDraft();

  constructor() { this.load(); }
  load() { this.loading.set(true); this.service.plans().subscribe({ next: plans => { this.plans.set(plans); this.loading.set(false); }, error: error => { this.error.set(errorMessage(error)); this.loading.set(false); } }); }
  openCreate() { this.editing.set(null); this.creating.set(true); this.draft = emptyDraft(); this.error.set(''); this.message.set(''); }
  applyTemplate(template: 'creator' | 'pro_monthly' | 'pro_yearly') {
    this.openCreate();
    this.draft = template === 'creator'
      ? { ...this.draft, code: 'creator_plus', name: 'Creator Plus', description: 'Gói nâng cao cho nhà sáng tạo.', price: 99000, durationDays: 30, storageLimit: 100, maxUploadSize: 20, maxVideoQuality: '1080p', maxMembers: 1 }
      : { ...this.draft, code: template === 'pro_monthly' ? 'pro_family_monthly' : 'pro_family_yearly', name: template === 'pro_monthly' ? 'Pro Group Monthly' : 'Pro Group Yearly', description: 'Gói nhóm gồm chủ gói và 4 thành viên qua Gmail.', price: template === 'pro_monthly' ? 299000 : 2990000, durationDays: template === 'pro_monthly' ? 30 : 365, storageLimit: 500, maxUploadSize: 50, maxVideoQuality: '2160p', maxMembers: 5 };
  }
  openEdit(plan: AdminPlan) { this.creating.set(false); this.editing.set(plan); this.draft = { code: plan.code, name: plan.name, description: plan.description ?? '', price: plan.price, durationDays: plan.durationDays, storageLimit: Math.round(plan.storageLimit / 1073741824), maxUploadSize: Math.round(plan.maxUploadSize / 1073741824), maxVideoDuration: plan.maxVideoDuration, maxVideoQuality: plan.maxVideoQuality ?? '720p', maxMembers: plan.maxMembers, status: plan.status, features: '{}' }; this.error.set(''); this.message.set(''); }
  closeEditor() { this.editing.set(null); this.creating.set(false); }
  save() {
    if (this.saving()) return;
    const request: SavePlanRequest = { ...this.draft, storageLimit: Math.round(this.draft.storageLimit * 1073741824), maxUploadSize: Math.round(this.draft.maxUploadSize * 1073741824) };
    this.saving.set(true); this.error.set('');
    const call = this.editing() ? this.service.updatePlan(this.editing()!.planId, request) : this.service.createPlan(request);
    call.subscribe({ next: () => { this.message.set(this.editing() ? 'Đã cập nhật gói.' : 'Đã tạo gói.'); this.closeEditor(); this.load(); this.saving.set(false); }, error: error => { this.error.set(errorMessage(error)); this.saving.set(false); } });
  }
  archive(plan: AdminPlan) { if (!confirm(`Lưu trữ gói ${plan.name}?`)) return; this.service.archivePlan(plan.planId).subscribe({ next: () => { this.message.set('Đã lưu trữ gói.'); this.load(); }, error: error => this.error.set(errorMessage(error)) }); }
}
