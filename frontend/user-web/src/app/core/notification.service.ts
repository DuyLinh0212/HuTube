import { HttpClient } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import * as signalR from '@microsoft/signalr';
import { Router } from '@angular/router';
import { AuthService } from './auth.service';
import { RuntimeConfig } from './runtime-config';

export interface AppNotification { notificationId: string; type: string; title: string; content: string; actionUrl: string | null; isRead: boolean; createdAt: string; }
interface NotificationPage { items: AppNotification[]; page: number; pageSize: number; total: number; unreadCount: number; hasMore: boolean; }

@Injectable({ providedIn: 'root' })
export class NotificationService {
  private readonly http = inject(HttpClient);
  private readonly auth = inject(AuthService);
  private readonly config = inject(RuntimeConfig);
  private readonly router = inject(Router);
  private connection?: signalR.HubConnection;
  private revocationPoll?: ReturnType<typeof setInterval>;
  private notificationPoll?: ReturnType<typeof setInterval>;
  private notificationIds = new Set<string>();
  private notificationPollInitialized = false;
  readonly items = signal<AppNotification[]>([]);
  readonly unread = signal(0);
  readonly hasMore = signal(false);
  readonly invitationVersion = signal(0);
  readonly invitationToast = signal<string | null>(null);
  readonly loading = signal(false);
  private page = 0;
  private invitationToastTimer?: ReturnType<typeof setTimeout>;

  async connect() {
    if (!this.auth.accessToken() || this.connection) return;
    this.startRevocationWatchdog();
    this.startNotificationPolling();
    this.connection = new signalR.HubConnectionBuilder()
      .withUrl(this.config.apiBaseUrl.replace(/\/api\/v1$/, '') + '/hubs/notifications', { accessTokenFactory: () => this.auth.accessToken() ?? '' })
      .withAutomaticReconnect()
      .build();
    this.connection.on('NotificationReceived', (item: AppNotification) => {
      this.items.update(items => [item, ...items.filter(existing => existing.notificationId !== item.notificationId)]);
      if (item.type === 'channel_invitation') this.showInvitationToast(item.content);
    });
    this.connection.on('UnreadCountChanged', (count: number) => this.unread.set(count));
    this.connection.on('InvitationReceived', (event: { channelName?: string }) => {
      this.invitationVersion.update(version => version + 1);
      this.showInvitationToast(`Bạn có lời mời tham gia kênh${event?.channelName ? ` ${event.channelName}` : ''}.`);
    });
    this.connection.on('SessionRevoked', (event: { allSessions?: boolean; exceptSessionId?: string }) => {
      if (!event?.allSessions && event?.exceptSessionId === this.auth.currentSessionId()) return;
      this.auth.clear();
      const connection = this.connection;
      this.connection = undefined;
      void connection?.stop();
      void this.router.navigate(['/login'], { queryParams: { reason: 'session-revoked' } });
    });
    try {
      await this.connection.start();
      this.loadInitial();
    } catch {
      this.connection = undefined;
    }
  }

  private startRevocationWatchdog() {
    if (this.revocationPoll) return;
    this.revocationPoll = setInterval(() => {
      if (!this.auth.accessToken()) return;
      this.auth.me().subscribe({ error: () => undefined });
    }, 3000);
  }

  private startNotificationPolling() {
    if (this.notificationPoll) return;
    this.pollLatestNotifications();
    this.notificationPoll = setInterval(() => this.pollLatestNotifications(), 3000);
  }

  private pollLatestNotifications() {
    if (!this.auth.accessToken() || this.loading()) return;
    this.http.get<NotificationPage>(`${this.config.apiBaseUrl}/notifications`, { params: { page: 1, pageSize: 5 } }).subscribe({
      next: value => {
        const fresh = value.items.filter(item => !this.notificationIds.has(item.notificationId));
        value.items.forEach(item => this.notificationIds.add(item.notificationId));
        this.items.update(items => {
          const merged = [...value.items, ...items];
          return merged.filter((item, index, all) => all.findIndex(candidate => candidate.notificationId === item.notificationId) === index);
        });
        this.unread.set(value.unreadCount);
        if (this.notificationPollInitialized) {
          const invitation = fresh.find(item => item.type === 'channel_invitation');
          if (invitation) this.showInvitationToast(invitation.content);
        }
        this.notificationPollInitialized = true;
      },
      error: () => undefined
    });
  }

  private showInvitationToast(message: string) {
    this.invitationToast.set(message);
    if (this.invitationToastTimer) clearTimeout(this.invitationToastTimer);
    this.invitationToastTimer = setTimeout(() => this.invitationToast.set(null), 6000);
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
          value.items.forEach(item => this.notificationIds.add(item.notificationId));
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
