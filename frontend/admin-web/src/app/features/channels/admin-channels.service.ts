import { csvCell } from '../../core/csv';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, forkJoin, map, of, catchError } from 'rxjs';
import { I18nService } from '../../core/i18n.service';
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

export interface AdminChannel {
  channelId: string;
  name: string;
  handle: string;
  avatarUrl?: string | null;
  ownerUserId: string;
  ownerName: string;
  ownerEmail: string;
  ownerAvatarUrl?: string | null;
  status: string; // 'active' | 'suspended' | 'banned' | 'deleted'
  statusReason?: string | null;
  createdAt: string;
  videoCount: number;
  subscriberCount: number;
  viewCount?: number;
  activeStrikeCount: number;
}

export interface AdminAuditItem {
  auditLogId: string;
  action: string;
  reason: string | null;
  actorName: string | null;
  createdAt: string;
}

export interface AdminVideoSnippet {
  videoId: string;
  title: string;
  thumbnailUrl: string | null;
  status: string;
  views: number;
}

export interface AdminChannelDetail {
  channel: AdminChannel;
  description: string | null;
  contactEmail: string | null;
  avatarUrl: string | null;
  bannerUrl: string | null;
  watermarkUrl: string | null;
  videos: AdminVideoSnippet[];
  history: AdminAuditItem[];
}

export interface ChannelCounts {
  all: number;
  active: number;
  restricted: number;
  banned: number;
}

@Injectable({ providedIn: 'root' })
export class AdminChannelsService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);
  private readonly i18n = inject(I18nService);

  private get base() {
    return `${this.config.apiBaseUrl}/admin`;
  }

  getChannels(options: {
    search?: string;
    status?: string;
    sortBy?: string;
    sortDescending?: boolean;
    page?: number;
    pageSize?: number;
  }): Observable<AdminPage<AdminChannel>> {
    let params = new HttpParams()
      .set('page', options.page ?? 1)
      .set('pageSize', options.pageSize ?? 8);

    if (options.search && options.search.trim()) {
      params = params.set('search', options.search.trim());
    }
    if (options.status && options.status !== 'all') {
      params = params.set('status', options.status);
    }
    if (options.sortBy) {
      params = params.set('sortBy', options.sortBy);
    }
    if (options.sortDescending !== undefined) {
      params = params.set('sortDescending', options.sortDescending.toString());
    }

    return this.http.get<AdminPage<AdminChannel>>(`${this.base}/channels`, { params });
  }

  getChannelDetail(id: string): Observable<AdminChannelDetail> {
    return this.http.get<AdminChannelDetail>(`${this.base}/channels/${id}`);
  }

  getChannelCounts(): Observable<ChannelCounts> {
    // Perform parallel calls to fetch actual counts per status
    const all$ = this.http
      .get<AdminPage<AdminChannel>>(`${this.base}/channels`, {
        params: new HttpParams().set('page', 1).set('pageSize', 1)
      })
      .pipe(
        map(res => res.total)
      );

    const active$ = this.http
      .get<AdminPage<AdminChannel>>(`${this.base}/channels`, {
        params: new HttpParams().set('page', 1).set('pageSize', 1).set('status', 'active')
      })
      .pipe(
        map(res => res.total)
      );

    const suspended$ = this.http
      .get<AdminPage<AdminChannel>>(`${this.base}/channels`, {
        params: new HttpParams().set('page', 1).set('pageSize', 1).set('status', 'suspended')
      })
      .pipe(
        map(res => res.total)
      );

    const banned$ = this.http
      .get<AdminPage<AdminChannel>>(`${this.base}/channels`, {
        params: new HttpParams().set('page', 1).set('pageSize', 1).set('status', 'banned')
      })
      .pipe(
        map(res => res.total)
      );

    return forkJoin({
      all: all$,
      active: active$,
      restricted: suspended$,
      banned: banned$
    });
  }

  channelAction(
    id: string,
    action: 'suspend' | 'ban' | 'unban' | 'restore',
    request: AdminContentAction
  ): Observable<void> {
    return this.http.post<void>(`${this.base}/channels/${id}/${action}`, request);
  }

  lockChannel(id: string, reason: string): Observable<void> {
    return this.http.post<void>(`${this.base}/channels/${id}/lock`, { reason });
  }

  unlockChannel(id: string, reason: string): Observable<void> {
    return this.http.post<void>(`${this.base}/channels/${id}/unlock`, { reason });
  }

  deleteChannel(id: string, request: AdminContentAction): Observable<void> {
    return this.http.delete<void>(`${this.base}/channels/${id}`, { body: request });
  }

  exportCsv(channels: AdminChannel[], filename?: string): void {
    const headers = [
      this.i18n.t('channels.csv.id'),
      this.i18n.t('channels.csv.name'),
      this.i18n.t('channels.csv.handle'),
      this.i18n.t('channels.csv.owner'),
      this.i18n.t('channels.csv.ownerEmail'),
      this.i18n.t('channels.csv.videos'),
      this.i18n.t('channels.csv.subscribers'),
      this.i18n.t('channels.csv.views'),
      this.i18n.t('channels.csv.status'),
      this.i18n.t('channels.csv.createdAt')
    ];

    const rows = channels.map(c => [
      c.channelId,
      c.name,
      `@${c.handle}`,
      c.ownerName,
      c.ownerEmail,
      c.videoCount,
      c.subscriberCount,
      c.viewCount ?? 0,
      c.status,
      c.createdAt
    ]);

    const csvContent = '\uFEFF' + [headers.map(csvCell).join(','), ...rows.map(r => r.map(csvCell).join(','))].join('\r\n');
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.setAttribute('href', url);
    link.setAttribute('download', filename ?? this.i18n.t('channels.csv.filename'));
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }
}
