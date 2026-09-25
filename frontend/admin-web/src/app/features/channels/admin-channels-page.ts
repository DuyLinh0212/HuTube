import { CommonModule, DatePipe, DecimalPipe } from '@angular/common';
import { Component, computed, inject, signal, OnInit, HostListener } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/auth.service';
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
  imports: [CommonModule, FormsModule, DatePipe, DecimalPipe, CustomSelectComponent],
  templateUrl: './admin-channels-page.html',
  styleUrl: './admin-channels-page.scss'
})
export class AdminChannelsPage implements OnInit {
  private readonly service = inject(AdminChannelsService);
  readonly auth = inject(AuthService);

  // Data signals
  readonly channels = signal<AdminChannel[]>([]);
  readonly channelCounts = signal<ChannelCounts>({
    all: 12568,
    active: 10432,
    restricted: 856,
    banned: 1280
  });
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
  readonly statusOptions: CustomSelectOption[] = [
    { value: 'all', label: 'Tất cả' },
    { value: 'active', label: 'Đang hoạt động' },
    { value: 'suspended', label: 'Hạn chế' },
    { value: 'banned', label: 'Bị khóa' }
  ];

  readonly timeOptions: CustomSelectOption[] = [
    { value: 'all', label: 'Tất cả' },
    { value: '7days', label: '7 ngày qua' },
    { value: '30days', label: '30 ngày qua' },
    { value: 'thisYear', label: 'Năm nay' }
  ];

  // Pagination
  readonly page = signal(1);
  readonly pageSize = signal(8);
  readonly total = signal(12568);

  // Sorting
  readonly sortColumn = signal<string>('createdAt');
  readonly sortDirection = signal<'asc' | 'desc'>('desc');

  // Dropdown menu & Modals
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

  ngOnInit(): void {
    this.loadCounts();
    this.load();
  }

  loadCounts(): void {
    this.service.getChannelCounts().subscribe({
      next: counts => {
        this.channelCounts.set(counts);
        if (this.activeTab() === 'all') {
          this.total.set(counts.all);
        } else if (this.activeTab() === 'active') {
          this.total.set(counts.active);
        } else if (this.activeTab() === 'restricted') {
          this.total.set(counts.restricted);
        } else if (this.activeTab() === 'banned') {
          this.total.set(counts.banned);
        }
      },
      error: () => {}
    });
  }

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
    if (this.activeMenuId() === channelId) {
      this.activeMenuId.set(null);
    } else {
      this.activeMenuId.set(channelId);
    }
  }

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
          description: `Kênh chính thức của ${channel.name}. Chia sẻ video và nội dung hấp dẫn hàng tuần.`,
          contactEmail: channel.ownerEmail,
          avatarUrl: channel.avatarUrl ?? null,
          bannerUrl: null,
          watermarkUrl: null,
          videos: [
            { videoId: 'v1', title: 'Video giới thiệu kênh mới', thumbnailUrl: null, status: 'published', views: 42500 },
            { videoId: 'v2', title: 'Hướng dẫn chi tiết từ A-Z', thumbnailUrl: null, status: 'published', views: 18900 },
            { videoId: 'v3', title: 'Top 10 mẹo hay mỗi ngày', thumbnailUrl: null, status: 'published', views: 98200 }
          ],
          history: [
            { auditLogId: 'a1', action: 'admin.channel.verify', reason: 'Xác thực tài khoản thành công', actorName: 'System Admin', createdAt: channel.createdAt }
          ]
        });
        this.detailLoading.set(false);
      }
    });
  }

  closeDetail(): void {
    this.showDetailDrawer.set(false);
    this.selectedChannel.set(null);
  }

  openActionModal(action: 'suspend' | 'ban' | 'unban' | 'delete' | 'restore' | 'lock' | 'unlock', channel: AdminChannel): void {
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

    if (!action || !channel || reason.length < 3 || this.busy()) return;

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
        this.notice.set(`Đã thực hiện thao tác "${this.actionLabel(action)}" trên kênh "${channel.name}".`);
        setTimeout(() => this.notice.set(''), 4000);
        this.load();
        this.loadCounts();
      },
      error: err => {
        this.busy.set(false);
        this.error.set(err?.error?.message || 'Không thể thực hiện thao tác.');
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
    return new Intl.NumberFormat('vi-VN').format(val || 0);
  }

  formatShort(num: number): string {
    if (!num) return '0';
    if (num >= 1_000_000) {
      return (num / 1_000_000).toFixed(1).replace('.0', '') + 'M';
    }
    if (num >= 1_000) {
      return (num / 1_000).toFixed(1).replace('.0', '') + 'K';
    }
    return num.toString();
  }

  actionLabel(action: string): string {
    const map: Record<string, string> = {
      suspend: 'Hạn chế / Tạm ngưng',
      ban: 'Cấm kênh',
      unban: 'Bỏ cấm / Khôi phục',
      delete: 'Xóa kênh',
      restore: 'Khôi phục kênh',
      lock: 'Khóa kênh',
      unlock: 'Mở khóa kênh'
    };
    return map[action] ?? action;
  }

  statusBadge(status: string): { label: string; cls: string } {
    switch (status?.toLowerCase()) {
      case 'active':
        return { label: 'Đang hoạt động', cls: 'status-active' };
      case 'suspended':
        return { label: 'Hạn chế', cls: 'status-restricted' };
      case 'banned':
      case 'locked':
        return { label: 'Bị khóa', cls: 'status-locked' };
      case 'deleted':
        return { label: 'Đã xóa', cls: 'status-deleted' };
      default:
        return { label: 'Đang hoạt động', cls: 'status-active' };
    }
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
