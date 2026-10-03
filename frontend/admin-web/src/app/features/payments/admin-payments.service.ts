import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { RuntimeConfig } from '../../core/runtime-config';

export interface AdminPaymentItem {
  paymentId: string;
  transactionCode: string;
  userId: string;
  userName: string;
  email: string;
  avatarUrl: string | null;
  planId: string;
  planName: string;
  type: string;
  paymentMethod: string;
  amount: number;
  currency: string;
  status: string;
  createdAt: string;
  paidAt: string | null;
  updatedAt: string;
  expiresAt: string;
  sepayTransactionId: number | null;
  planHistoryId: string | null;
}

export interface AdminPaymentStats {
  revenueInRange: number;
  revenueThisMonth: number;
  successfulTransactions: number;
  refundTransactions: number;
  pendingTransactions: number;
  failedTransactions: number;
}

export interface AdminPaymentDaily { date: string; revenue: number; transactions: number; }
export interface AdminPaymentMethod { method: string; transactions: number; revenue: number; share: number; }
export interface AdminPaymentPage {
  items: AdminPaymentItem[];
  page: number;
  pageSize: number;
  total: number;
  hasMore: boolean;
  stats: AdminPaymentStats;
  daily: AdminPaymentDaily[];
  methods: AdminPaymentMethod[];
  availableMethods: string[];
}
export interface AdminPaymentEvent { status: string; title: string; description: string; occurredAt: string; }
export interface AdminPaymentDetail { transaction: AdminPaymentItem; events: AdminPaymentEvent[]; }
export interface AdminPaymentFilters {
  search?: string;
  status?: string;
  method?: string;
  type?: string;
  fromDate?: string;
  toDate?: string;
  page?: number;
  pageSize?: number;
}

@Injectable({ providedIn: 'root' })
export class AdminPaymentsService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);
  private readonly base = this.config.apiBaseUrl + '/admin/payments';

  list(filters: AdminPaymentFilters) {
    return this.http.get<AdminPaymentPage>(this.base, { params: this.toParams(filters) });
  }

  detail(paymentId: string) {
    return this.http.get<AdminPaymentDetail>(`${this.base}/${paymentId}`);
  }

  export(filters: AdminPaymentFilters) {
    return this.http.get<AdminPaymentItem[]>(`${this.base}/export`, { params: this.toParams(filters) });
  }

  private toParams(filters: AdminPaymentFilters): HttpParams {
    let params = new HttpParams();
    for (const [key, value] of Object.entries(filters)) {
      if (value !== undefined && value !== null && value !== '') params = params.set(key, String(value));
    }
    return params;
  }
}
