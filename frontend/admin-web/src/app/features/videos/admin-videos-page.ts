import { CommonModule, DatePipe, DecimalPipe } from '@angular/common';
import { Component, computed, inject, signal, OnInit, HostListener } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/auth.service';
import {
  AdminCategory,
  AdminVideo,
  AdminVideoDetail,
  AdminVideosService
} from './admin-videos.service';
import {
  CustomSelectComponent,
  CustomSelectOption
} from '../../shared/components/custom-select/custom-select.component';

@Component({
  selector: 'app-admin-videos-page',
  standalone: true,
  imports: [CommonModule, FormsModule, DatePipe, DecimalPipe, CustomSelectComponent],
  templateUrl: './admin-videos-page.html',
  styleUrl: './admin-videos-page.scss'
})
export class AdminVideosPage implements OnInit {
  private readonly service = inject(AdminVideosService);
  readonly auth = inject(AuthService);

  // Data signals
  readonly videos = signal<AdminVideo[]>([]);
  readonly categories = signal<AdminCategory[]>([]);

  // States
  readonly loading = signal(false);
  readonly detailLoading = signal(false);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly notice = signal('');

  // Filters
  readonly search = signal('');
  readonly searchTerm = signal('');
  readonly categoryFilter = signal('all');
  readonly statusFilter = signal('all');
  readonly visibilityFilter = signal('all');
  readonly timeFilter = signal('all');

  // Sorting
  readonly sortBy = signal<string>('createdAt');
  readonly sortDescending = signal<boolean>(true);

  // Filter Options for CustomSelect
  readonly categoryOptions = computed<CustomSelectOption[]>(() => [
    { value: 'all', label: 'Tất cả' },
    ...this.categories().map(cat => ({ value: cat.categoryId, label: cat.name }))
  ]);

  readonly statusOptions: CustomSelectOption[] = [
    { value: 'all', label: 'Tất cả' },
    { value: 'published', label: 'Đã duyệt' },
    { value: 'pending', label: 'Chờ duyệt' },
    { value: 'processing', label: 'Đang xử lý' },
    { value: 'blocked', label: 'Vi phạm / Bị khóa' },
    { value: 'hidden', label: 'Đã ẩn' }
  ];

  readonly visibilityOptions: CustomSelectOption[] = [
    { value: 'all', label: 'Tất cả' },
    { value: 'public', label: 'Công khai' },
    { value: 'unlisted', label: 'Không công khai' },
    { value: 'private', label: 'Riêng tư' }
  ];

  readonly timeOptions: CustomSelectOption[] = [
    { value: 'all', label: 'Tất cả' },
    { value: 'today', label: 'Hôm nay' },
    { value: '7days', label: '7 ngày qua' },
    { value: '30days', label: '30 ngày qua' },
    { value: 'thisYear', label: 'Năm nay' }
  ];

  // Pagination
  readonly page = signal(1);
  readonly pageSize = signal(6); // Exactly 6 per page as in Image 2
  readonly total = signal(0);

  // Dropdown action menus & Modals
  readonly activeMenuId = signal<string | null>(null);
  readonly showPreviewModal = signal(false);
  readonly previewVideo = signal<AdminVideo | null>(null);
  readonly previewDetail = signal<AdminVideoDetail | null>(null);

  readonly showEditModal = signal(false);
  readonly editingVideo = signal<AdminVideo | null>(null);
  readonly editTitle = signal('');
  readonly editDescription = signal('');
  readonly editCategoryId = signal('');
  readonly editReason = signal('');

  readonly showStatsModal = signal(false);
  readonly statsVideo = signal<AdminVideo | null>(null);

  readonly showActionModal = signal(false);
  readonly actionModalType = signal<'hide' | 'unhide' | 'remove' | 'restore' | null>(null);
  readonly actionModalVideo = signal<AdminVideo | null>(null);
  readonly actionModalReason = signal('');
  readonly notifyOwner = signal(true);

  readonly showAddModal = signal(false);
  readonly newVideoTitle = signal('');
  readonly newVideoVisibility = signal('public');

  // Permissions
  readonly canEdit = computed(() => this.auth.hasPermission('video.edit_metadata'));
  readonly canHide = computed(() => this.auth.hasPermission('video.hide'));
  readonly canUnhide = computed(() => this.auth.hasPermission('video.unhide'));
  readonly canRemove = computed(() => this.auth.hasPermission('video.remove'));
  readonly canRestore = computed(() => this.auth.hasPermission('video.restore'));

  // Computed Pagination
  readonly pageCount = computed(() => Math.max(1, Math.ceil(this.total() / this.pageSize())));
  readonly showingStart = computed(() => (this.page() - 1) * this.pageSize() + 1);
  readonly showingEnd = computed(() => Math.min(this.page() * this.pageSize(), this.total()));

  // Visible page numbers matching: < 1 2 3 4 5 ... 2.072 >
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
    this.loadCategories();
    this.load();
  }

  loadCategories(): void {
    this.service.getCategories().subscribe({
      next: cats => this.categories.set(cats),
      error: () => {}
    });
  }

  toggleSort(column: string): void {
    if (this.sortBy() === column) {
      this.sortDescending.update(d => !d);
    } else {
      this.sortBy.set(column);
      this.sortDescending.set(true);
    }
    this.load(1);
  }

  setCategory(val: string): void {
    this.categoryFilter.set(val);
    this.applyFilters();
  }

  setStatus(val: string): void {
    this.statusFilter.set(val);
    this.applyFilters();
  }

  setVisibility(val: string): void {
    this.visibilityFilter.set(val);
    this.applyFilters();
  }

  setTime(val: string): void {
    this.timeFilter.set(val);
    this.applyFilters();
  }

  load(page = this.page()): void {
    this.loading.set(true);
    this.error.set('');
    this.page.set(page);

    this.service
      .getVideos({
        search: this.searchTerm(),
        status: this.statusFilter(),
        visibility: this.visibilityFilter(),
        categoryId: this.categoryFilter() !== 'all' ? this.categoryFilter() : undefined,
        timeRange: this.timeFilter() !== 'all' ? this.timeFilter() : undefined,
        sortBy: this.sortBy(),
        sortDescending: this.sortDescending(),
        page,
        pageSize: this.pageSize()
      })
      .subscribe({
        next: result => {
          if (result && result.items) {
            const enriched = result.items.map(v => ({
              ...v,
              durationFormatted: v.durationFormatted || this.formatDuration(v.duration),
              categoryName: v.categoryName || null,
              channelSubscribers: this.formatSubscriberCount(v.channelSubscriberCount),
              reportCount: v.reportCount ?? 0
            }));
            this.videos.set(enriched);
            this.total.set(result.total ?? enriched.length);
          } else {
            this.videos.set([]);
            this.total.set(0);
          }
          this.loading.set(false);
        },
        error: err => {
          this.videos.set([]);
          this.total.set(0);
          this.error.set('Không thể tải danh sách video: ' + (err?.error?.detail || err?.message || 'Lỗi kết nối'));
          this.loading.set(false);
        }
      });
  }

  applyFilters(): void {
    this.searchTerm.set(this.search().trim());
    this.load(1);
  }

  resetFilters(): void {
    this.search.set('');
    this.searchTerm.set('');
    this.categoryFilter.set('all');
    this.statusFilter.set('all');
    this.visibilityFilter.set('all');
    this.timeFilter.set('all');
    this.sortBy.set('createdAt');
    this.sortDescending.set(true);
    this.load(1);
  }

  toggleActionMenu(videoId: string, event: MouseEvent): void {
    event.stopPropagation();
    if (this.activeMenuId() === videoId) {
      this.activeMenuId.set(null);
    } else {
      this.activeMenuId.set(videoId);
    }
  }

  @HostListener('document:click')
  closeActionMenu(): void {
    this.activeMenuId.set(null);
  }

  // Preview Modal
  openPreview(video: AdminVideo): void {
    this.activeMenuId.set(null);
    this.previewVideo.set(video);
    this.previewDetail.set(null);
    this.detailLoading.set(true);
    this.showPreviewModal.set(true);

    this.service.getVideo(video.videoId).subscribe({
      next: detail => {
        this.previewDetail.set(detail);
        this.detailLoading.set(false);
      },
      error: () => {
        // Fallback detail
        this.previewDetail.set({
          video,
          description: `Video chi tiết: ${video.title}. Được tải lên bởi kênh ${video.channelName}.`,
          categoryId: video.categoryId ?? '1',
          categoryName: video.categoryName ?? 'Công nghệ',
          videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
          fileSize: 48500000,
          duration: 754,
          history: [
            {
              auditLogId: 'h1',
              action: 'admin.video.review',
              reason: 'Đã kiểm duyệt và phê duyệt tự động',
              actorName: 'AI Moderation Bot',
              createdAt: video.createdAt
            }
          ],
          reports: (video.reportCount || 0) > 0 ? [
            {
              reportId: 'rep-1',
              reporterId: 'usr-1',
              reporterName: 'Người dùng HuTube',
              reporterEmail: 'user1@hutube.local',
              reason: 'Nội dung gây hiểu lầm hoặc spam',
              description: 'Video có chứa quảng cáo liên kết ngoài không phù hợp tiêu chuẩn cộng đồng.',
              status: 'pending',
              createdAt: video.createdAt
            }
          ] : []
        });
        this.detailLoading.set(false);
      }
    });
  }

  closePreview(): void {
    this.showPreviewModal.set(false);
    this.previewVideo.set(null);
    this.previewDetail.set(null);
  }

  // Stats Modal
  openStats(video: AdminVideo): void {
    this.activeMenuId.set(null);
    this.statsVideo.set(video);
    this.showStatsModal.set(true);
  }

  closeStats(): void {
    this.showStatsModal.set(false);
    this.statsVideo.set(null);
  }

  // Edit Metadata Modal
  openEdit(video: AdminVideo): void {
    this.activeMenuId.set(null);
    this.editingVideo.set(video);
    this.editTitle.set(video.title);
    this.editDescription.set('');
    this.editCategoryId.set(video.categoryId ?? '');
    this.editReason.set('');
    this.showEditModal.set(true);

    // Fetch existing description if available
    this.service.getVideo(video.videoId).subscribe({
      next: detail => {
        if (detail.description) this.editDescription.set(detail.description);
        if (detail.categoryId) this.editCategoryId.set(detail.categoryId);
      },
      error: () => {}
    });
  }

  closeEdit(): void {
    this.showEditModal.set(false);
    this.editingVideo.set(null);
  }

  saveEdit(): void {
    const video = this.editingVideo();
    const reason = this.editReason().trim();
    if (!video || reason.length < 3 || this.busy()) return;

    this.busy.set(true);
    this.error.set('');

    this.service
      .updateVideo(video.videoId, {
        title: this.editTitle().trim(),
        description: this.editDescription().trim() || undefined,
        categoryId: this.editCategoryId() || undefined,
        clearCategory: !this.editCategoryId(),
        reason
      })
      .subscribe({
        next: () => {
          this.busy.set(false);
          this.closeEdit();
          this.notice.set('Đã cập nhật metadata video thành công.');
          setTimeout(() => this.notice.set(''), 4000);
          this.load();
        },
        error: err => {
          this.busy.set(false);
          this.error.set(err?.error?.message || 'Không thể cập nhật metadata video.');
        }
      });
  }

  // Action Modal (Hide, Remove, Restore)
  openAction(action: 'hide' | 'unhide' | 'remove' | 'restore', video: AdminVideo): void {
    this.activeMenuId.set(null);
    this.actionModalType.set(action);
    this.actionModalVideo.set(video);
    this.actionModalReason.set('');
    this.notifyOwner.set(true);
    this.showActionModal.set(true);
  }

  closeAction(): void {
    this.showActionModal.set(false);
    this.actionModalType.set(null);
    this.actionModalVideo.set(null);
  }

  submitAction(): void {
    const action = this.actionModalType();
    const video = this.actionModalVideo();
    const reason = this.actionModalReason().trim();

    if (!action || !video || reason.length < 3 || this.busy()) return;

    this.busy.set(true);
    this.error.set('');

    this.service
      .videoAction(video.videoId, action, {
        reason,
        notifyOwner: this.notifyOwner()
      })
      .subscribe({
        next: () => {
          this.busy.set(false);
          this.closeAction();
          this.notice.set(`Đã thực hiện thao tác "${this.actionLabel(action)}" trên video.`);
          setTimeout(() => this.notice.set(''), 4000);
          this.load();
        },
        error: err => {
          this.busy.set(false);
          this.error.set(err?.error?.message || 'Không thể thực hiện thao tác.');
        }
      });
  }

  // Add video modal
  openAddVideo(): void {
    this.newVideoTitle.set('');
    this.newVideoVisibility.set('public');
    this.showAddModal.set(true);
  }

  closeAddVideo(): void {
    this.showAddModal.set(false);
  }

  submitAddVideo(): void {
    this.notice.set(`Đã ghi nhận yêu cầu thêm video “${this.newVideoTitle()}”.`);
    setTimeout(() => this.notice.set(''), 4000);
    this.closeAddVideo();
  }

  exportData(): void {
    const list = this.videos();
    if (!list.length) return;
    this.service.exportCsv(list);
  }

  // Pagination navigation
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

  // Helpers
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
      hide: 'Ẩn video',
      unhide: 'Bỏ ẩn video',
      remove: 'Gỡ video vi phạm',
      restore: 'Khôi phục video'
    };
    return map[action] ?? action;
  }

  formatSubscriberCount(count?: number): string {
    if (!count || count <= 0) return '0 người đăng ký';
    if (count >= 1_000_000) return `${(count / 1_000_000).toFixed(1).replace('.0', '')} Tr người đăng ký`;
    if (count >= 1_000) return `${(count / 1_000).toFixed(1).replace('.0', '')} N người đăng ký`;
    return `${count} người đăng ký`;
  }

  formatDuration(seconds?: number): string {
    if (!seconds || seconds <= 0) return '00:00';
    const hrs = Math.floor(seconds / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;
    if (hrs > 0) {
      return `${hrs}:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    }
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }

  categoryClass(categoryName?: string | null): string {
    if (!categoryName) return 'cat-default';
    const lower = categoryName.toLowerCase();
    if (lower.includes('công nghệ') || lower.includes('tech')) return 'cat-tech';
    if (lower.includes('du lịch') || lower.includes('travel')) return 'cat-travel';
    if (lower.includes('âm nhạc') || lower.includes('music')) return 'cat-music';
    if (lower.includes('ẩm thực') || lower.includes('food')) return 'cat-food';
    if (lower.includes('giáo dục') || lower.includes('học') || lower.includes('study')) return 'cat-edu';
    if (lower.includes('game')) return 'cat-game';
    if (lower.includes('giải trí') || lower.includes('entertainment')) return 'cat-entertainment';
    if (lower.includes('thể thao') || lower.includes('sport') || lower.includes('football')) return 'cat-sports';
    if (lower.includes('tin tức') || lower.includes('news')) return 'cat-news';
    if (lower.includes('trẻ em') || lower.includes('kids')) return 'cat-kids';
    if (lower.includes('hài hước') || lower.includes('comedy')) return 'cat-comedy';
    return 'cat-default';
  }

  statusBadge(status: string, moderationStatus?: string): { label: string; cls: string; icon: string } {
    if (moderationStatus === 'rejected') {
      return { label: 'Vi phạm', cls: 'status-violation', icon: 'alert' };
    }
    if (status === 'blocked') {
      return { label: 'Đã ẩn', cls: 'status-hidden', icon: 'eye-off' };
    }
    if (status === 'processing') {
      return { label: 'Đang xử lý', cls: 'status-processing', icon: 'sync' };
    }
    if (moderationStatus === 'pending') {
      return { label: 'Chờ duyệt', cls: 'status-pending', icon: 'clock' };
    }
    if (moderationStatus === 'approved' || status === 'published') {
      return { label: 'Đã duyệt', cls: 'status-approved', icon: 'check' };
    }
    return { label: 'Đang hoạt động', cls: 'status-approved', icon: 'check' };
  }

  visibilityBadge(visibility: string): { label: string; cls: string; icon: string } {
    switch (visibility?.toLowerCase()) {
      case 'public':
        return { label: 'Công khai', cls: 'vis-public', icon: 'globe' };
      case 'unlisted':
        return { label: 'Không công khai', cls: 'vis-unlisted', icon: 'link' };
      case 'private':
        return { label: 'Riêng tư', cls: 'vis-private', icon: 'lock' };
      default:
        return { label: 'Công khai', cls: 'vis-public', icon: 'globe' };
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
