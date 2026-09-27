import { Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { forkJoin } from 'rxjs';
import { AuthService, errorMessage } from '../../core/auth.service';
import { AdminPermission, AdminRbacService, AdminRole } from './admin-rbac.service';
import { TranslatePipe } from '../../core/translate.pipe';
import { I18nService } from '../../core/i18n.service';

type AccessLevel = 'none' | 'view' | 'action' | 'admin';

interface PermissionGroup {
  key: string;
  name: string;
  permissions: AdminPermission[];
}

@Component({
  selector: 'app-admin-rbac-page',
  imports: [FormsModule, TranslatePipe],
  templateUrl: './admin-rbac-page.html',
  styleUrls: ['./admin-rbac-page.scss', './admin-rbac-dialog-overrides.scss'],
})
export class AdminRbacPage {
  private readonly rbac = inject(AdminRbacService);
  private readonly auth = inject(AuthService);
  private readonly i18n = inject(I18nService);

  readonly loading = signal(true);
  readonly error = signal('');
  readonly roleSearch = signal('');
  readonly permissionSearch = signal('');
  readonly roles = signal<AdminRole[]>([]);
  readonly permissions = signal<AdminPermission[]>([]);
  readonly selectedRoleId = signal<string | null>(null);
  readonly editing = signal(false);
  readonly saving = signal(false);
  readonly saveReason = signal('');
  readonly saveMessage = signal('');
  readonly saveFailed = signal(false);
  readonly draftPermissionCodes = signal<string[]>([]);
  readonly createOpen = signal(false);
  readonly creating = signal(false);
  readonly createCode = signal('');
  readonly createName = signal('');
  readonly createDescription = signal('');
  readonly createReason = signal('');
  readonly createPermissionCodes = signal<string[]>([]);
  private readonly moduleOrder = [
    'dashboard', 'user', 'role', 'channel', 'video', 'comment', 'moderation', 'report', 'appeal',
    'plan', 'subscription', 'payment', 'revenue', 'policy', 'taxonomy', 'notification', 'analytics', 'audit', 'system',
  ];

  readonly canEdit = computed(() => this.auth.hasPermission('role.edit'));
  readonly canDelete = computed(() => this.auth.hasPermission('role.delete'));

  readonly selectedRole = computed(() =>
    this.roles().find((role) => role.roleId === this.selectedRoleId()) ?? this.roles()[0] ?? null,
  );

  readonly selectedPermissionCodes = computed(() =>
    this.editing() ? this.draftPermissionCodes() : this.selectedRole()?.permissions ?? [],
  );

  readonly isDirty = computed(() => {
    const role = this.selectedRole();
    if (!role || !this.editing()) return false;
    return !this.sameCodes(role.permissions, this.draftPermissionCodes());
  });

  readonly filteredRoles = computed(() => {
    const query = this.roleSearch().trim().toLocaleLowerCase('vi');
    if (!query) return this.roles();
    return this.roles().filter((role) =>
      [role.name, role.code, role.description ?? ''].join(' ').toLocaleLowerCase('vi').includes(query),
    );
  });

  readonly groups = computed<PermissionGroup[]>(() => {
    const query = this.permissionSearch().trim().toLocaleLowerCase('vi');
    const byGroup = new Map<string, AdminPermission[]>();

    for (const permission of this.permissions()) {
      if (query && ![permission.name, permission.code, permission.description ?? '']
        .join(' ').toLocaleLowerCase('vi').includes(query)) {
        continue;
      }
      const group = permission.code.split('.')[0];
      byGroup.set(group, [...(byGroup.get(group) ?? []), permission]);
    }

    return [...byGroup.entries()]
      .sort(([left], [right]) => this.moduleRank(left) - this.moduleRank(right))
      .map(([key, permissions]) => ({ key, name: this.moduleName(key), permissions }));
  });

  constructor() {
    this.load();
  }

  load() {
    this.loading.set(true);
    this.error.set('');
    forkJoin({ roles: this.rbac.roles(), permissions: this.rbac.permissions() }).subscribe({
      next: ({ roles, permissions }) => {
        this.roles.set(roles);
        this.permissions.set(permissions.filter((permission) => permission.status === 'active'));
        const current = this.selectedRoleId();
        const selected = roles.find((role) => role.roleId === current) ?? roles[0] ?? null;
        this.selectedRoleId.set(selected?.roleId ?? null);
        this.resetDraft(selected);
        this.loading.set(false);
      },
      error: (error) => {
        this.error.set(errorMessage(error, this.i18n));
        this.loading.set(false);
      },
    });
  }

  selectRole(role: AdminRole) {
    this.selectedRoleId.set(role.roleId);
    this.resetDraft(role);
  }

  roleHas(permission: AdminPermission): boolean {
    return this.selectedPermissionCodes().includes(permission.code);
  }

  accessLevel(permission: AdminPermission): AccessLevel {
    if (!this.roleHas(permission)) return 'none';
    if (permission.code.startsWith('system.')) return 'admin';
    if (/\.(manage|edit|create|delete|clone|assign_permission|remove_permission|assign_user|remove_user|change_plan|suspend|ban|unban|force_logout|send_message|export|hide|unhide|remove|restore|strike|remove_strike|claim|review|approve|reject|escalate|reopen|resolve|dismiss|contact_reporter|change|cancel|refund|retry|publish|archive|manage_template)$/.test(permission.code)) {
      return 'action';
    }
    return 'view';
  }

  assignedPermissions(): AdminPermission[] {
    const assigned = new Set(this.selectedPermissionCodes());
    return this.permissions().filter((permission) => assigned.has(permission.code));
  }

  groupAssignedCount(group: PermissionGroup): number {
    const assigned = new Set(this.selectedPermissionCodes());
    return group.permissions.filter((permission) => assigned.has(permission.code)).length;
  }

  permissionCount(role: AdminRole): number {
    return role.permissions.length;
  }

  moduleName(module: string): string {
    return this.i18n.t(this.moduleOrder.includes(module) ? `rbac.module.${module}` : 'rbac.module.other');
  }

  private moduleRank(module: string): number {
    const rank = this.moduleOrder.indexOf(module);
    return rank === -1 ? Number.MAX_SAFE_INTEGER : rank;
  }

  levelLabel(level: AccessLevel): string {
    const labels: Record<AccessLevel, string> = {
      none: this.i18n.t('rbac.none'),
      view: this.i18n.t('rbac.viewOnly'),
      action: this.i18n.t('rbac.action'),
      admin: this.i18n.t('rbac.admin'),
    };
    return labels[level];
  }

  beginEdit() {
    if (!this.canEdit() || !this.selectedRole()) return;
    this.editing.set(true);
    this.saveMessage.set('');
    this.saveFailed.set(false);
    this.saveReason.set('');
    this.draftPermissionCodes.set([...(this.selectedRole()?.permissions ?? [])]);
  }

  cancelEdit() {
    this.resetDraft(this.selectedRole());
    this.saveMessage.set('');
    this.saveFailed.set(false);
  }

  togglePermission(permission: AdminPermission) {
    if (!this.editing() || !this.canEdit()) return;
    const current = new Set(this.draftPermissionCodes());
    current.has(permission.code) ? current.delete(permission.code) : current.add(permission.code);
    this.draftPermissionCodes.set([...current]);
  }

  saveRole() {
    const role = this.selectedRole();
    if (!role || !this.isDirty() || this.saving()) return;
    this.saving.set(true);
    this.saveMessage.set('');
    this.saveFailed.set(false);
    this.rbac.updateRole(role.roleId, {
      name: role.name,
      description: role.description,
      permissionCodes: this.draftPermissionCodes(),
      reason: this.saveReason(),
    }).subscribe({
      next: (updated) => {
        this.roles.update((roles) => roles.map((item) => item.roleId === updated.roleId ? updated : item));
        this.resetDraft(updated);
        this.saveMessage.set(this.i18n.t('rbac.savedSuccess'));
        this.saveFailed.set(false);
        this.saving.set(false);
      },
      error: (error) => {
        this.saveMessage.set(errorMessage(error, this.i18n));
        this.saveFailed.set(true);
        this.saving.set(false);
      },
    });
  }

  openCreate() {
    if (!this.canEdit()) return;
    this.createCode.set('');
    this.createName.set('');
    this.createDescription.set('');
    this.createReason.set('');
    this.createPermissionCodes.set([]);
    this.createOpen.set(true);
  }

  closeCreate() {
    if (!this.creating()) this.createOpen.set(false);
  }

  toggleCreatePermission(permission: AdminPermission) {
    const current = new Set(this.createPermissionCodes());
    current.has(permission.code) ? current.delete(permission.code) : current.add(permission.code);
    this.createPermissionCodes.set([...current]);
  }

  createRole() {
    if (this.creating()) return;
    this.creating.set(true);
    this.saveMessage.set('');
    this.saveFailed.set(false);
    this.rbac.createRole({
      code: this.createCode(),
      name: this.createName(),
      description: this.createDescription().trim() || null,
      permissionCodes: this.createPermissionCodes(),
      reason: this.createReason(),
    }).subscribe({
      next: (created) => {
        this.roles.update((roles) => [...roles, created].sort((left, right) => left.name.localeCompare(right.name, 'vi')));
        this.selectedRoleId.set(created.roleId);
        this.resetDraft(created);
        this.createOpen.set(false);
        this.saveMessage.set(this.i18n.t('rbac.createdSuccess'));
        this.saveFailed.set(false);
        this.creating.set(false);
      },
      error: (error) => {
        this.saveMessage.set(errorMessage(error, this.i18n));
        this.saveFailed.set(true);
        this.creating.set(false);
      },
    });
  }

  deleteSelectedRole() {
    const role = this.selectedRole();
    if (!role || !this.canDelete() || role.isSystemRole || role.status === 'deleted' || role.assignedUserCount > 0) return;
    const reason = window.prompt(this.i18n.format('rbac.deleteReasonPrompt', { name: role.name }))?.trim();
    if (!reason || reason.length < 3 || reason.length > 300) return;
    if (!window.confirm(this.i18n.format('rbac.deleteConfirm', { name: role.name }))) return;
    this.rbac.deleteRole(role.roleId, reason).subscribe({
      next: () => {
        const remaining = this.roles().filter(item => item.roleId !== role.roleId);
        this.roles.set(remaining);
        const nextRole = remaining.find(item => item.roleId === this.selectedRoleId()) ?? remaining[0] ?? null;
        this.selectedRoleId.set(nextRole?.roleId ?? null);
        this.resetDraft(nextRole);
        this.saveMessage.set(this.i18n.format('rbac.deletedSuccess', { name: role.name }));
        this.saveFailed.set(false);
      },
      error: error => {
        this.saveMessage.set(errorMessage(error, this.i18n));
        this.saveFailed.set(true);
      }
    });
  }

  private resetDraft(role: AdminRole | null) {
    this.editing.set(false);
    this.saveReason.set('');
    this.draftPermissionCodes.set([...(role?.permissions ?? [])]);
  }

  private sameCodes(left: string[], right: string[]): boolean {
    return left.length === right.length && left.every((code) => right.includes(code));
  }
}
