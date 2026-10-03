import { Subject, takeUntil } from 'rxjs';
import { HttpClient } from '@angular/common/http';
import { Injectable, effect, inject, signal } from '@angular/core';
import * as signalR from '@microsoft/signalr';
import { Router } from '@angular/router';
import { AuthService } from './auth.service';
import { RuntimeConfig } from './runtime-config';
import { I18nService } from './i18n.service';

export interface AppNotification { notificationId: string; type: string; title: string; content: string; actionUrl: string | null; isRead: boolean; createdAt: string; }
interface NotificationPage { items: AppNotification[]; page: number; pageSize: number; total: number; unreadCount: number; hasMore: boolean; }

@Injectable({ providedIn: 'root' })
export class NotificationService {
  private readonly http = inject(HttpClient);
  private readonly auth = inject(AuthService);
  private readonly config = inject(RuntimeConfig);
  private readonly router = inject(Router);
  private readonly i18n = inject(I18nService);
  private generation = 0;
  private identity = '';
  private identityChanged = new Subject<void>();
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

  constructor() {
    effect(() => {
      const identity = this.auth.user() && this.auth.accessToken()
        ? this.auth.user()!.userId + ':' + this.auth.currentSessionId() : '';
      if (identity === this.identity) return;
      this.identity = identity;
      this.reset();
      if (identity) void this.connect();
    });
  }

  private reset() {
    ++this.generation;
    this.identityChanged.next();
    const old = this.connection; this.connection = undefined;
    void old?.stop();
    if (this.revocationPoll) clearInterval(this.revocationPoll);
    if (this.notificationPoll) clearInterval(this.notificationPoll);
    if (this.invitationToastTimer) clearTimeout(this.invitationToastTimer);
    this.revocationPoll = undefined; this.notificationPoll = undefined;
    this.notificationIds.clear(); this.notificationPollInitialized = false;
    this.items.set([]); this.unread.set(0); this.hasMore.set(false);
    this.loading.set(false); this.invitationToast.set(null); this.page = 0;
  }

  async connect() {
    if (!this.auth.accessToken() || this.connection) return;
    const generation = this.generation;
    this.startRevocationWatchdog();
    this.startNotificationPolling();
    this.connection = new signalR.HubConnectionBuilder()
      .withUrl(this.config.apiBaseUrl.replace(/\/api\/v1$/, '') + '/hubs/notifications', { accessTokenFactory: () => this.auth.accessToken() ?? '' })
      .withAutomaticReconnect()
      .build();
    this.connection.on('NotificationReceived', (item: AppNotification) => {
      if (generation !== this.generation) return;
      this.items.update(items => [item, ...items.filter(existing => existing.notificationId !== item.notificationId)]);
      if (item.type === 'channel_invitation') this.showInvitationToast(item.content);
    });
    this.connection.on('UnreadCountChanged', (count: number) => { if (generation === this.generation) this.unread.set(count); });
    this.connection.on('InvitationReceived', (event: { channelName?: string }) => {
      if (generation !== this.generation) return;
      this.invitationVersion.update(version => version + 1);
      this.showInvitationToast(this.i18n.t('notification.channelInviteToast', { channel: event?.channelName ? ` ${event.channelName}` : '' }));
    });
    this.connection.on('SessionRevoked', (event: { allSessions?: boolean; exceptSessionId?: string }) => {
      if (generation !== this.generation) return;
      if (!event?.allSessions && event?.exceptSessionId === this.auth.currentSessionId()) return;
      this.auth.clear();
      const connection = this.connection;
      this.connection = undefined;
      void connection?.stop();
      void this.router.navigate(['/login'], { queryParams: { reason: 'session-revoked' } });
    });
    const connection = this.connection;
    try {
      await connection.start();
      if (generation !== this.generation) { await connection.stop(); return; }
      this.loadInitial();
    } catch {
      if (generation === this.generation) this.connection = undefined;
    }
  }

  private startRevocationWatchdog() {
    if (this.revocationPoll) return;
    this.revocationPoll = setInterval(() => {
      if (!this.auth.accessToken()) return;
      this.auth.me().pipe(takeUntil(this.identityChanged)).subscribe({ error: () => undefined });
    }, 3000);
  }

  private startNotificationPolling() {
    if (this.notificationPoll) return;
    this.pollLatestNotifications();
    this.notificationPoll = setInterval(() => this.pollLatestNotifications(), 3000);
  }

  private pollLatestNotifications() {
    if (!this.auth.accessToken() || this.loading()) return;
    const generation = this.generation;
    this.http.get<NotificationPage>(`${this.config.apiBaseUrl}/notifications`, { params: { page: 1, pageSize: 5 } }).pipe(takeUntil(this.identityChanged)).subscribe({
      next: value => {
        if (generation !== this.generation) return;
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
    const generation = this.generation;
    if (this.loading()) return;
    this.loading.set(true);
    this.http.get<NotificationPage>(`${this.config.apiBaseUrl}/notifications`, { params: { page: this.page + 1, pageSize: 5 } }).pipe(takeUntil(this.identityChanged)).subscribe({
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
      error: () => { if (generation === this.generation) this.loading.set(false); }
    });
  }
  read(item: AppNotification) { const generation = this.generation; if (!item.isRead) this.http.patch<void>(`${this.config.apiBaseUrl}/notifications/${item.notificationId}/read`, {}).pipe(takeUntil(this.identityChanged)).subscribe(() => { if (generation !== this.generation) return; item.isRead = true; this.items.update(items => [...items]); }); }
  readAll() { const generation = this.generation; this.http.post<void>(`${this.config.apiBaseUrl}/notifications/read-all`, {}).pipe(takeUntil(this.identityChanged)).subscribe(() => { if (generation !== this.generation) return; this.items.update(items => items.map(item => ({ ...item, isRead: true }))); this.unread.set(0); }); }
}
