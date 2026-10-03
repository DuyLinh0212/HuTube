import { CommonModule, DatePipe, DecimalPipe } from '@angular/common';
import { Component, computed, inject, signal, OnInit, HostListener, DestroyRef } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';
import {
  AdminChannel,
  AdminChannelDetail,
  AdminChannelsService,
  ChannelCounts
} from './admin-channels.service';
import {
  CustomSelectComponent,
  CustomSelectOption
} from '../../shared/components/custom-select/custom-select.component';

@Component({
  selector: 'app-admin-channels-page',
  standalone: true,
  imports: [CommonModule, FormsModule, DatePipe, DecimalPipe, CustomSelectComponent, TranslatePipe],
  templateUrl: './admin-channels-page.html',
  styleUrl: './admin-channels-page.scss'
})
export class AdminChannelsPage implements OnInit {
  private readonly service = inject(AdminChannelsService);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);

  // Data signals
  readonly channels = signal<AdminChannel[]>([]);
  readonly channelCounts = signal<ChannelCounts>({
    all: 0,
    active: 0,
    restricted: 0,
    banned: 0
  });
  readonly countsAvailable = signal(false);
  readonly selectedChannel = signal<AdminChannelDetail | null>(null);

  // State signals
  readonly loading = signal(false);
  readonly detailLoading = signal(false);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly notice = signal('');

  // Tab & Filters
  readonly activeTab = signal<'all' | 'active' | 'restricted' | 'banned'>('all');
  readonly search = signal('');
  readonly searchTerm = signal('');
  readonly statusFilter = signal('all');
  readonly timeFilter = signal('all');

  // Filter options for CustomSelect
  readonly statusOptions = computed<CustomSelectOption[]>(() => [
    { value: 'all', label: this.i18n.t('common.all') },
    { value: 'active', label: this.i18n.t('channels.status.active') },
    { value: 'suspended', label: this.i18n.t('channels.status.suspended') },
    { value: 'banned', label: this.i18n.t('channels.status.locked') }
  ]);

  readonly timeOptions = computed<CustomSelectOption[]>(() => [
    { value: 'all', label: this.i18n.t('common.all') },
    { value: '7days', label: this.i18n.t('channels.last7Days') },
    { value: '30days', label: this.i18n.t('channels.last30Days') },
    { value: 'thisYear', label: this.i18n.t('channels.thisYear') }
  ]);

  // Pagination
  readonly page = signal(1);
  readonly pageSize = signal(8);
  readonly total = signal(0);

  // Sorting
  readonly sortColumn = signal<string>('createdAt');
  readonly sortDirection = signal<'asc' | 'desc'>('desc');

  // Dropdown menu & Modals
  private menuAnchor: HTMLElement | null = null;
  private menuAnchorTop = 0;
  private menuAnchorLeft = 0;
  readonly menuPosition = signal({ top: 0, left: 0 });
  readonly activeMenuId = signal<string | null>(null);
  readonly showDetailDrawer = signal(false);
  readonly showActionModal = signal(false);
  readonly actionModalType = signal<'suspend' | 'ban' | 'unban' | 'delete' | 'restore' | 'lock' | 'unlock' | null>(null);
  readonly actionModalChannel = signal<AdminChannel | null>(null);
  readonly actionModalReason = signal('');
  readonly notifyOwner = signal(true);

  // Permissions
  readonly canSuspend = computed(() => this.auth.hasPermission('channel.suspend'));
  readonly canBan = computed(() => this.auth.hasPermission('channel.ban'));
  readonly canUnban = computed(() => this.auth.hasPermission('channel.unban'));
  readonly canDelete = computed(() => this.auth.hasPermission('channel.delete'));
  readonly canLock = computed(() => this.auth.hasPermission('channel.lock'));

  // Computed Pagination
  readonly pageCount = computed(() => Math.max(1, Math.ceil(this.total() / this.pageSize())));
  readonly showingStart = computed(() => (this.page() - 1) * this.pageSize() + 1);
  readonly showingEnd = computed(() => Math.min(this.page() * this.pageSize(), this.total()));

  // Visible page numbers matching: < 1 2 3 4 5 ... 1,571 >
  readonly visiblePages = computed(() => {
    const current = this.page();
    const max = this.pageCount();
    const pages: (number | string)[] = [];

    if (max <= 7) {
      for (let i = 1; i <= max; i++) pages.push(i);
    } else {
      if (current <= 4) {
        for (let i = 1; i <= 5; i++) pages.push(i);
        pages.push('...');
        pages.push(max);
      } else if (current >= max - 3) {
        pages.push(1);
        pages.push('...');
        for (let i = max - 4; i <= max; i++) pages.push(i);
      } else {
        pages.push(1);
        pages.push('...');
        pages.push(current - 1);
        pages.push(current);
        pages.push(current + 1);
        pages.push('...');
        pages.push(max);
      }
    }
    return pages;
  });

  constructor() {
    const closeOnScroll = (event: Event) => {
      // Keep scrolling inside the floating menu usable, but close it when its anchor moves.
      if (event.target instanceof Element && event.target.closest('.dropdown-menu')) return;
      const current = this.menuAnchor?.getBoundingClientRect();
      if (current && (current.top !== this.menuAnchorTop || current.left !== this.menuAnchorLeft)) this.closeActionMenu();
    };
    document.addEventListener('scroll', closeOnScroll, true);
    inject(DestroyRef).onDestroy(() => document.removeEventListener('scroll', closeOnScroll, true));
  }

  ngOnInit(): void {
    this.loadCounts();
    this.load();
  }

  loadCounts(): void {
    this.countsAvailable.set(false);
    this.service.getChannelCounts().subscribe({
      next: counts => { this.channelCounts.set(counts); this.countsAvailable.set(true); },
      error: () => { this.countsAvailable.set(false); }
    });
  }

  countLabel(value: number): string { return this.countsAvailable() ? this.formatNumber(value) : '—'; }

  load(page = this.page()): void {
    this.loading.set(true);
    this.error.set('');
    this.page.set(page);

    // Compute status filter from tab or dropdown
    let effectiveStatus = this.statusFilter();
    if (this.activeTab() === 'active') effectiveStatus = 'active';
    else if (this.activeTab() === 'restricted') effectiveStatus = 'suspended';
    else if (this.activeTab() === 'banned') effectiveStatus = 'banned';

    this.service
      .getChannels({
        search: this.searchTerm(),
        status: effectiveStatus,
        sortBy: this.sortColumn(),
        sortDescending: this.sortDirection() === 'desc',
        page,
        pageSize: this.pageSize()
      })
      .subscribe({
        next: result => {
          if (result && result.items) {
            const enriched = result.items.map(ch => ({
              ...ch,
              viewCount: ch.viewCount ?? 0
            }));
            this.channels.set(enriched);
            this.total.set(result.total ?? enriched.length);
          } else {
            this.channels.set([]);
            this.total.set(0);
          }
          this.loading.set(false);
        },
        error: () => {
          this.channels.set([]);
          this.total.set(0);
          this.loading.set(false);
        }
      });
  }

  setStatus(val: string): void {
    this.activeTab.set('all');
    this.statusFilter.set(val);
    this.applyFilters();
  }

  setTime(val: string): void {
    this.timeFilter.set(val);
    this.applyFilters();
  }

  selectTab(tab: 'all' | 'active' | 'restricted' | 'banned'): void {
    if (this.activeTab() === tab) return;
    this.activeTab.set(tab);
    if (tab === 'all') this.statusFilter.set('all');
    else if (tab === 'active') this.statusFilter.set('active');
    else if (tab === 'restricted') this.statusFilter.set('suspended');
    else if (tab === 'banned') this.statusFilter.set('banned');
    this.load(1);
  }

  applyFilters(): void {
    this.searchTerm.set(this.search().trim());
    this.load(1);
  }

  resetFilters(): void {
    this.search.set('');
    this.searchTerm.set('');
    this.statusFilter.set('all');
    this.timeFilter.set('all');
    this.activeTab.set('all');
    this.sortColumn.set('createdAt');
    this.sortDirection.set('desc');
    this.load(1);
  }

  toggleSort(column: string): void {
    if (this.sortColumn() === column) {
      this.sortDirection.set(this.sortDirection() === 'asc' ? 'desc' : 'asc');
    } else {
      this.sortColumn.set(column);
      this.sortDirection.set('desc');
    }
    this.load(1);
  }

  toggleActionMenu(channelId: string, event: MouseEvent): void {
    event.stopPropagation();
    this.menuAnchor = event.currentTarget as HTMLElement;
    const rect = this.menuAnchor.getBoundingClientRect();
    this.menuAnchorTop = rect.top;
    this.menuAnchorLeft = rect.left;
    this.menuPosition.set({ top: Math.max(8, Math.min(rect.bottom + 4, window.innerHeight - 280)), left: Math.max(8, Math.min(rect.right - 210, window.innerWidth - 218)) });
    if (this.activeMenuId() === channelId) {
      this.activeMenuId.set(null);
    } else {
      this.activeMenuId.set(channelId);
    }
  }

  @HostListener('window:resize')
  @HostListener('document:click')
  closeActionMenu(): void {
    this.activeMenuId.set(null);
  }

  openDetail(channel: AdminChannel): void {
    this.activeMenuId.set(null);
    this.selectedChannel.set(null);
    this.detailLoading.set(true);
    this.showDetailDrawer.set(true);

    this.service.getChannelDetail(channel.channelId).subscribe({
      next: detail => {
        this.selectedChannel.set(detail);
        this.detailLoading.set(false);
      },
      error: () => {
        // Fallback detail
        this.selectedChannel.set({
          channel,
          description: null,
          contactEmail: channel.ownerEmail,
          avatarUrl: channel.avatarUrl ?? null,
          bannerUrl: null,
          watermarkUrl: null,
          videos: [],
          history: []
        });
        this.detailLoading.set(false);
      }
    });
  }

  closeDetail(): void {
    this.showDetailDrawer.set(false);
    this.selectedChannel.set(null);
  }

  private allowedAction(action: string): boolean {
    return ({ suspend: this.canSuspend(), ban: this.canBan(), unban: this.canUnban(), restore: this.canUnban(), delete: this.canDelete(), lock: this.canLock(), unlock: this.canLock() } as Record<string, boolean>)[action] ?? false;
  }

  openActionModal(action: 'suspend' | 'ban' | 'unban' | 'delete' | 'restore' | 'lock' | 'unlock', channel: AdminChannel): void {
    if (!this.allowedAction(action)) return;
    this.activeMenuId.set(null);
    this.actionModalType.set(action);
    this.actionModalChannel.set(channel);
    this.actionModalReason.set('');
    this.notifyOwner.set(true);
    this.showActionModal.set(true);
  }

  closeActionModal(): void {
    this.showActionModal.set(false);
    this.actionModalType.set(null);
    this.actionModalChannel.set(null);
    this.actionModalReason.set('');
  }

  submitAction(): void {
    const action = this.actionModalType();
    const channel = this.actionModalChannel();
    const reason = this.actionModalReason().trim();

    if (!action || !channel || reason.length < 3 || this.busy() || !this.allowedAction(action)) return;

    this.busy.set(true);
    this.error.set('');

    const request = { reason, notifyOwner: this.notifyOwner() };

    let call$;
    if (action === 'delete') {
      call$ = this.service.deleteChannel(channel.channelId, request);
    } else if (action === 'lock') {
      call$ = this.service.lockChannel(channel.channelId, reason);
    } else if (action === 'unlock') {
      call$ = this.service.unlockChannel(channel.channelId, reason);
    } else {
      call$ = this.service.channelAction(channel.channelId, action, request);
    }

    call$.subscribe({
      next: () => {
        this.busy.set(false);
        this.closeActionModal();
        this.notice.set(this.i18n.format('channels.actionSuccess', { action: this.actionLabel(action), name: channel.name }));
        setTimeout(() => this.notice.set(''), 4000);
        this.load();
        this.loadCounts();
      },
      error: err => {
        this.busy.set(false);
        this.error.set(err?.error?.message || this.i18n.t('channels.actionError'));
      }
    });
  }

  exportData(): void {
    const list = this.channels();
    if (!list.length) return;
    this.service.exportCsv(list);
  }

  setPage(p: number | string): void {
    if (typeof p !== 'number') return;
    if (p < 1 || p > this.pageCount() || p === this.page()) return;
    this.load(p);
  }

  prevPage(): void {
    if (this.page() > 1) this.load(this.page() - 1);
  }

  nextPage(): void {
    if (this.page() < this.pageCount()) this.load(this.page() + 1);
  }

  onPageSizeChange(event: Event): void {
    const size = Number((event.target as HTMLSelectElement).value);
    this.pageSize.set(size);
    this.load(1);
  }

  // Format Helpers
  formatNumber(val: number): string {
    return new Intl.NumberFormat(this.dateLocale()).format(val || 0);
  }

  formatShort(num: number): string {
    return new Intl.NumberFormat(this.dateLocale(), { notation: 'compact', maximumFractionDigits: 1 }).format(num || 0);
  }

  actionLabel(action: string): string {
    const map: Record<string, string> = {
      suspend: this.i18n.t('channels.suspend'),
      ban: this.i18n.t('channels.banAction'),
      unban: this.i18n.t('channels.restore'),
      delete: this.i18n.t('channels.delete'),
      restore: this.i18n.t('channels.restoreAction'),
      lock: this.i18n.t('channels.banAction'),
      unlock: this.i18n.t('channels.restoreAction')
    };
    return map[action] ?? action;
  }

  auditActionLabel(action: string): string {
    const status = action.startsWith('admin.channel.') ? action.slice('admin.channel.'.length) : '';
    const key = status ? `channels.audit.status.${status}` : '';
    const translated = key ? this.i18n.t(key) : key;
    return translated && translated !== key ? translated : action;
  }

  videoStatusLabel(status: string): string {
    const keys: Record<string, string> = {
      published: 'videos.badge.approved',
      processing: 'videos.badge.processing',
      blocked: 'videos.badge.hidden',
      deleted: 'videos.badge.deleted',
      failed: 'videos.badge.failed',
    };
    return this.i18n.t(keys[status] ?? 'common.unknown');
  }

  statusBadge(status: string): { label: string; cls: string } {
    switch (status?.toLowerCase()) {
      case 'active':
        return { label: this.i18n.t('channels.status.active'), cls: 'status-active' };
      case 'suspended':
        return { label: this.i18n.t('channels.status.suspended'), cls: 'status-restricted' };
      case 'banned':
      case 'locked':
        return { label: this.i18n.t('channels.status.locked'), cls: 'status-locked' };
      case 'deleted':
        return { label: this.i18n.t('channels.status.deleted'), cls: 'status-deleted' };
      default:
        return { label: this.i18n.t('channels.status.active'), cls: 'status-active' };
    }
  }

  dateLocale(): string {
    return this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US';
  }

  getInitials(name: string): string {
    if (!name) return 'K';
    const words = name.trim().split(/\s+/);
    if (words.length >= 2) {
      return (words[0][0] + words[words.length - 1][0]).toUpperCase();
    }
    return name.slice(0, 2).toUpperCase();
  }
}
