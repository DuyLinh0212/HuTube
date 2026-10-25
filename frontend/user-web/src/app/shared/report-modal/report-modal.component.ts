import { POLICY_CENTER_TRANSLATIONS } from '../../features/policy/policy-translations';
import { CommonModule } from '@angular/common';
import { Component, ElementRef, EventEmitter, HostListener, Input, ViewChild, OnChanges, OnInit, Output, SimpleChanges, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
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
  imports: [CommonModule, FormsModule, RouterLink, TranslatePipe],
  template: `
    @if (isOpen) {
      <div
        class="modal-backdrop"
        [class.dark-theme]="isDark()"
        [class.light-theme]="!isDark()"
        role="dialog"
        aria-modal="true" aria-labelledby="report-modal-title"
        (click)="onBackdropClick($event)">
        <div
          class="report-modal" #reportDialog tabindex="-1"
          [class.dark-theme]="isDark()"
          [class.light-theme]="!isDark()"
          (click)="$event.stopPropagation()">

          <div class="report-progress" aria-live="polite">
            <span>{{ 'report.stepProgress' | translate:{ step: step() } }}</span>
            <strong>{{ (step() === 1 ? 'report.stepReason' : 'report.stepDetails') | translate }}</strong>
            <div class="report-progress-track" aria-hidden="true"><i></i><i [class.complete]="step() === 2"></i></div>
          </div>
          @if (targetTitle) { <div class="report-target"><span>{{ targetTitle }}</span></div> }
          <!-- STEP 1 (Hình 2 hoặc Hình 3) -->
          @if (step() === 1) {
            <!-- Modal Header Step 1 -->
            <header class="modal-header">
              <div class="header-title-box">
                <h2 id="report-modal-title">{{ (targetType === 'channel' ? 'report.userTitle' : 'report.title') | translate }}</h2>
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
                    <input class="report-reason-radio" type="radio" name="report-reason" [id]="'report-reason-' + opt.code" [value]="opt.code"
                      [checked]="selectedCode() === opt.code" (change)="selectOption(opt.code)" />
                    <div aria-hidden="true" class="radio-outer" [class.is-checked]="selectedCode() === opt.code">
                      <div class="radio-inner" [class.is-checked]="selectedCode() === opt.code"></div>
                    </div>
                    <label class="option-label" [for]="'report-reason-' + opt.code">{{ opt.nameKey | translate }}</label>

                    <!-- Info Icon with Tooltip (Hình 2) -->
                    @if (opt.infoTipKey) {
                      <div
                        class="info-tooltip-wrap"
                        (click)="$event.stopPropagation(); toggleTooltip(opt.code)"
                        (mouseenter)="activeTooltipCode.set(opt.code)"
                        (mouseleave)="activeTooltipCode.set(null)">
                        <button type="button" class="btn-info-icon" [attr.aria-expanded]="activeTooltipCode() === opt.code" [attr.aria-controls]="'report-tip-' + opt.code"
                          (focus)="activeTooltipCode.set(opt.code)" (blur)="activeTooltipCode.set(null)" [attr.aria-label]="'report.details' | translate">
                          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                            <circle cx="12" cy="12" r="10"/>
                            <path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/>
                            <line x1="12" y1="17" x2="12.01" y2="17"/>
                          </svg>
                        </button>
                        @if (activeTooltipCode() === opt.code) {
                          <div class="tooltip-bubble" role="tooltip" [id]="'report-tip-' + opt.code">
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
                <h2 id="report-modal-title">{{ 'report.title' | translate }}</h2>
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

              @if (selectedOption(); as option) {
                <div class="selected-report-reason"><span>{{ 'report.selectedReason' | translate }}</span><strong>{{ option.nameKey | translate }}</strong></div>
              }
              <!-- Textarea for additional details -->
              <div class="textarea-container">
                <label for="report-description">{{ 'report.detailsLabel' | translate }}</label>
                <textarea id="report-description"
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
          <a class="report-policy-link" [routerLink]="submitting() ? null : '/guidelines'" [attr.aria-disabled]="submitting()" [attr.tabindex]="submitting() ? -1 : null" (click)="closeModal()">{{ 'report.policyLink' | translate }} <span aria-hidden="true">↗</span></a>
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

  @ViewChild('reportDialog') private reportDialog?: ElementRef<HTMLElement>;
  private previousFocus: HTMLElement | null = null;

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

  constructor() {
    this.i18n.registerTranslations(POLICY_CENTER_TRANSLATIONS);
  }

  ngOnInit(): void {
    this.loadViolationTypes();
  }

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['isOpen'] && !this.isOpen) this.restoreFocus();
    if (changes['isOpen'] && this.isOpen) {
      this.previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
      setTimeout(() => this.reportDialog?.nativeElement.focus());
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
    setTimeout(() => this.reportDialog?.nativeElement.querySelector<HTMLTextAreaElement>('textarea')?.focus());
  }

  goBackToStep1(): void {
    this.step.set(1);
    setTimeout(() => this.reportDialog?.nativeElement.querySelector<HTMLInputElement>('input:checked')?.focus());
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

  @HostListener('document:keydown', ['$event'])
  onDialogKeydown(event: KeyboardEvent): void {
    if (!this.isOpen) return;
    if (event.key === 'Escape') { event.preventDefault(); this.closeModal(); return; }
    if (event.key !== 'Tab') return;
    const dialog = this.reportDialog?.nativeElement;
    const controls = dialog ? Array.from(dialog.querySelectorAll<HTMLElement>(
      'button:not(:disabled), input:not(:disabled), textarea:not(:disabled), a[href]'
    )).filter(element => element.getClientRects().length > 0) : [];
    const first = controls[0], last = controls[controls.length - 1];
    if (!first) { event.preventDefault(); dialog?.focus(); return; }
    if (event.shiftKey && (document.activeElement === first || document.activeElement === dialog)) {
      event.preventDefault(); last.focus();
    } else if (!event.shiftKey && (document.activeElement === last || document.activeElement === dialog)) {
      event.preventDefault(); first.focus();
    }
  }

  private restoreFocus(): void {
    if (this.previousFocus?.isConnected) this.previousFocus.focus({ preventScroll: true });
    this.previousFocus = null;
  }

  onBackdropClick(event: MouseEvent): void {
    if (event.target === event.currentTarget) {
      this.closeModal();
    }
  }

  closeModal(): void {
    if (this.submitting()) return;
    this.restoreFocus();
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
