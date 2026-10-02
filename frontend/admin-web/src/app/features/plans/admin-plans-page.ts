import { Component, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdminPlan, AdminPlansService, SavePlanRequest } from './admin-plans.service';
import { AuthService, errorMessage } from '../../core/auth.service';
import { TranslatePipe } from '../../core/translate.pipe';
import { I18nService } from '../../core/i18n.service';

const BYTES_PER_GIB = 1024 ** 3;
const bytesToGiB = (bytes: number) => Number((bytes / BYTES_PER_GIB).toFixed(2));
const giBToBytes = (gib: number) => Math.round(gib * BYTES_PER_GIB);
const emptyDraft = (): SavePlanRequest => ({ code: '', name: '', description: '', price: 0, durationDays: 30, storageLimit: 10, maxUploadSize: 1, maxVideoDuration: 720, maxVideoQuality: '720p', maxDownloadQuality: '720p', maxMembers: 1, status: 'active', features: '{"download":false,"background_play":false,"pip":false,"video_promotion":false}', displayOrder: 0 });

@Component({ selector: 'app-admin-plans-page', imports: [FormsModule, DecimalPipe, TranslatePipe], templateUrl: './admin-plans-page.html', styleUrl: './admin-plans-page.scss' })
export class AdminPlansPage {
  private readonly service = inject(AdminPlansService);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);
  readonly plans = signal<AdminPlan[]>([]);
  readonly loading = signal(true);
  readonly saving = signal(false);
  readonly error = signal('');
  readonly message = signal('');
  readonly editing = signal<AdminPlan | null>(null);
  readonly creating = signal(false);
  draft: SavePlanRequest = emptyDraft();

  constructor() { this.load(); }
  load() { this.loading.set(true); this.service.plans().subscribe({ next: plans => { this.plans.set(plans); this.loading.set(false); }, error: error => { this.error.set(errorMessage(error, this.i18n)); this.loading.set(false); } }); }
  openCreate() { this.editing.set(null); this.creating.set(true); this.draft = emptyDraft(); this.error.set(''); this.message.set(''); }
  applyTemplate(template: 'creator' | 'pro_monthly' | 'pro_yearly') {
    this.openCreate();
    this.draft = template === 'creator'
      ? { ...this.draft, code: 'creator_plus', name: 'Creator Plus', description: this.i18n.t('plans.creatorDescription'), price: 99000, durationDays: 30, storageLimit: 100, maxUploadSize: 20, maxVideoQuality: '1080p', maxDownloadQuality: '1080p', maxMembers: 1, features: '{"download":true,"background_play":true,"pip":true,"video_promotion":false}', displayOrder: 2 }
      : { ...this.draft, code: template === 'pro_monthly' ? 'pro_family_monthly' : 'pro_family_yearly', name: template === 'pro_monthly' ? 'Pro Group Monthly' : 'Pro Group Yearly', description: this.i18n.t('plans.groupDescription'), price: template === 'pro_monthly' ? 299000 : 2990000, durationDays: template === 'pro_monthly' ? 30 : 365, storageLimit: 500, maxUploadSize: 50, maxVideoQuality: '2160p', maxDownloadQuality: '2160p', maxMembers: 5, features: '{"download":true,"background_play":true,"pip":true,"video_promotion":false}', displayOrder: 3 };
  }
  openEdit(plan: AdminPlan) {
    this.creating.set(false); this.editing.set(plan);
    this.draft = {
      code: plan.code, name: plan.name, description: plan.description ?? '', price: plan.price,
      durationDays: plan.durationDays, storageLimit: bytesToGiB(plan.storageLimit),
      maxUploadSize: bytesToGiB(plan.maxUploadSize), maxVideoDuration: Math.max(1, Math.round(plan.maxVideoDuration / 60)),
      maxVideoQuality: plan.maxVideoQuality ?? '720p', maxDownloadQuality: plan.maxDownloadQuality ?? plan.maxVideoQuality ?? '720p', maxMembers: plan.maxMembers, status: plan.status,
      features: JSON.stringify(plan.features ?? {}), displayOrder: plan.displayOrder ?? 0
    };
    this.error.set(''); this.message.set('');
  }
  closeEditor() { this.editing.set(null); this.creating.set(false); }
  save() {
    if (this.saving()) return;
    const request: SavePlanRequest = {
      ...this.draft,
      storageLimit: giBToBytes(this.draft.storageLimit),
      maxUploadSize: giBToBytes(this.draft.maxUploadSize),
      maxVideoDuration: Math.round(this.draft.maxVideoDuration * 60),
      displayOrder: Math.max(0, Math.round(this.draft.displayOrder ?? 0)),
      features: this.draft.features || '{}'
    };
    this.saving.set(true); this.error.set('');
    const call = this.editing() ? this.service.updatePlan(this.editing()!.planId, request) : this.service.createPlan(request);
    call.subscribe({ next: () => { this.message.set(this.i18n.t(this.editing() ? 'plans.updatedSuccess' : 'plans.createdSuccess')); this.closeEditor(); this.load(); this.saving.set(false); }, error: error => { this.error.set(errorMessage(error, this.i18n)); this.saving.set(false); } });
  }
  featureEnabled(key: string): boolean {
    try {
      const parsed = JSON.parse(this.draft.features || '{}');
      return parsed && typeof parsed === 'object' && parsed[key] === true;
    } catch { return false; }
  }
  setFeature(key: string, enabled: boolean) {
    let current: Record<string, unknown> = {};
    try {
      const parsed = JSON.parse(this.draft.features || '{}');
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) current = parsed;
    } catch { /* The API will return a validation error for malformed custom JSON. */ }
    this.draft = { ...this.draft, features: JSON.stringify({ ...current, [key]: enabled }) };
  }
  statusLabel(status: string): string {
    const key = status === 'active' ? 'plans.status.active' : status === 'inactive' ? 'plans.status.inactive' : status === 'archived' ? 'plans.status.archived' : '';
    return key ? this.i18n.t(key) : status;
  }

  archive(plan: AdminPlan) { if (!confirm(this.i18n.format('plans.archiveConfirm', { name: plan.name }))) return; this.service.archivePlan(plan.planId).subscribe({ next: () => { this.message.set(this.i18n.t('plans.archivedSuccess')); this.load(); }, error: error => this.error.set(errorMessage(error, this.i18n)) }); }
}
