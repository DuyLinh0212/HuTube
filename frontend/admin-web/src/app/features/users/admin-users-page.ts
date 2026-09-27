import { CommonModule } from '@angular/common';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AuthService, errorMessage } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';
import {
  AdminRoleOption,
  AdminUserDetail,
  AdminUserItem,
  AdminUserCategoryStatistic,
  AdminUserStatistics,
  AdminUsersService,
  AdminUserStatus,
} from './admin-users.service';

type UserAction = 'lock' | 'unlock' | 'role';

@Component({
  selector: 'app-admin-users-page',
  standalone: true,
  imports: [CommonModule, FormsModule, TranslatePipe],
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
  readonly statisticsModal = signal(false);
  readonly statisticsUser = signal<AdminUserItem | AdminUserDetail | null>(null);
  readonly statistics = signal<AdminUserStatistics | null>(null);
  readonly statisticsLoading = signal(false);
  readonly statisticsError = signal('');
  readonly statisticsFrom = signal(this.toDateInput(-29));
  readonly statisticsTo = signal(this.toDateInput(0));
  readonly topicColors = ['#2563eb', '#0f9f8f', '#8b5cf6', '#f59e0b', '#e11d48', '#64748b'];
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
        { roleId: 'user', code: 'user', name: this.i18n.t('users.role.user') },
        { roleId: 'creator', code: 'creator', name: this.i18n.t('users.role.creator') },
        { roleId: 'moderator', code: 'moderator', name: this.i18n.t('users.role.moderator') },
        { roleId: 'admin', code: 'admin', name: this.i18n.t('users.role.admin') },
        { roleId: 'super-admin', code: 'super_admin', name: this.i18n.t('users.role.super_admin') },
      ]),
    });
  }

  load(page = this.page(), forceDetailRefresh = false): void {
    this.page.set(Math.max(1, page));
    this.loading.set(true);
    this.error.set('');
    const refreshToken = forceDetailRefresh ? Date.now() : undefined;
    this.service.getUsers(this.page(), this.pageSize, this.searchQuery(), this.selectedRole(), this.selectedStatus(), refreshToken).subscribe({
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
          if (current) this.selectUser(current, forceDetailRefresh);
        }
      },
      error: error => {
        this.loading.set(false);
        this.error.set(errorMessage(error, this.i18n));
      },
    });
  }

  refresh(): void {
    if (this.loading()) return;
    this.load(this.page(), true);
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

  selectUser(user: AdminUserItem, force = false): void {
    if (!force && this.selectedUserId() === user.userId && this.selectedUser()) return;
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
        this.error.set(errorMessage(error, this.i18n));
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

  openStatistics(user: AdminUserItem | AdminUserDetail | null = this.selectedUser()): void {
    if (!user) return;
    this.statisticsUser.set(user);
    this.statisticsModal.set(true);
    this.loadStatistics();
  }

  closeStatistics(): void {
    this.statisticsModal.set(false);
  }

  loadStatistics(): void {
    const user = this.statisticsUser();
    const from = this.statisticsFrom();
    const to = this.statisticsTo();
    if (!user || !from || !to || from > to) {
      this.statisticsError.set(this.i18n.t('users.statistics.invalidRange'));
      return;
    }
    this.statisticsLoading.set(true);
    this.statisticsError.set('');
    this.statistics.set(null);
    this.service.getStatistics(user.userId, from, to).subscribe({
      next: result => {
        this.statistics.set(result);
        this.statisticsLoading.set(false);
      },
      error: error => {
        this.statisticsLoading.set(false);
        this.statistics.set(null);
        this.statisticsError.set(errorMessage(error, this.i18n));
      },
    });
  }

  setStatisticsPreset(days: number): void {
    const end = new Date();
    const start = new Date(end);
    start.setDate(start.getDate() - Math.max(0, days - 1));
    this.statisticsFrom.set(this.toDateInputFor(start));
    this.statisticsTo.set(this.toDateInputFor(end));
    this.loadStatistics();
  }

  topicGradient(): string {
    const categories = this.topicCategories();
    if (!categories.length) return 'conic-gradient(#edf1f7 0 100%)';
    const total = categories.reduce((sum, category) => sum + Math.max(0, category.percentage), 0) || 100;
    let offset = 0;
    const stops = categories.map((category, index) => {
      const start = offset;
      offset += Math.max(0, category.percentage) * 100 / total;
      return `${this.topicColors[index % this.topicColors.length]} ${start}% ${offset}%`;
    });
    return `conic-gradient(${stops.join(', ')})`;
  }

  topicColor(index: number): string {
    return this.topicColors[index % this.topicColors.length];
  }

  topicCategories(): AdminUserCategoryStatistic[] {
    const categories = this.statistics()?.categories ?? [];
    if (categories.length <= 5) return categories;
    const top = categories.slice(0, 5);
    const other = categories.slice(5);
    const interactionCount = other.reduce((total, category) => total + category.interactionCount, 0);
    const percentage = other.reduce((total, category) => total + category.percentage, 0);
    return [...top, {
      categoryId: 'other',
      categoryName: this.i18n.t('users.statistics.otherTopics'),
      interactionCount,
      percentage: Math.round(percentage * 10) / 10,
    }];
  }

  topicLabel(category: { categoryName: string | null }): string {
    return category.categoryName?.trim() || this.i18n.t('users.statistics.uncategorized');
  }

  formatWatchTime(seconds: number): string {
    const safeSeconds = Math.max(0, Math.round(seconds));
    const hours = Math.floor(safeSeconds / 3600);
    const minutes = Math.floor((safeSeconds % 3600) / 60);
    const remaining = safeSeconds % 60;
    if (hours > 0) return this.i18n.t('users.statistics.watchTimeHours', { hours, minutes });
    if (minutes > 0) return this.i18n.t('users.statistics.watchTimeMinutes', { minutes, seconds: remaining });
    return this.i18n.t('users.statistics.watchTimeSeconds', { seconds: remaining });
  }

  recommendationMatchKey(item: { watched: boolean; categoryInteractionPercentage: number }): string {
    if (item.watched) return 'users.statistics.matchWatched';
    if (item.categoryInteractionPercentage > 0) return 'users.statistics.matchCategory';
    return 'users.statistics.matchNew';
  }

  reactionLabel(reaction: string | null): string {
    if (!reaction) return this.i18n.t('users.statistics.noReaction');
    return this.i18n.t(reaction.toLowerCase() === 'like' ? 'users.statistics.like' : 'users.statistics.dislike');
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
        this.showSuccess(this.i18n.t(action === 'role' ? 'users.success.roleUpdated' : action === 'lock' ? 'users.success.locked' : 'users.success.unlocked'));
        this.load();
      },
      error: error => {
        this.savingAction.set(false);
        this.error.set(errorMessage(error, this.i18n));
      },
    });
  }

  statusLabel(status: AdminUserStatus | string): string {
    const key = `users.status.${status}`;
    const translated = this.i18n.t(key);
    return translated === key ? status : translated;
  }

  roleLabel(user: Pick<AdminUserItem, 'roleCode' | 'roleName'>): string {
    const key = `users.role.${user.roleCode}`;
    const translated = this.i18n.t(key);
    return translated === key ? user.roleName || user.roleCode : translated;
  }

  formatDate(value: string | null): string {
    if (!value) return this.i18n.t('users.dateUnavailable');
    const locale = this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US';
    return new Intl.DateTimeFormat(locale, { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value));
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
    const keys: Record<string, string> = {
      'admin.user_locked': 'users.audit.userLocked',
      'admin.user_unlocked': 'users.audit.userUnlocked',
      'admin.user_role_updated': 'users.audit.roleUpdated',
      'strike.issued': 'users.audit.strikeIssued',
      'strike.revoked': 'users.audit.strikeRevoked',
      'moderation.warned': 'users.audit.warned',
      'channel.suspended': 'users.audit.channelSuspended',
      'channel.unlocked': 'users.audit.channelUnlocked',
    };
    const key = keys[action];
    return key ? this.i18n.t(key) : action;
  }

  private toDateInput(daysFromToday: number): string {
    const date = new Date();
    date.setDate(date.getDate() + daysFromToday);
    return this.toDateInputFor(date);
  }

  private toDateInputFor(date: Date): string {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  private showSuccess(message: string): void {
    this.success.set(message);
    window.setTimeout(() => this.success.set(''), 3500);
  }
}
