import { HttpClient } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import * as signalR from '@microsoft/signalr';
import { AuthService } from './auth.service';
import { RuntimeConfig } from './runtime-config';

export interface AppNotification { notificationId: string; type: string; title: string; content: string; actionUrl: string | null; isRead: boolean; createdAt: string; }
interface NotificationPage { items: AppNotification[]; page: number; pageSize: number; total: number; unreadCount: number; hasMore: boolean; }

@Injectable({ providedIn: 'root' })
export class NotificationService {
  private readonly http = inject(HttpClient);
  private readonly auth = inject(AuthService);
  private readonly config = inject(RuntimeConfig);
  private connection?: signalR.HubConnection;
  readonly items = signal<AppNotification[]>([]);
  readonly unread = signal(0);
  readonly hasMore = signal(false);
  readonly loading = signal(false);
  private page = 0;

  async connect() {
    if (!this.auth.accessToken() || this.connection) return;
    this.connection = new signalR.HubConnectionBuilder()
      .withUrl(this.config.apiBaseUrl.replace(/\/api\/v1$/, '') + '/hubs/notifications', { accessTokenFactory: () => this.auth.accessToken() ?? '' })
      .withAutomaticReconnect()
      .build();
    this.connection.on('NotificationReceived', (item: AppNotification) => this.items.update(items => [item, ...items.filter(existing => existing.notificationId !== item.notificationId)]));
    this.connection.on('UnreadCountChanged', (count: number) => this.unread.set(count));
    try {
      await this.connection.start();
      this.loadInitial();
    } catch {
      this.connection = undefined;
    }
  }

  loadInitial() { this.page = 0; this.items.set([]); return this.loadMore(); }
  loadMore() {
    if (this.loading()) return;
    this.loading.set(true);
    this.http.get<NotificationPage>(`${this.config.apiBaseUrl}/notifications`, { params: { page: this.page + 1, pageSize: 5 } }).subscribe({
      next: value => {
        this.page = value.page;
        this.items.update(items => {
          const merged = [...items, ...value.items];
          return merged.filter((item, index, all) => all.findIndex(candidate => candidate.notificationId === item.notificationId) === index);
        });
        this.unread.set(value.unreadCount);
        this.hasMore.set(value.hasMore);
        this.loading.set(false);
      },
      error: () => this.loading.set(false)
    });
  }
  read(item: AppNotification) { if (!item.isRead) this.http.patch<void>(`${this.config.apiBaseUrl}/notifications/${item.notificationId}/read`, {}).subscribe(() => { item.isRead = true; this.items.update(items => [...items]); }); }
  readAll() { this.http.post<void>(`${this.config.apiBaseUrl}/notifications/read-all`, {}).subscribe(() => { this.items.update(items => items.map(item => ({ ...item, isRead: true }))); this.unread.set(0); }); }
}
