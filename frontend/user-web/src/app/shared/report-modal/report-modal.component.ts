import { CommonModule } from '@angular/common';
import { Component, EventEmitter, Input, OnChanges, OnInit, Output, SimpleChanges, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { ContentService, DEFAULT_VIOLATION_TYPES, ViolationType } from '../../core/content.service';
import { ThemeService } from '../../core/theme.service';

export interface ReportReasonOption {
  code: string;
  name: string;
  infoTip?: string;
}

export const CHANNEL_REPORT_OPTIONS: ReportReasonOption[] = [
  {
    code: 'harassment',
    name: 'Quấy rối và bắt nạt qua mạng',
    infoTip: 'Bao gồm hành vi bắt nạt, đe dọa trực tuyến, rình rập hoặc quấy rối người khác.'
  },
  {
    code: 'privacy',
    name: 'Quyền riêng tư',
    infoTip: 'Tiết lộ thông tin nhận dạng cá nhân hoặc hình ảnh riêng tư mà không có sự đồng ý.'
  },
  {
    code: 'impersonation',
    name: 'Mạo danh',
    infoTip: 'Giả danh một kênh, cá nhân hoặc tổ chức khác nhằm gây hiểu lầm hoặc lừa đảo.'
  },
  {
    code: 'violence_threat',
    name: 'Đe dọa sử dụng bạo lực',
    infoTip: 'Nội dung chứa lời đe dọa thực tế nhằm gây hại hoặc tấn công thân thể ai đó.'
  },
  {
    code: 'child_safety',
    name: 'Gây nguy hiểm cho trẻ em',
    infoTip: 'Nội dung bóc lột tình dục trẻ em, lạm dụng hoặc gây nguy hiểm về thể chất/tinh thần cho trẻ vị thành niên.'
  },
  {
    code: 'hate_speech',
    name: 'Lời nói căm thù nhắm đến một nhóm người được bảo vệ',
    infoTip: 'Kích động thù hận, phân biệt đối xử dựa trên chủng tộc, tôn giáo, giới tính, khuyết tật.'
  },
  {
    code: 'fraud',
    name: 'Nội dung vi phạm và lừa đảo',
    infoTip: 'Nội dung lừa đảo tài chính, phát tán phần mềm độc hại hoặc vi phạm pháp luật.'
  },
  {
    code: 'other',
    name: 'Vấn đề của tôi không có trong danh sách trên',
    infoTip: 'Các lý do vi phạm khác chưa được phân loại cụ thể ở trên.'
  }
];

export const CONTENT_REPORT_OPTIONS: ReportReasonOption[] = [
  {
    code: 'sexual',
    name: 'Nội dung khiêu dâm',
    infoTip: 'Hình ảnh, video đồi trụy hoặc khiêu dâm.'
  },
  {
    code: 'violent',
    name: 'Nội dung bạo lực hoặc phản cảm',
    infoTip: 'Cảnh máu me, bạo lực tàn bạo hoặc gây sốc.'
  },
  {
    code: 'hate',
    name: 'Nội dung lăng mạ hoặc kích động thù hận',
    infoTip: 'Xúc phạm danh dự hoặc kích động thù địch.'
  },
  {
    code: 'harassment',
    name: 'Nội dung quấy rối hoặc bắt nạt',
    infoTip: 'Hành vi xúc phạm, quấy rối hoặc đe dọa.'
  },
  {
    code: 'harmful',
    name: 'Hành động gây hại hoặc nguy hiểm',
    infoTip: 'Thực hiện hoặc khuyến khích các thử thách nguy hiểm có thể gây thương tích.'
  },
  {
    code: 'self_harm',
    name: 'Hành vi tự tử, tự huỷ hoại bản thân hoặc chứng rối loạn ăn uống',
    infoTip: 'Khuyến khích hoặc hướng dẫn hành vi tự tử, tự làm hại bản thân.'
  },
  {
    code: 'spam',
    name: 'Spam hoặc thông tin sai lệch',
    infoTip: 'Spam liên kết, lừa đảo, lan truyền tin giả.'
  },
  {
    code: 'copyright',
    name: 'Vi phạm bản quyền',
    infoTip: 'Sử dụng tác phẩm hoặc nội dung không có bản quyền.'
  },
  {
    code: 'other',
    name: 'Vấn đề của tôi không có trong danh sách trên',
    infoTip: 'Lý do vi phạm khác.'
  }
];

@Component({
  selector: 'app-report-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    @if (isOpen) {
      <div
        class="modal-backdrop"
        [class.dark-theme]="isDark()"
        [class.light-theme]="!isDark()"
        role="dialog"
        aria-modal="true"
        (click)="onBackdropClick($event)">
        <div
          class="report-modal"
          [class.dark-theme]="isDark()"
          [class.light-theme]="!isDark()"
          (click)="$event.stopPropagation()">

          <!-- STEP 1 (Hình 2 hoặc Hình 3) -->
          @if (step() === 1) {
            <!-- Modal Header Step 1 -->
            <header class="modal-header">
              <div class="header-title-box">
                <h2>{{ targetType === 'channel' ? 'Báo cáo người dùng' : 'Báo cáo' }}</h2>
              </div>
              <button type="button" class="btn-close" (click)="closeModal()" aria-label="Đóng">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <line x1="18" y1="6" x2="6" y2="18"/>
                  <line x1="6" y1="6" x2="18" y2="18"/>
                </svg>
              </button>
            </header>

            <!-- Modal Body Step 1 -->
            <div class="modal-body step1-body">
              @if (errorMessage()) {
                <div class="alert-box alert-error">{{ errorMessage() }}</div>
              }
              @if (successMessage()) {
                <div class="alert-box alert-success">{{ successMessage() }}</div>
              }

              <div class="step-intro-box">
                <h3 class="step-title">
                  {{ targetType === 'channel' ? 'Vấn đề là gì?' : 'Nội dung có vấn đề gì?' }}
                </h3>
                @if (targetType !== 'channel') {
                  <p class="step-guideline">
                    Chúng tôi sẽ kiểm tra theo tất cả Nguyên tắc cộng đồng nên bạn đừng lo lắng về việc phải lựa chọn sao cho chính xác nhất.
                  </p>
                }
              </div>

              <!-- Options List -->
              <div class="options-list" role="radiogroup" aria-label="Lý do báo cáo">
                @for (opt of currentOptions(); track opt.code) {
                  <div
                    class="option-row"
                    [class.is-selected]="selectedCode() === opt.code"
                    (click)="selectOption(opt.code)">
                    <div class="radio-outer" [class.is-checked]="selectedCode() === opt.code">
                      <div class="radio-inner" [class.is-checked]="selectedCode() === opt.code"></div>
                    </div>
                    <span class="option-label">{{ opt.name }}</span>

                    <!-- Info Icon with Tooltip (Hình 2) -->
                    @if (opt.infoTip) {
                      <div
                        class="info-tooltip-wrap"
                        (click)="$event.stopPropagation(); toggleTooltip(opt.code)"
                        (mouseenter)="activeTooltipCode.set(opt.code)"
                        (mouseleave)="activeTooltipCode.set(null)">
                        <button type="button" class="btn-info-icon" aria-label="Thông tin chi tiết">
                          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                            <circle cx="12" cy="12" r="10"/>
                            <path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/>
                            <line x1="12" y1="17" x2="12.01" y2="17"/>
                          </svg>
                        </button>
                        @if (activeTooltipCode() === opt.code) {
                          <div class="tooltip-bubble" role="tooltip">
                            {{ opt.infoTip }}
                          </div>
                        }
                      </div>
                    }
                  </div>
                }
              </div>
            </div>

            <!-- Footer Step 1: Button Tiếp -->
            <footer class="modal-footer" [class.footer-right]="targetType === 'channel'" [class.footer-full]="targetType !== 'channel'">
              <button
                type="button"
                class="btn-pill btn-next"
                [disabled]="!selectedCode()"
                (click)="goToStep2()">
                Tiếp
              </button>
            </footer>
          }

          <!-- STEP 2 (Hình 4) -->
          @if (step() === 2) {
            <!-- Modal Header Step 2: Back Button (←), Title, Close (X) -->
            <header class="modal-header header-step2">
              <div class="header-left-group">
                <button type="button" class="btn-back" (click)="goBackToStep1()" aria-label="Quay lại">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                    <line x1="19" y1="12" x2="5" y2="12"/>
                    <polyline points="12 19 5 12 12 5"/>
                  </svg>
                </button>
                <h2>{{ targetType === 'channel' ? 'Báo cáo' : 'Báo cáo' }}</h2>
              </div>
              <button type="button" class="btn-close" (click)="closeModal()" aria-label="Đóng">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <line x1="18" y1="6" x2="6" y2="18"/>
                  <line x1="6" y1="6" x2="18" y2="18"/>
                </svg>
              </button>
            </header>

            <!-- Modal Body Step 2 -->
            <div class="modal-body step2-body">
              @if (errorMessage()) {
                <div class="alert-box alert-error">{{ errorMessage() }}</div>
              }
              @if (successMessage()) {
                <div class="alert-box alert-success">{{ successMessage() }}</div>
              }

              <div class="step-intro-box">
                <h3 class="step-title">Bạn có muốn chia sẻ thêm gì không? (Không bắt buộc)</h3>
                <p class="step-guideline">
                  Khi chia sẻ thêm thông tin, bạn có thể giúp chúng tôi hiểu rõ vấn đề. Vui lòng không thêm thông tin cá nhân hoặc câu hỏi.
                </p>
              </div>

              <!-- Textarea for additional details -->
              <div class="textarea-container">
                <textarea
                  class="report-textarea"
                  rows="6"
                  [ngModel]="description()"
                  (ngModelChange)="description.set($event)"
                  placeholder="Thêm chi tiết...">
                </textarea>
              </div>

              <!-- Quick Template Suggestions -->
              <div class="quick-chips-wrap">
                <span class="chips-label">Gợi ý nhanh:</span>
                <div class="chips-list">
                  @for (sample of sampleTemplates; track sample) {
                    <button type="button" class="chip-item" (click)="applySample(sample)">
                      + {{ sample }}
                    </button>
                  }
                </div>
              </div>
            </div>

            <!-- Footer Step 2: Button Báo vi phạm -->
            <footer class="modal-footer footer-full">
              <button
                type="button"
                class="btn-pill btn-submit"
                [disabled]="submitting()"
                (click)="submitReport()">
                @if (submitting()) {
                  <span class="spinner"></span>
                  <span>Đang gửi...</span>
                } @else {
                  <span>Báo vi phạm</span>
                }
              </button>
            </footer>
          }

        </div>
      </div>
    }
  `,
  styleUrls: ['./report-modal.component.scss']
})
export class ReportModalComponent implements OnInit, OnChanges {
  private readonly contentService = inject(ContentService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly themeService = inject(ThemeService);

  @Input() isOpen = false;
  @Input() targetType: 'video' | 'channel' | 'comment' = 'video';
  @Input() targetId = '';
  @Input() targetTitle = '';

  @Output() close = new EventEmitter<void>();
  @Output() submitted = new EventEmitter<{ violationTypeId: string; description: string }>();

  readonly step = signal<1 | 2>(1);
  readonly selectedCode = signal<string>('');
  readonly activeTooltipCode = signal<string | null>(null);
  readonly description = signal<string>('');
  readonly submitting = signal<boolean>(false);
  readonly errorMessage = signal<string | null>(null);
  readonly successMessage = signal<string | null>(null);

  readonly backendViolationTypes = signal<ViolationType[]>(DEFAULT_VIOLATION_TYPES);

  readonly isDark = computed(() => this.themeService.currentTheme() === 'dark');

  readonly currentOptions = computed<ReportReasonOption[]>(() => {
    return this.targetType === 'channel' ? CHANNEL_REPORT_OPTIONS : CONTENT_REPORT_OPTIONS;
  });

  readonly selectedOption = computed<ReportReasonOption | undefined>(() => {
    return this.currentOptions().find(o => o.code === this.selectedCode());
  });

  readonly sampleTemplates = [
    'Nội dung phản cảm, không phù hợp',
    'Spam liên kết lừa đảo / quảng cáo rác',
    'Mạo danh cá nhân hoặc tổ chức',
    'Bình luận xúc phạm, bôi nhọ danh dự',
    'Vi phạm bản quyền hình ảnh / âm thanh',
    'Hành vi nguy hiểm hoặc kích động thù hận'
  ];

  ngOnInit(): void {
    this.loadViolationTypes();
  }

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['isOpen'] && this.isOpen) {
      this.step.set(1);
      this.selectedCode.set('');
      this.activeTooltipCode.set(null);
      this.description.set('');
      this.errorMessage.set(null);
      this.successMessage.set(null);
    }
  }

  loadViolationTypes(): void {
    this.contentService.violationTypes().subscribe({
      next: (types: ViolationType[]) => {
        const list = types && types.length > 0 ? types : DEFAULT_VIOLATION_TYPES;
        this.backendViolationTypes.set(list);
      },
      error: () => {
        this.backendViolationTypes.set(DEFAULT_VIOLATION_TYPES);
      }
    });
  }

  selectOption(code: string): void {
    this.selectedCode.set(code);
    this.errorMessage.set(null);
  }

  toggleTooltip(code: string): void {
    if (this.activeTooltipCode() === code) {
      this.activeTooltipCode.set(null);
    } else {
      this.activeTooltipCode.set(code);
    }
  }

  goToStep2(): void {
    if (!this.selectedCode()) return;
    this.step.set(2);
  }

  goBackToStep1(): void {
    this.step.set(1);
    this.errorMessage.set(null);
  }

  applySample(sample: string): void {
    const current = this.description().trim();
    if (!current) {
      this.description.set(sample);
    } else if (!current.includes(sample)) {
      this.description.set(`${current}; ${sample}`);
    }
  }

  findViolationTypeId(code: string): string {
    const types = this.backendViolationTypes();
    if (!types || types.length === 0) {
      return DEFAULT_VIOLATION_TYPES[0].violationTypeId;
    }

    // 1. Check exact match on code
    const exact = types.find(t => t.code.toLowerCase() === code.toLowerCase());
    if (exact) return exact.violationTypeId;

    // 2. Mapping from reason codes to backend violation codes
    const mapToBackend: Record<string, string> = {
      harassment: 'harassment',
      privacy: 'other',
      impersonation: 'spam',
      violence_threat: 'violent',
      child_safety: 'harmful',
      hate_speech: 'hate',
      fraud: 'spam',
      sexual: 'sexual',
      violent: 'violent',
      hate: 'hate',
      harmful: 'harmful',
      self_harm: 'harmful',
      spam: 'spam',
      copyright: 'copyright',
      other: 'other'
    };

    const targetBackendCode = mapToBackend[code] || 'other';
    const backendMatch = types.find(t => t.code.toLowerCase() === targetBackendCode.toLowerCase());
    if (backendMatch) return backendMatch.violationTypeId;

    // 3. Fallback to 'other' or first available
    const otherType = types.find(t => t.code.toLowerCase() === 'other');
    return otherType ? otherType.violationTypeId : types[0].violationTypeId;
  }

  onBackdropClick(event: MouseEvent): void {
    if (event.target === event.currentTarget) {
      this.closeModal();
    }
  }

  closeModal(): void {
    if (this.submitting()) return;
    this.close.emit();
  }

  submitReport(): void {
    if (!this.auth.user()) {
      this.errorMessage.set('Vui lòng đăng nhập để gửi báo cáo.');
      const currentUrl = this.router.url;
      setTimeout(() => {
        void this.router.navigate(['/login'], { queryParams: { returnUrl: currentUrl } });
      }, 1000);
      return;
    }

    const opt = this.selectedOption();
    if (!opt) {
      this.errorMessage.set('Vui lòng chọn loại vi phạm.');
      return;
    }

    const typeId = this.findViolationTypeId(opt.code);
    const detailText = this.description().trim();
    const finalDescription = detailText
      ? `[${opt.name}] ${detailText}`
      : `Báo cáo vi phạm: ${opt.name}`;

    this.submitting.set(true);
    this.errorMessage.set(null);

    this.contentService.reportContent(this.targetType, this.targetId, typeId, finalDescription).subscribe({
      next: () => {
        this.submitting.set(false);
        this.successMessage.set('Cảm ơn bạn! Báo cáo vi phạm đã được gửi đến ban kiểm duyệt.');
        this.submitted.emit({ violationTypeId: typeId, description: finalDescription });
        setTimeout(() => {
          this.closeModal();
        }, 1200);
      },
      error: (err: any) => {
        this.submitting.set(false);
        const msg = err?.error?.message || err?.message || 'Không thể gửi báo cáo vi phạm. Vui lòng thử lại.';
        this.errorMessage.set(msg);
      }
    });
  }
}
