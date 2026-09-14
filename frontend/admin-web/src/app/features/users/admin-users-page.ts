import { CommonModule } from '@angular/common';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { AuthService, errorMessage } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import {
  AdminRoleOption,
  AdminUserDetail,
  AdminUserItem,
  AdminUsersService,
  AdminUserStatus,
} from './admin-users.service';

type UserAction = 'lock' | 'unlock' | 'role';

@Component({
  selector: 'app-admin-users-page',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './admin-users-page.html',
  styleUrl: './admin-users-page.scss',
})
export class AdminUsersPage implements OnInit {
  private readonly service = inject(AdminUsersService);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);

  readonly users = signal<AdminUserItem[]>([]);
  readonly stats = signal({ total: 0, active: 0, blocked: 0, creatorPro: 0 });
  readonly roles = signal<AdminRoleOption[]>([]);
  readonly selectedUserId = signal<string | null>(null);
  readonly selectedUser = signal<AdminUserDetail | null>(null);
  readonly actionTarget = signal<AdminUserItem | AdminUserDetail | null>(null);
  readonly page = signal(1);
  readonly pageSize = 10;
  readonly resultTotal = signal(0);
  readonly hasMore = signal(false);
  readonly loading = signal(true);
  readonly detailLoading = signal(false);
  readonly savingAction = signal(false);
  readonly error = signal('');
  readonly success = signal('');
  readonly searchQuery = signal('');
  readonly selectedRole = signal('ALL');
  readonly selectedStatus = signal('ALL');
  readonly actionModal = signal<UserAction | null>(null);
  readonly actionReason = signal('');
  readonly notifyUser = signal(true);
  readonly actionRole = signal('');
  private searchTimer: ReturnType<typeof setTimeout> | undefined;

  readonly filteredUsers = computed(() => {
    const query = this.searchQuery().trim().toLowerCase();
    const role = this.selectedRole();
    const status = this.selectedStatus();
    return this.users().filter(user => {
      const matchesQuery = !query || [user.displayName, user.username, user.email, user.userId]
        .some(value => value.toLowerCase().includes(query));
      const matchesRole = role === 'ALL' || user.roleCode === role;
      const matchesStatus = status === 'ALL' || user.status === status;
      return matchesQuery && matchesRole && matchesStatus;
    });
  });

  ngOnInit(): void {
    this.load(1);
    this.service.getRoles().subscribe({
      next: roles => this.roles.set(roles),
      error: () => this.roles.set([
        { roleId: 'user', code: 'user', name: 'Viewer' },
        { roleId: 'creator', code: 'creator', name: 'Creator' },
        { roleId: 'moderator', code: 'moderator', name: 'Moderator' },
        { roleId: 'admin', code: 'admin', name: 'Administrator' },
        { roleId: 'super-admin', code: 'super_admin', name: 'Super Administrator' },
      ]),
    });
  }

  load(page = this.page()): void {
    this.page.set(Math.max(1, page));
    this.loading.set(true);
    this.error.set('');
    this.service.getUsers(this.page(), this.pageSize, this.searchQuery(), this.selectedRole(), this.selectedStatus()).subscribe({
      next: response => {
        this.users.set(response.items);
        this.stats.set(response.stats);
        this.resultTotal.set(response.total);
        this.hasMore.set(response.hasMore);
        this.loading.set(false);
        const selected = this.selectedUserId();
        const firstVisible = this.filteredUsers()[0];
        if (!selected || !response.items.some(user => user.userId === selected)) {
          if (firstVisible) this.selectUser(firstVisible);
          else {
            this.selectedUserId.set(null);
            this.selectedUser.set(null);
          }
        } else {
          const current = response.items.find(user => user.userId === selected);
          if (current) this.selectUser(current);
        }
      },
      error: error => {
        this.loading.set(false);
        this.error.set(errorMessage(error));
      },
    });
  }

  onSearchChanged(value: string): void {
    this.searchQuery.set(value);
    if (this.searchTimer) clearTimeout(this.searchTimer);
    this.searchTimer = setTimeout(() => this.load(1), 350);
  }

  onStatusChanged(value: string): void {
    this.selectedStatus.set(value);
    this.load(1);
  }

  onRoleChanged(value: string): void {
    this.selectedRole.set(value);
    this.load(1);
  }

  rangeStart(): number {
    return this.resultTotal() === 0 ? 0 : (this.page() - 1) * this.pageSize + 1;
  }

  rangeEnd(): number {
    return Math.min(this.page() * this.pageSize, this.resultTotal());
  }

  selectUser(user: AdminUserItem): void {
    if (this.selectedUserId() === user.userId && this.selectedUser()) return;
    this.selectedUserId.set(user.userId);
    this.selectedUser.set(null);
    this.detailLoading.set(true);
    this.service.getUser(user.userId).subscribe({
      next: detail => {
        this.selectedUser.set(detail);
        this.detailLoading.set(false);
      },
      error: error => {
        this.detailLoading.set(false);
        this.error.set(errorMessage(error));
      },
    });
  }

  openAction(action: UserAction, user: AdminUserItem | AdminUserDetail | null = this.selectedUser()): void {
    if (!user) return;
    this.selectedUserId.set(user.userId);
    this.actionTarget.set(user);
    if (this.selectedUser()?.userId !== user.userId) this.selectUser(user);
    this.actionModal.set(action);
    this.actionReason.set('');
    this.notifyUser.set(true);
    this.actionRole.set(user.roleCode);
  }

  closeAction(): void {
    if (!this.savingAction()) {
      this.actionModal.set(null);
      this.actionTarget.set(null);
    }
  }

  submitAction(): void {
    const user = this.actionTarget();
    const action = this.actionModal();
    const reason = this.actionReason().trim();
    if (!user || !action || reason.length < 3 || this.savingAction()) return;

    this.savingAction.set(true);
    this.error.set('');
    const request$ = action === 'lock'
      ? this.service.lock(user.userId, { reason, notify: this.notifyUser() })
      : action === 'unlock'
        ? this.service.unlock(user.userId, { reason, notify: this.notifyUser() })
        : this.service.updateRole(user.userId, { roleCode: this.actionRole(), reason });

    request$.subscribe({
      next: detail => {
        this.savingAction.set(false);
        this.actionModal.set(null);
        this.actionTarget.set(null);
        this.selectedUser.set(detail);
        this.showSuccess(action === 'role' ? 'Đã cập nhật vai trò.' : action === 'lock' ? 'Đã khóa tài khoản.' : 'Đã mở khóa tài khoản.');
        this.load();
      },
      error: error => {
        this.savingAction.set(false);
        this.error.set(errorMessage(error));
      },
    });
  }

  statusLabel(status: AdminUserStatus | string): string {
    return ({ active: 'Hoạt động', banned: 'Đã khóa', suspended: 'Tạm khóa', pending: 'Chờ xác minh', deleted: 'Đã xóa' } as Record<string, string>)[status] ?? status;
  }

  roleLabel(user: Pick<AdminUserItem, 'roleCode' | 'roleName'>): string {
    return user.roleName || ({ super_admin: 'Super Administrator', admin: 'Administrator', moderator: 'Moderator', creator: 'Creator', user: 'Viewer' } as Record<string, string>)[user.roleCode] || user.roleCode;
  }

  formatDate(value: string | null): string {
    if (!value) return 'Chưa có dữ liệu';
    return new Intl.DateTimeFormat('vi-VN', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value));
  }

  getInitials(name: string): string {
    return name.split(/\s+/).filter(Boolean).slice(-2).map(part => part[0]).join('').toUpperCase() || '?';
  }

  canBan(): boolean { return this.auth.hasPermission('user.ban'); }
  canEdit(): boolean { return this.auth.hasPermission('user.edit'); }

  isBlocked(user: Pick<AdminUserItem, 'status'>): boolean {
    return user.status === 'banned' || user.status === 'suspended';
  }

  auditLabel(action: string): string {
    return ({
      'admin.user_locked': 'Khóa tài khoản',
      'admin.user_unlocked': 'Mở khóa tài khoản',
      'admin.user_role_updated': 'Cập nhật vai trò',
    } as Record<string, string>)[action] ?? action;
  }

  private showSuccess(message: string): void {
    this.success.set(message);
    window.setTimeout(() => this.success.set(''), 3500);
  }
}
