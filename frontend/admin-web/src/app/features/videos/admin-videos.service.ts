import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, catchError, map, of } from 'rxjs';
import { RuntimeConfig } from '../../core/runtime-config';

export interface AdminPage<T> {
  items: T[];
  page: number;
  pageSize: number;
  total: number;
}

export interface AdminContentAction {
  reason: string;
  notifyOwner?: boolean;
}

export interface AdminVideo {
  videoId: string;
  channelId: string;
  channelName: string;
  channelHandle: string;
  channelAvatarUrl?: string | null;
  channelSubscriberCount?: number;
  channelSubscribers?: string;
  title: string;
  thumbnailUrl: string | null;
  duration?: number;
  durationFormatted?: string;
  categoryId?: string | null;
  categoryName?: string | null;
  visibility: 'public' | 'unlisted' | 'private' | string;
  status: string; // 'published' | 'processing' | 'blocked' | 'deleted' | 'failed'
  moderationStatus: string; // 'approved' | 'pending' | 'rejected' | 'not_submitted'
  views: number;
  reportCount?: number;
  ageRestricted: boolean;
  createdAt: string;
  publishedAt: string | null;
}

export interface AdminAuditItem {
  auditLogId: string;
  action: string;
  reason: string | null;
  actorName: string | null;
  createdAt: string;
}

export interface AdminVideoReportSummary {
  reportId: string;
  reporterId: string;
  reporterName: string;
  reporterEmail: string;
  reason: string;
  description: string | null;
  status: string;
  createdAt: string;
}

export interface AdminVideoDetail {
  video: AdminVideo;
  description: string | null;
  categoryId: string | null;
  categoryName: string | null;
  videoUrl: string;
  fileSize: number;
  duration: number;
  history: AdminAuditItem[];
  reports: AdminVideoReportSummary[];
}

export interface AdminCategory {
  categoryId: string;
  name: string;
  slug: string;
  description: string | null;
}

export interface UpdateAdminVideo {
  title?: string;
  description?: string;
  categoryId?: string;
  clearCategory: boolean;
  reason: string;
}

export interface WeeklyUploadDay {
  day: string; // 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'
  label: string;
  count: number;
  heightPercent: number;
}

export interface WeeklyUploadStats {
  total: number;
  growthPercentage: number;
  days: WeeklyUploadDay[];
}

export interface StorageStats {
  percentage: number;
  usedFormatted: string;
  totalFormatted: string;
  weeklyChangeFormatted: string;
  totalVideosFormatted: string;
}

export interface AdminVideoStatisticsResponse {
  weekly: WeeklyUploadStats;
  storage: StorageStats;
}

@Injectable({ providedIn: 'root' })
export class AdminVideosService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);

  private get base() {
    return `${this.config.apiBaseUrl}/admin`;
  }

  getVideos(options: {
    search?: string;
    status?: string;
    visibility?: string;
    categoryId?: string;
    channelId?: string;
    timeRange?: string;
    fromDate?: string;
    toDate?: string;
    sortBy?: string;
    sortDescending?: boolean;
    page?: number;
    pageSize?: number;
  }): Observable<AdminPage<AdminVideo>> {
    let params = new HttpParams()
      .set('page', options.page ?? 1)
      .set('pageSize', options.pageSize ?? 6);

    if (options.search && options.search.trim()) {
      params = params.set('search', options.search.trim());
    }
    if (options.status && options.status !== 'all') {
      params = params.set('status', options.status);
    }
    if (options.visibility && options.visibility !== 'all') {
      params = params.set('visibility', options.visibility);
    }
    if (options.categoryId && options.categoryId !== 'all') {
      params = params.set('categoryId', options.categoryId);
    }
    if (options.channelId) {
      params = params.set('channelId', options.channelId);
    }
    if (options.timeRange && options.timeRange !== 'all') {
      params = params.set('timeRange', options.timeRange);
    }
    if (options.fromDate) {
      params = params.set('fromDate', options.fromDate);
    }
    if (options.toDate) {
      params = params.set('toDate', options.toDate);
    }
    if (options.sortBy) {
      params = params.set('sortBy', options.sortBy);
    }
    if (options.sortDescending !== undefined) {
      params = params.set('sortDescending', options.sortDescending.toString());
    }

    return this.http.get<AdminPage<AdminVideo>>(`${this.base}/videos`, { params });
  }

  getVideo(id: string): Observable<AdminVideoDetail> {
    return this.http.get<AdminVideoDetail>(`${this.base}/videos/${id}`);
  }

  updateVideo(id: string, request: UpdateAdminVideo): Observable<void> {
    return this.http.put<void>(`${this.base}/videos/${id}/metadata`, request);
  }

  videoAction(
    id: string,
    action: 'hide' | 'unhide' | 'remove' | 'restore',
    request: AdminContentAction
  ): Observable<void> {
    return this.http.post<void>(`${this.base}/videos/${id}/${action}`, request);
  }

  getCategories(): Observable<AdminCategory[]> {
    return this.http.get<AdminCategory[]>(`${this.config.apiBaseUrl}/categories`).pipe(
      catchError(() =>
        of([
          { categoryId: '1', name: 'Công nghệ', slug: 'cong-nghe', description: null },
          { categoryId: '2', name: 'Du lịch', slug: 'du-lich', description: null },
          { categoryId: '3', name: 'Âm nhạc', slug: 'am-nhac', description: null },
          { categoryId: '4', name: 'Ẩm thực', slug: 'am-thuc', description: null },
          { categoryId: '5', name: 'Giáo dục', slug: 'giao-duc', description: null },
          { categoryId: '6', name: 'Giải trí', slug: 'giai-tri', description: null }
        ])
      )
    );
  }

  getVideoStatistics(): Observable<AdminVideoStatisticsResponse> {
    return this.http.get<AdminVideoStatisticsResponse>(`${this.base}/videos/statistics`).pipe(
      catchError(() =>
        of({
          weekly: {
            total: 0,
            growthPercentage: 0,
            days: [
              { day: 'T2', label: 'Thứ 2', count: 0, heightPercent: 10 },
              { day: 'T3', label: 'Thứ 3', count: 0, heightPercent: 10 },
              { day: 'T4', label: 'Thứ 4', count: 0, heightPercent: 10 },
              { day: 'T5', label: 'Thứ 5', count: 0, heightPercent: 10 },
              { day: 'T6', label: 'Thứ 6', count: 0, heightPercent: 10 },
              { day: 'T7', label: 'Thứ 7', count: 0, heightPercent: 10 },
              { day: 'CN', label: 'Chủ nhật', count: 0, heightPercent: 10 }
            ]
          },
          storage: {
            percentage: 0,
            usedFormatted: '0 MB',
            totalFormatted: '100 GB',
            weeklyChangeFormatted: '0 MB',
            totalVideosFormatted: '0'
          }
        })
      )
    );
  }

  getWeeklyUploadStats(range: '7days' | '30days' = '7days'): Observable<WeeklyUploadStats> {
    return this.getVideoStatistics().pipe(map(s => s.weekly));
  }

  getStorageStats(): Observable<StorageStats> {
    return this.getVideoStatistics().pipe(map(s => s.storage));
  }

  exportCsv(videos: AdminVideo[], filename = 'danh-sach-video.csv'): void {
    const headers = [
      'ID Video',
      'Tiêu Đề',
      'Kênh',
      'Handle Kênh',
      'Danh Mục',
      'Trạng Thái',
      'Quyền Riêng Tư',
      'Lượt Xem',
      'Số Báo Cáo',
      'Ngày Tải Lên'
    ];

    const rows = videos.map(v => [
      `"${v.videoId}"`,
      `"${v.title.replace(/"/g, '""')}"`,
      `"${v.channelName.replace(/"/g, '""')}"`,
      `"@${v.channelHandle}"`,
      `"${v.categoryName ?? 'Chưa phân loại'}"`,
      `"${v.status}"`,
      `"${v.visibility}"`,
      v.views,
      v.reportCount ?? 0,
      `"${v.createdAt}"`
    ]);

    const csvContent = '\uFEFF' + [headers.join(','), ...rows.map(r => r.join(','))].join('\r\n');
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.setAttribute('href', url);
    link.setAttribute('download', filename);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }
}
