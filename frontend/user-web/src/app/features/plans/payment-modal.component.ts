import { Component, EventEmitter, Input, Output, OnDestroy, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CreatePaymentResponse, PaymentSummary, PlanService } from '../../core/plan.service';
import { LocaleCurrencyPipe } from '../../core/locale-currency.pipe';
import { TranslatePipe } from '../../core/translate.pipe';
import { Subscription, interval } from 'rxjs';

@Component({
  selector: 'app-payment-modal',
  standalone: true,
  imports: [CommonModule, LocaleCurrencyPipe],
  template: `
    <div class="modal-backdrop" (click)="close()">
      <div class="modal-card" (click)="$event.stopPropagation()">
        <div class="modal-header">
          <div class="title-wrap">
            <span class="badge">SePay VietQR</span>
            <h2>Thanh toán gói {{ payment.planName }}</h2>
          </div>
          <button class="close-btn" (click)="close()" aria-label="Đóng">✕</button>
        </div>

        <div class="modal-body">
          <!-- Trạng thái: Đang chờ thanh toán -->
          <ng-container *ngIf="status() === 'pending'">
            <div class="qr-section">
              <div class="qr-wrapper" *ngIf="payment.qrCodeUrl; else noQr">
                <img [src]="payment.qrCodeUrl" alt="VietQR Payment Code" class="qr-image" />
                <div class="scan-hint">Mở App ngân hàng để quét mã QR</div>
              </div>
              <ng-template #noQr>
                <div class="no-qr-box">
                  <p>Hệ thống chưa cấu hình tài khoản nhận SePay.</p>
                  <p class="sub-hint">Vui lòng liên hệ quản trị viên để hoàn tất cấu hình.</p>
                </div>
              </ng-template>

              <div class="info-list">
                <div class="info-item">
                  <span class="label">Số tiền:</span>
                  <span class="value amount">{{ payment.amount | localeCurrency:payment.currency }}</span>
                </div>
                <div class="info-item">
                  <span class="label">Nội dung chuyển khoản:</span>
                  <div class="code-box">
                    <span class="code">{{ payment.transactionCode }}</span>
                    <button class="copy-btn" (click)="copyCode()" type="button">
                      {{ copied() ? 'Đã chép!' : 'Sao chép' }}
                    </button>
                  </div>
                </div>
                <div class="info-item countdown">
                  <span class="label">Thời hạn thanh toán:</span>
                  <span class="value timer">{{ remainingTime() }}</span>
                </div>
              </div>
            </div>

            <div class="waiting-indicator">
              <span class="spinner"></span>
              <span>Đang chờ hệ thống ghi nhận chuyển khoản tự động...</span>
            </div>
          </ng-container>

          <!-- Trạng thái: Thành công -->
          <div *ngIf="status() === 'paid'" class="result-box success">
            <div class="icon">✅</div>
            <h3>Thanh toán thành công!</h3>
            <p>Gói dịch vụ <strong>{{ payment.planName }}</strong> đã được kích hoạt ngay lập tức.</p>
            <button class="action-btn" (click)="onSuccessDone()">Hoàn tất</button>
          </div>

          <!-- Trạng thái: Hết hạn / Huỷ -->
          <div *ngIf="status() === 'cancelled'" class="result-box failed">
            <div class="icon">⏰</div>
            <h3>Đơn hàng đã hết hạn</h3>
            <p>Đã quá thời gian chờ chuyển khoản. Vui lòng tạo yêu cầu thanh toán mới.</p>
            <button class="action-btn" (click)="close()">Đóng</button>
          </div>
        </div>
      </div>
    </div>
  `,
  styles: [`
    .modal-backdrop {
      position: fixed; inset: 0; background: rgba(0, 0, 0, 0.7);
      display: flex; align-items: center; justify-content: center; z-index: 1000;
      backdrop-filter: blur(4px);
    }
    .modal-card {
      background: var(--surface-primary, #1e1e24); color: var(--text-primary, #fff);
      border-radius: 16px; width: 100%; max-width: 480px; padding: 24px;
      box-shadow: 0 12px 32px rgba(0,0,0,0.5); border: 1px solid rgba(255,255,255,0.1);
    }
    .modal-header {
      display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 20px;
    }
    .title-wrap h2 { margin: 6px 0 0; font-size: 1.25rem; }
    .badge {
      font-size: 0.75rem; background: #0066cc; color: #fff; padding: 2px 8px;
      border-radius: 6px; font-weight: 600; text-transform: uppercase;
    }
    .close-btn {
      background: none; border: none; font-size: 1.2rem; color: var(--text-secondary, #aaa);
      cursor: pointer; padding: 4px 8px; border-radius: 6px;
    }
    .close-btn:hover { color: #fff; background: rgba(255,255,255,0.1); }
    .qr-wrapper {
      text-align: center; margin-bottom: 20px; background: #fff; padding: 16px;
      border-radius: 12px; display: inline-block; width: 100%; box-sizing: border-box;
    }
    .qr-image { width: 220px; height: 220px; object-fit: contain; margin: 0 auto; display: block; }
    .scan-hint { color: #333; font-size: 0.85rem; margin-top: 8px; font-weight: 500; }
    .no-qr-box {
      text-align: center; padding: 24px; background: rgba(255,255,255,0.05);
      border-radius: 12px; margin-bottom: 20px;
    }
    .no-qr-box .sub-hint { font-size: 0.85rem; opacity: 0.7; }
    .info-list { display: flex; flex-direction: column; gap: 12px; margin-bottom: 20px; }
    .info-item { display: flex; justify-content: space-between; align-items: center; font-size: 0.95rem; }
    .info-item .label { opacity: 0.8; }
    .info-item .value.amount { font-size: 1.2rem; font-weight: 700; color: #4ade80; }
    .code-box { display: flex; align-items: center; gap: 8px; }
    .code {
      font-family: monospace; font-weight: 700; background: rgba(255,255,255,0.1);
      padding: 4px 8px; border-radius: 6px; letter-spacing: 1px; color: #fbbf24;
    }
    .copy-btn {
      background: rgba(255,255,255,0.15); border: none; color: #fff; padding: 4px 8px;
      border-radius: 4px; font-size: 0.8rem; cursor: pointer;
    }
    .copy-btn:hover { background: rgba(255,255,255,0.25); }
    .countdown .timer { font-weight: 600; color: #f87171; }
    .waiting-indicator {
      display: flex; align-items: center; justify-content: center; gap: 10px;
      font-size: 0.85rem; opacity: 0.8; padding: 12px;
      background: rgba(255,255,255,0.03); border-radius: 8px;
    }
    .spinner {
      width: 16px; height: 16px; border: 2px solid rgba(255,255,255,0.2);
      border-top-color: #3b82f6; border-radius: 50%;
      animation: spin 1s linear infinite; display: inline-block;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    .result-box { text-align: center; padding: 24px 0; }
    .result-box .icon { font-size: 3rem; margin-bottom: 12px; }
    .result-box h3 { margin-bottom: 8px; }
    .result-box p { opacity: 0.85; margin-bottom: 20px; font-size: 0.95rem; }
    .action-btn {
      background: #2563eb; color: #fff; border: none; padding: 10px 24px;
      border-radius: 8px; font-weight: 600; cursor: pointer;
    }
    .action-btn:hover { background: #1d4ed8; }
  `]
})
export class PaymentModalComponent implements OnInit, OnDestroy {
  @Input({ required: true }) payment!: CreatePaymentResponse;
  @Output() completed = new EventEmitter<void>();
  @Output() dismissed = new EventEmitter<void>();

  private readonly planService = inject(PlanService);

  readonly status = signal<'pending' | 'paid' | 'cancelled'>('pending');
  readonly copied = signal(false);
  readonly remainingTime = signal('');

  private pollSub?: Subscription;
  private timerSub?: Subscription;

  ngOnInit() {
    this.startCountdown();
    this.startPolling();
  }

  ngOnDestroy() {
    this.pollSub?.unsubscribe();
    this.timerSub?.unsubscribe();
  }

  copyCode() {
    const code = this.payment.transactionCode;
    navigator.clipboard.writeText(code).then(() => {
      this.copied.set(true);
      setTimeout(() => this.copied.set(false), 2000);
    });
  }

  close() {
    this.dismissed.emit();
  }

  onSuccessDone() {
    this.completed.emit();
  }

  private startCountdown() {
    const expiresAt = new Date(this.payment.expiresAt).getTime();
    const update = () => {
      const now = Date.now();
      const diff = Math.max(0, Math.floor((expiresAt - now) / 1000));
      if (diff <= 0) {
        this.remainingTime.set('Hết hạn');
        if (this.status() === 'pending') {
          this.status.set('cancelled');
          this.pollSub?.unsubscribe();
        }
        return;
      }
      const mins = Math.floor(diff / 60);
      const secs = diff % 60;
      this.remainingTime.set(`${mins}:${secs < 10 ? '0' : ''}${secs}`);
    };
    update();
    this.timerSub = interval(1000).subscribe(update);
  }

  private startPolling() {
    // Poll mỗi 4 giây để kiểm tra trạng thái thanh toán từ webhook SePay
    this.pollSub = interval(4000).subscribe(() => {
      this.planService.getPayment(this.payment.paymentId).subscribe({
        next: (p: PaymentSummary) => {
          if (p.status === 'paid') {
            this.status.set('paid');
            this.pollSub?.unsubscribe();
            this.timerSub?.unsubscribe();
          } else if (p.status === 'cancelled' || p.status === 'failed') {
            this.status.set('cancelled');
            this.pollSub?.unsubscribe();
            this.timerSub?.unsubscribe();
          }
        },
        error: () => undefined
      });
    });
  }
}
