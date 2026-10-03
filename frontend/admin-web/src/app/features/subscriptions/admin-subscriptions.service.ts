import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { RuntimeConfig } from '../../core/runtime-config';

export interface AdminSubscription {
  planHistoryId: string;
  userId: string;
  userName: string;
  email: string;
  avatarUrl: string | null;
  planId: string;
  planCode: string;
  planName: string;
  price: number;
  durationDays: number;
  cycle: 'monthly' | 'yearly' | 'custom';
  status: 'active' | 'expiring' | 'expired' | string;
  startedAt: string;
  expiresAt: string | null;
  autoRenew: boolean;
  lastPaymentAt: string | null;
  lastPaymentAmount: number | null;
  lastPaymentStatus: string | null;
}

export interface AdminSubscriptionPayment {
  paymentId: string;
  planId: string;
  planName: string;
  transactionCode: string;
  amount: number;
  currency: string;
  status: string;
  createdAt: string;
  paidAt: string | null;
}

export interface AdminSubscriptionStats {
  totalSubscriptions: number;
  activeSubscriptions: number;
  expiringSubscriptions: number;
  expiredSubscriptions: number;
  autoRenewSubscriptions: number;
  pendingPayments: number;
  paidRevenueThisMonth: number;
  paidTransactionsThisMonth: number;
  failedPayments: number;
  newSubscriptionsThisMonth: number;
}

export interface AdminSubscriptionPage {
  items: AdminSubscription[];
  page: number;
  pageSize: number;
  total: number;
  hasMore: boolean;
  stats: AdminSubscriptionStats;
}

export interface AdminSubscriptionDetail {
  subscription: AdminSubscription;
  payments: AdminSubscriptionPayment[];
}

export interface SubscriptionFilters {
  search?: string;
  status?: string;
  planId?: string;
  cycle?: string;
  autoRenew?: boolean;
  fromDate?: string;
  toDate?: string;
  page?: number;
  pageSize?: number;
}

@Injectable({ providedIn: 'root' })
export class AdminSubscriptionsService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);
  private readonly base = this.config.apiBaseUrl + '/admin/subscriptions';

  list(filters: SubscriptionFilters) {
    return this.http.get<AdminSubscriptionPage>(this.base, { params: this.toParams(filters) });
  }

  export(filters: SubscriptionFilters) {
    return this.http.get<AdminSubscription[]>(`${this.base}/export`, { params: this.toParams(filters) });
  }

  detail(historyId: string) {
    return this.http.get<AdminSubscriptionDetail>(`${this.base}/${historyId}`);
  }

  extend(historyId: string) {
    return this.http.post<AdminSubscription>(`${this.base}/${historyId}/extend`, {});
  }

  switchPlan(historyId: string, planId: string) {
    return this.http.post<AdminSubscription>(`${this.base}/${historyId}/change-plan`, { planId });
  }

  private toParams(filters: SubscriptionFilters): HttpParams {
    let params = new HttpParams();
    for (const [key, value] of Object.entries(filters)) {
      if (value !== undefined && value !== null && value !== '') params = params.set(key, String(value));
    }
    return params;
  }
}
