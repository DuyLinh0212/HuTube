import { CommonModule } from '@angular/common';
import { Component, EventEmitter, Input, OnChanges, OnInit, Output, SimpleChanges, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { ContentService, DEFAULT_VIOLATION_TYPES, ViolationType } from '../../core/content.service';
import { I18nService } from '../../core/i18n.service';
import { ThemeService } from '../../core/theme.service';
import { TranslatePipe } from '../../core/translate.pipe';

export interface ReportReasonOption {
  code: string;
  nameKey: string;
  infoTipKey?: string;
}

export const CHANNEL_REPORT_OPTIONS: ReportReasonOption[] = [
  {
    code: 'harassment',
    nameKey: 'report.reason.harassment',
    infoTipKey: 'report.reasonTip.harassment'
  },
  {
    code: 'privacy',
    nameKey: 'report.reason.privacy',
    infoTipKey: 'report.reasonTip.privacy'
  },
  {
    code: 'impersonation',
    nameKey: 'report.reason.impersonation',
    infoTipKey: 'report.reasonTip.impersonation'
  },
  {
    code: 'violence_threat',
    nameKey: 'report.reason.violenceThreat',
    infoTipKey: 'report.reasonTip.violenceThreat'
  },
  {
    code: 'child_safety',
    nameKey: 'report.reason.childSafety',
    infoTipKey: 'report.reasonTip.childSafety'
  },
  {
    code: 'hate_speech',
    nameKey: 'report.reason.hateSpeech',
    infoTipKey: 'report.reasonTip.hateSpeech'
  },
  {
    code: 'fraud',
    nameKey: 'report.reason.fraud',
    infoTipKey: 'report.reasonTip.fraud'
  },
  {
    code: 'other',
    nameKey: 'report.reason.other',
    infoTipKey: 'report.reasonTip.otherChannel'
  }
];

export const CONTENT_REPORT_OPTIONS: ReportReasonOption[] = [
  {
    code: 'sexual',
    nameKey: 'report.reason.sexual',
    infoTipKey: 'report.reasonTip.sexual'
  },
  {
    code: 'violent',
    nameKey: 'report.reason.violent',
    infoTipKey: 'report.reasonTip.violent'
  },
  {
    code: 'hate',
    nameKey: 'report.reason.hate',
    infoTipKey: 'report.reasonTip.hate'
  },
  {
    code: 'harassment',
    nameKey: 'report.reason.harassmentContent',
    infoTipKey: 'report.reasonTip.harassmentContent'
  },
  {
    code: 'harmful',
    nameKey: 'report.reason.harmful',
    infoTipKey: 'report.reasonTip.harmful'
  },
  {
    code: 'self_harm',
    nameKey: 'report.reason.selfHarm',
    infoTipKey: 'report.reasonTip.selfHarm'
  },
  {
    code: 'spam',
    nameKey: 'report.reason.spam',
    infoTipKey: 'report.reasonTip.spam'
  },
  {
    code: 'copyright',
    nameKey: 'report.reason.copyright',
    infoTipKey: 'report.reasonTip.copyright'
  },
  {
    code: 'other',
    nameKey: 'report.reason.other',
    infoTipKey: 'report.reasonTip.otherContent'
  }
];

@Component({
  selector: 'app-report-modal',
  standalone: true,
  imports: [CommonModule, FormsModule, TranslatePipe],
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
                <h2>{{ (targetType === 'channel' ? 'report.userTitle' : 'report.title') | translate }}</h2>
              </div>
              <button type="button" class="btn-close" (click)="closeModal()" [attr.aria-label]="'common.close' | translate">
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
                  {{ (targetType === 'channel' ? 'report.channelQuestion' : 'report.contentQuestion') | translate }}
                </h3>
                @if (targetType !== 'channel') {
                  <p class="step-guideline">
                    {{ 'report.guidelineReassurance' | translate }}
                  </p>
                }
              </div>

              <!-- Options List -->
              <div class="options-list" role="radiogroup" [attr.aria-label]="'report.reasonList' | translate">
                @for (opt of currentOptions(); track opt.code) {
                  <div
                    class="option-row"
                    [class.is-selected]="selectedCode() === opt.code"
                    (click)="selectOption(opt.code)">
                    <div class="radio-outer" [class.is-checked]="selectedCode() === opt.code">
                      <div class="radio-inner" [class.is-checked]="selectedCode() === opt.code"></div>
                    </div>
                    <span class="option-label">{{ opt.nameKey | translate }}</span>

                    <!-- Info Icon with Tooltip (Hình 2) -->
                    @if (opt.infoTipKey) {
                      <div
                        class="info-tooltip-wrap"
                        (click)="$event.stopPropagation(); toggleTooltip(opt.code)"
                        (mouseenter)="activeTooltipCode.set(opt.code)"
                        (mouseleave)="activeTooltipCode.set(null)">
                        <button type="button" class="btn-info-icon" [attr.aria-label]="'report.details' | translate">
                          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                            <circle cx="12" cy="12" r="10"/>
                            <path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/>
                            <line x1="12" y1="17" x2="12.01" y2="17"/>
                          </svg>
                        </button>
                        @if (activeTooltipCode() === opt.code) {
                          <div class="tooltip-bubble" role="tooltip">
                            {{ opt.infoTipKey | translate }}
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
                {{ 'common.continue' | translate }}
              </button>
            </footer>
          }

          <!-- STEP 2 (Hình 4) -->
          @if (step() === 2) {
            <!-- Modal Header Step 2: Back Button (←), Title, Close (X) -->
            <header class="modal-header header-step2">
              <div class="header-left-group">
                <button type="button" class="btn-back" (click)="goBackToStep1()" [attr.aria-label]="'common.back' | translate">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                    <line x1="19" y1="12" x2="5" y2="12"/>
                    <polyline points="12 19 5 12 12 5"/>
                  </svg>
                </button>
                <h2>{{ 'report.title' | translate }}</h2>
              </div>
              <button type="button" class="btn-close" (click)="closeModal()" [attr.aria-label]="'common.close' | translate">
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
                <h3 class="step-title">{{ 'report.additionalDetailsTitle' | translate }}</h3>
                <p class="step-guideline">
                  {{ 'report.additionalDetailsDescription' | translate }}
                </p>
              </div>

              <!-- Textarea for additional details -->
              <div class="textarea-container">
                <textarea
                  class="report-textarea"
                  rows="6"
                  [ngModel]="description()"
                  (ngModelChange)="description.set($event)"
                  [placeholder]="'report.detailsPlaceholder' | translate">
                </textarea>
              </div>

              <!-- Quick Template Suggestions -->
              <div class="quick-chips-wrap">
                <span class="chips-label">{{ 'report.quickSuggestions' | translate }}</span>
                <div class="chips-list">
                  @for (sampleKey of sampleTemplateKeys; track sampleKey) {
                    <button type="button" class="chip-item" (click)="applySample(sampleKey)">
                      + {{ sampleKey | translate }}
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
                  <span>{{ 'report.submitting' | translate }}</span>
                } @else {
                  <span>{{ 'report.submit' | translate }}</span>
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
  private readonly i18n = inject(I18nService);

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
  private reportIdempotencyKey = this.newReportIdempotencyKey();

  readonly isDark = computed(() => this.themeService.currentTheme() === 'dark');

  readonly currentOptions = computed<ReportReasonOption[]>(() => {
    return this.targetType === 'channel' ? CHANNEL_REPORT_OPTIONS : CONTENT_REPORT_OPTIONS;
  });

  readonly selectedOption = computed<ReportReasonOption | undefined>(() => {
    return this.currentOptions().find(o => o.code === this.selectedCode());
  });

  readonly sampleTemplateKeys = [
    'report.sample.inappropriate',
    'report.sample.spam',
    'report.sample.impersonation',
    'report.sample.abusiveComment',
    'report.sample.copyright',
    'report.sample.dangerousConduct'
  ];

  ngOnInit(): void {
    this.loadViolationTypes();
  }

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['isOpen'] && this.isOpen) {
      this.reportIdempotencyKey = this.newReportIdempotencyKey();
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

  applySample(sampleKey: string): void {
    const sample = this.i18n.t(sampleKey);
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
      this.errorMessage.set(this.i18n.t('report.loginRequired'));
      const currentUrl = this.router.url;
      setTimeout(() => {
        void this.router.navigate(['/login'], { queryParams: { returnUrl: currentUrl } });
      }, 1000);
      return;
    }

    const opt = this.selectedOption();
    if (!opt) {
      this.errorMessage.set(this.i18n.t('report.reasonRequired'));
      return;
    }

    const typeId = this.findViolationTypeId(opt.code);
    const detailText = this.description().trim();
    const reason = this.i18n.t(opt.nameKey);
    const finalDescription = detailText
      ? this.i18n.format('report.submissionWithDetails', { reason, detail: detailText })
      : this.i18n.format('report.submission', { reason });

    this.submitting.set(true);
    this.errorMessage.set(null);

    this.contentService.reportContent(this.targetType, this.targetId, typeId, finalDescription, this.reportIdempotencyKey).subscribe({
      next: () => {
        this.submitting.set(false);
        this.successMessage.set(this.i18n.t('report.sentSuccessfully'));
        this.submitted.emit({ violationTypeId: typeId, description: finalDescription });
        setTimeout(() => {
          this.closeModal();
        }, 1200);
      },
      error: (err: any) => {
        this.submitting.set(false);
        const msg = err?.error?.message || err?.message || this.i18n.t('report.sendError');
        this.errorMessage.set(msg);
      }
    });
  }

  private newReportIdempotencyKey(): string {
    return typeof crypto !== 'undefined' && 'randomUUID' in crypto
      ? crypto.randomUUID()
      : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  }
}
