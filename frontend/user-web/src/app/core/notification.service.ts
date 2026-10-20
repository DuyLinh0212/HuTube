import { Subject, finalize, takeUntil } from 'rxjs';
import { HttpClient } from '@angular/common/http';
import { Injectable, OnDestroy, effect, inject, signal } from '@angular/core';
import * as signalR from '@microsoft/signalr';
import { Router } from '@angular/router';
import { AuthService } from './auth.service';
import { RuntimeConfig } from './runtime-config';
import { I18nService } from './i18n.service';
import { NetworkStatusService } from './network/network-status.service';

export interface AppNotification { notificationId: string; type: string; title: string; content: string; actionUrl: string | null; isRead: boolean; createdAt: string; }
interface NotificationPage { items: AppNotification[]; page: number; pageSize: number; total: number; unreadCount: number; hasMore: boolean; }

@Injectable({ providedIn: 'root' })
export class NotificationService implements OnDestroy {
  private readonly http = inject(HttpClient);
  private readonly auth = inject(AuthService);
  private readonly config = inject(RuntimeConfig);
  private readonly router = inject(Router);
  private readonly i18n = inject(I18nService);
  private readonly network = inject(NetworkStatusService);
  private notificationFlight = false;
  private revocationFlight = false;
  private nextConnectionAt = 0;
  private generation = 0;
  private identity = '';
  private identityChanged = new Subject<void>();
  private connection?: signalR.HubConnection;
  private revocationPoll?: ReturnType<typeof setInterval>;
  private notificationPoll?: ReturnType<typeof setInterval>;
  private notificationIds = new Set<string>();
  private readingIds = new Set<string>();
  private readAllRevision = 0;
  private notificationPollInitialized = false;
  readonly items = signal<AppNotification[]>([]);
  readonly unread = signal(0);
  readonly hasMore = signal(false);
  readonly invitationVersion = signal(0);
  readonly invitationToast = signal<string | null>(null);
  readonly loading = signal(false);
  readonly loadedPage = signal(0);
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

  ngOnDestroy(): void {
    this.reset();
    this.identityChanged.complete();
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
    this.notificationFlight = false; this.revocationFlight = false; this.nextConnectionAt = 0;
    this.notificationIds.clear(); this.notificationPollInitialized = false;
    this.readingIds.clear(); this.readAllRevision = 0;
    this.items.set([]); this.unread.set(0); this.hasMore.set(false);
    this.loading.set(false); this.invitationToast.set(null); this.page = 0; this.loadedPage.set(0);
  }

  async connect() {
    if (!this.auth.accessToken()) return;
    this.startRevocationWatchdog();
    this.startNotificationPolling();
    if (this.connection || this.network.unavailable() || Date.now() < this.nextConnectionAt) return;
    this.nextConnectionAt = Date.now() + 120_000;
    const generation = this.generation;
    this.connection = new signalR.HubConnectionBuilder()
      .withUrl(this.config.apiBaseUrl.replace(/\/api\/v1$/, '') + '/hubs/notifications', { accessTokenFactory: () => this.auth.accessToken() ?? '' })
      .withAutomaticReconnect({ nextRetryDelayInMilliseconds: context => {
        if (context.previousRetryCount >= 3) return null;
        return this.network.unavailable() || document.hidden ? 60_000 : [5_000, 15_000, 60_000][context.previousRetryCount];
      } })
      .configureLogging(signalR.LogLevel.Warning)
      .build();
    this.connection.onreconnected(() => { if (generation === this.generation) this.loadInitial(); });
    this.connection.onreconnecting(() => {
      if (generation !== this.generation || this.network.unavailable() || this.revocationFlight) return;
      this.revocationFlight = true;
      this.auth.me().pipe(takeUntil(this.identityChanged), finalize(() => { this.revocationFlight = false; }))
        .subscribe({ error: () => undefined });
    });
    this.connection.onclose(() => { if (generation === this.generation) this.connection = undefined; });
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
      if (generation === this.generation) {
        this.connection = undefined;
        if (!this.network.unavailable()) this.loadInitial();
      }
    }
  }

  private startRevocationWatchdog() {
    if (this.revocationPoll) return;
    this.revocationPoll = setInterval(() => {
      // SessionRevoked is pushed over the hub. This is a fallback for missed events.
      if (!this.auth.accessToken() || document.hidden || this.network.unavailable()
          || this.connection?.state === signalR.HubConnectionState.Connected || this.revocationFlight) return;
      this.revocationFlight = true;
      this.auth.me().pipe(takeUntil(this.identityChanged), finalize(() => { this.revocationFlight = false; }))
        .subscribe({ error: () => undefined });
    }, 60_000);
  }

  private startNotificationPolling() {
    if (this.notificationPoll) return;
    this.notificationPoll = setInterval(() => this.pollLatestNotifications(), 30_000);
  }

  private pollLatestNotifications() {
    if (!this.auth.accessToken() || this.loading() || this.notificationFlight || document.hidden || this.network.unavailable()
        || this.connection?.state === signalR.HubConnectionState.Connected) return;
    if (!this.connection && Date.now() >= this.nextConnectionAt) void this.connect();
    this.notificationFlight = true;
    const generation = this.generation;
    this.http.get<NotificationPage>(`${this.config.apiBaseUrl}/notifications`, { params: { page: 1, pageSize: 5 } }).pipe(
      takeUntil(this.identityChanged), finalize(() => { this.notificationFlight = false; }),
    ).subscribe({
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

  loadInitial() {
    if (this.loading()) return;
    this.page = 0;
    this.loadedPage.set(0);
    this.items.set([]);
    this.hasMore.set(false);
    return this.loadMore();
  }
  loadMore() {
    const generation = this.generation;
    if (this.loading() || (this.page > 0 && !this.hasMore())) return;
    this.loading.set(true);
    this.http.get<NotificationPage>(`${this.config.apiBaseUrl}/notifications`, { params: { page: this.page + 1, pageSize: 5 } }).pipe(takeUntil(this.identityChanged)).subscribe({
      next: value => {
        this.page = value.page;
        this.loadedPage.set(value.page);
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
  read(item: AppNotification) {
    const id = item.notificationId;
    const current = this.items().find(candidate => candidate.notificationId === id);
    if (!current || current.isRead || this.readingIds.has(id)) return;

    const generation = this.generation;
    const readAllRevision = this.readAllRevision;
    this.readingIds.add(id);
    this.items.update(items => items.map(candidate => candidate.notificationId === id ? { ...candidate, isRead: true } : candidate));
    this.unread.update(count => Math.max(0, count - 1));

    this.http.patch<void>(`${this.config.apiBaseUrl}/notifications/${id}/read`, {}).pipe(takeUntil(this.identityChanged)).subscribe({
      next: () => {
        if (generation === this.generation) this.readingIds.delete(id);
      },
      error: () => {
        if (generation !== this.generation) return;
        this.readingIds.delete(id);
        if (readAllRevision !== this.readAllRevision) return;
        if (!this.items().find(candidate => candidate.notificationId === id)?.isRead) return;
        this.items.update(items => items.map(candidate => candidate.notificationId === id ? { ...candidate, isRead: false } : candidate));
        this.unread.update(count => count + 1);
      }
    });
  }
  readAll() { const generation = this.generation; this.http.post<void>(`${this.config.apiBaseUrl}/notifications/read-all`, {}).pipe(takeUntil(this.identityChanged)).subscribe(() => { if (generation !== this.generation) return; this.readAllRevision++; this.items.update(items => items.map(item => ({ ...item, isRead: true }))); this.unread.set(0); }); }
}
