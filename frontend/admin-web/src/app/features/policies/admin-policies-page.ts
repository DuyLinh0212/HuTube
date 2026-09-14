import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';
import { PolicyItem } from '../moderation/admin-moderation.service';
import { AdminPoliciesService, CreatePolicyRequest } from './admin-policies.service';

export type AdminPolicyGroup = 'ALL' | 'guidelines' | 'privacy' | 'terms' | 'monetization' | 'enforcement';

@Component({
  selector: 'app-admin-policies-page',
  standalone: true,
  imports: [CommonModule, FormsModule, TranslatePipe],
  templateUrl: './admin-policies-page.html',
  styleUrl: './admin-policies-page.scss'
})
export class AdminPoliciesPage implements OnInit {
  private readonly policiesService = inject(AdminPoliciesService);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);

  readonly loading = signal(true);
  readonly error = signal<string | null>(null);
  readonly successMessage = signal<string | null>(null);
  readonly policies = signal<PolicyItem[]>([]);

  readonly selectedGroup = signal<AdminPolicyGroup>('ALL');
  readonly searchQuery = signal('');

  // Create Modal
  readonly isCreateModalOpen = signal(false);
  readonly creating = signal(false);
  readonly newCode = signal('');
  readonly newName = signal('');
  readonly newGroup = signal('guidelines');
  readonly newContent = signal('');
  readonly newSeverity = signal('medium');
  readonly newVersion = signal('1.0');

  // View/Edit Modal
  readonly selectedPolicy = signal<PolicyItem | null>(null);
  readonly isDetailModalOpen = signal(false);
  readonly updating = signal(false);
  readonly editContent = signal('');
  readonly editVersion = signal('');

  readonly groupTabs: { key: AdminPolicyGroup; labelKey: string }[] = [
    { key: 'ALL', labelKey: 'policies.all' },
    { key: 'guidelines', labelKey: 'policies.guidelines' },
    { key: 'privacy', labelKey: 'policies.privacy' },
    { key: 'terms', labelKey: 'policies.terms' },
    { key: 'monetization', labelKey: 'policies.monetization' },
    { key: 'enforcement', labelKey: 'policies.enforcement' }
  ];

  readonly filteredPolicies = computed(() => {
    let items = this.policies();
    const group = this.selectedGroup();
    const query = this.searchQuery().trim().toLowerCase();

    if (group !== 'ALL') {
      items = items.filter(p => {
        if (group === 'guidelines') return p.group === 'guidelines' || p.group === 'content';
        if (group === 'terms') return p.group === 'terms' || p.group === 'legal';
        return p.group === group;
      });
    }
    if (query) {
      items = items.filter(p =>
        p.code.toLowerCase().includes(query) ||
        p.name.toLowerCase().includes(query) ||
        this.getPolicyName(p).toLowerCase().includes(query) ||
        p.content.toLowerCase().includes(query) ||
        this.getPolicyContent(p).toLowerCase().includes(query)
      );
    }
    return items;
  });

  getPolicyName(policy: { code: string; name?: string } | null | undefined): string {
    if (!policy) return '';
    const key = `policy.${policy.code}.name`;
    const val = this.i18n.t(key);
    return val !== key ? val : (policy.name || policy.code);
  }

  getPolicyContent(policy: { code: string; content?: string } | null | undefined): string {
    if (!policy) return '';
    const key = `policy.${policy.code}.content`;
    const val = this.i18n.t(key);
    return val !== key ? val : (policy.content || '');
  }

  getGroupLabel(group: string): string {
    switch (group?.toLowerCase()) {
      case 'guidelines':
      case 'content':
        return this.i18n.t('policies.group.guidelines');
      case 'privacy':
        return this.i18n.t('policies.group.privacy');
      case 'terms':
      case 'legal':
        return this.i18n.t('policies.group.terms');
      case 'monetization':
        return this.i18n.t('policies.group.monetization');
      case 'enforcement':
        return this.i18n.t('policies.group.enforcement');
      default:
        return group || this.i18n.t('policies.group.guidelines');
    }
  }

  getSeverityLabel(severity: string): string {
    switch (severity?.toLowerCase()) {
      case 'critical':
        return this.i18n.t('policies.severity.critical');
      case 'high':
        return this.i18n.t('policies.severity.high');
      case 'medium':
        return this.i18n.t('policies.severity.medium');
      case 'low':
        return this.i18n.t('policies.severity.low');
      case 'info':
        return this.i18n.t('policies.severity.info');
      default:
        return severity || this.i18n.t('policies.severity.medium');
    }
  }

  ngOnInit(): void {
    this.loadPolicies();
  }

  loadPolicies(): void {
    this.loading.set(true);
    this.error.set(null);

    this.policiesService.getAdminPolicies().subscribe({
      next: (items) => {
        this.policies.set(items);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err?.error?.detail || this.i18n.t('common.error'));
        this.loading.set(false);
      }
    });
  }

  openCreateModal(): void {
    this.newCode.set('');
    this.newName.set('');
    this.newGroup.set('guidelines');
    this.newContent.set('');
    this.newSeverity.set('medium');
    this.newVersion.set('1.0');
    this.isCreateModalOpen.set(true);
  }

  closeCreateModal(): void {
    this.isCreateModalOpen.set(false);
  }

  createPolicy(): void {
    if (!this.newCode().trim() || !this.newName().trim() || !this.newContent().trim()) {
      alert(this.i18n.t('policies.validationError'));
      return;
    }

    const req: CreatePolicyRequest = {
      code: this.newCode().trim().toUpperCase(),
      name: this.newName().trim(),
      group: this.newGroup(),
      content: this.newContent().trim(),
      severity: this.newSeverity(),
      version: this.newVersion().trim() || '1.0',
      status: 'published'
    };

    this.creating.set(true);
    this.policiesService.createPolicy(req).subscribe({
      next: () => {
        this.creating.set(false);
        this.closeCreateModal();
        this.showMessage(this.i18n.t('policies.msgCreated'));
        this.loadPolicies();
      },
      error: (err) => {
        this.creating.set(false);
        alert(err?.error?.detail || this.i18n.t('common.error'));
      }
    });
  }

  openDetailModal(policy: PolicyItem): void {
    this.selectedPolicy.set(policy);
    this.editContent.set(this.getPolicyContent(policy));
    const parts = policy.version.split('.');
    const nextVer = parts.length === 2 ? `${parts[0]}.${parseInt(parts[1] || '0') + 1}` : `${policy.version}.1`;
    this.editVersion.set(nextVer);
    this.isDetailModalOpen.set(true);
  }

  closeDetailModal(): void {
    this.isDetailModalOpen.set(false);
    this.selectedPolicy.set(null);
  }

  publishNewVersion(): void {
    const policy = this.selectedPolicy();
    if (!policy) return;

    if (!this.editContent().trim()) {
      alert(this.i18n.t('policies.contentEmptyError'));
      return;
    }

    this.updating.set(true);
    this.policiesService.publishPolicy(policy.policyId, {
      name: policy.name,
      group: policy.group,
      content: this.editContent().trim(),
      severity: policy.severity,
      status: 'published',
      version: this.editVersion().trim()
    }).subscribe({
      next: () => {
        this.updating.set(false);
        this.closeDetailModal();
        this.showMessage(this.i18n.t('policies.msgUpdated', { version: this.editVersion(), code: policy.code }));
        this.loadPolicies();
      },
      error: (err) => {
        this.updating.set(false);
        alert(err?.error?.detail || this.i18n.t('common.error'));
      }
    });
  }

  canEdit(): boolean {
    const u = this.auth.user();
    if (!u) return false;
    if (u.role === 'super_admin' || u.role === 'admin' || u.isAdmin) return true;
    return this.auth.hasPermission('system.edit_setting') || this.auth.hasPermission('system.view_setting');
  }

  private showMessage(msg: string): void {
    this.successMessage.set(msg);
    setTimeout(() => this.successMessage.set(null), 4000);
  }
}
