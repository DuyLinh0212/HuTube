import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { RuntimeConfig } from './runtime-config';

export interface Plan {
  planId: string;
  code: string;
  name: string;
  description: string | null;
  price: number;
  durationDays: number;
  storageLimit: number;
  maxUploadSize: number;
  maxVideoDuration: number;
  maxVideoQuality: string | null;
  maxDownloadQuality?: string | null;
  maxMembers: number;
  status: string;
  features?: Record<string, boolean>;
  displayOrder?: number;
}

export interface PlanMember {
  planMemberId: string;
  planId: string;
  ownerUserId: string;
  memberEmail: string;
  memberUserId: string | null;
  status: string;
  invitedAt: string;
  acceptedAt: string | null;
  revokedAt: string | null;
  allocatedStorage?: number | null;
  storageUsed?: number;
}

export interface PlanSubscriptionInfo {
  planHistoryId: string;
  startedAt: string;
  endedAt: string | null;
  autoRenew: boolean;
  isExpired: boolean;
}

export interface MyPlan extends Plan {
  usedStorage: number;
  remainingStorage: number;
  members: PlanMember[];
  subscription?: PlanSubscriptionInfo | null;
  isSharedMember?: boolean;
  activePaidPlanIds?: string[];
  ownerAllocatedStorage?: number | null;
}

export interface PlanShare {
  planId: string;
  code: string;
  name: string;
  description: string | null;
  shareUrl: string;
  status: string;
  features?: Record<string, boolean>;
}

export interface CreatePaymentResponse {
  paymentId: string;
  planId: string;
  planName: string;
  transactionCode: string;
  qrCodeUrl: string;
  amount: number;
  currency: string;
  expiresAt: string;
}

export interface PaymentSummary {
  paymentId: string;
  planId: string;
  planName: string;
  transactionCode: string;
  amount: number;
  currency: string;
  status: string;
  paidAt: string | null;
  createdAt: string;
  expiresAt: string;
}

@Injectable({ providedIn: 'root' })
export class PlanService {
  private http = inject(HttpClient);
  private config = inject(RuntimeConfig);
  private base = this.config.apiBaseUrl + '/plans';
  private paymentsBase = this.config.apiBaseUrl + '/payments';

  getPlans(): Observable<Plan[]> { return this.http.get<Plan[]>(this.base); }
  getPlan(planId: string): Observable<Plan> { return this.http.get<Plan>(`${this.base}/${planId}`); }
  getShare(planId: string): Observable<PlanShare> { return this.http.get<PlanShare>(`${this.base}/${planId}/share`); }
  getMyPlan(): Observable<MyPlan | null> { return this.http.get<MyPlan | null>(`${this.base}/my-plan`); }
  subscribe(planId: string): Observable<Plan> { return this.http.post<Plan>(`${this.base}/${planId}/subscribe`, { autoRenew: false }); }
  invite(email: string, allocatedStorage?: number | null): Observable<PlanMember> { return this.http.post<PlanMember>(`${this.base}/members/invite`, { email, allocatedStorage }); }
  accept(memberId: string, token: string): Observable<PlanMember> { return this.http.post<PlanMember>(`${this.base}/members/${memberId}/accept`, { token }); }
  revoke(memberId: string): Observable<void> { return this.http.delete<void>(`${this.base}/members/${memberId}`); }
  updateMemberStorage(memberId: string, allocatedStorage: number | null): Observable<PlanMember> {
    return this.http.patch<PlanMember>(`${this.base}/my-subscription/members/${memberId}/storage`, { allocatedStorage });
  }
  updateOwnerStorage(allocatedStorage: number | null): Observable<void> {
    return this.http.patch<void>(`${this.base}/my-subscription/owner-storage`, { allocatedStorage });
  }

  initiatePayment(planId: string, autoRenew = false, idempotencyKey?: string): Observable<CreatePaymentResponse> {
    return this.http.post<CreatePaymentResponse>(this.paymentsBase, { planId, autoRenew, idempotencyKey });
  }

  getPayment(paymentId: string): Observable<PaymentSummary> {
    return this.http.get<PaymentSummary>(`${this.paymentsBase}/${paymentId}`);
  }

  getMyPayments(): Observable<PaymentSummary[]> {
    return this.http.get<PaymentSummary[]>(this.paymentsBase);
  }
}
