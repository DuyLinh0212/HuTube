import { DestroyRef, Injectable, inject, signal } from '@angular/core';

export interface ReviewerLease { status: string; claimId?: string | null; claimExpiresAt?: string | null; }

@Injectable({ providedIn: 'root' })
export class ReviewerLeaseService {
  private readonly now = signal(Date.now());
  constructor() {
    const timer = setInterval(() => this.now.set(Date.now()), 1000);
    inject(DestroyRef).onDestroy(() => clearInterval(timer));
  }
  expired(item: ReviewerLease) {
    const expires = Date.parse(item.claimExpiresAt ?? '');
    return item.status === 'reviewing' && (!item.claimId || !Number.isFinite(expires) || expires <= this.now());
  }
  active(item: ReviewerLease) { return item.status === 'reviewing' && !this.expired(item); }
}
