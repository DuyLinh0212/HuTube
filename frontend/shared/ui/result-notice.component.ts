import { Component, computed, inject, input, output } from '@angular/core';
import { FEEDBACK_LANGUAGE, FEEDBACK_TEXT, FeedbackDetail, FeedbackTone } from './feedback-language';

@Component({
  selector: 'app-result-notice',
  host: { '[class.has-notice]': '!!message() || !!title()' },
  template: `@if (message() || title()) {
    <section class="result-notice" [class]="'result-notice result-notice--' + tone()"
      [attr.role]="tone() === 'error' ? 'alert' : 'status'" [attr.aria-live]="tone() === 'error' ? 'assertive' : 'polite'">
      <span class="notice-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="12" cy="12" r="9"/>
        @if (tone() === 'success') { <path d="m8 12 3 3 5-6"/> }
        @else if (tone() === 'info') { <path d="M12 11v6M12 7h.01"/> }
        @else { <path d="M12 7v6M12 17h.01"/> }
      </svg></span>
      <div class="notice-copy"><strong>{{ title() || text()[tone()] }}</strong>
        @if (message()) { <p>{{ message() }}</p> }
        @if (details().length) { <ul>@for (detail of details(); track $index) { <li><b>{{ detail.label }}</b>@if (detail.message) {<span>: {{ detail.message }}</span>}</li> }</ul> }
      </div>
      @if (dismissible()) { <button type="button" class="notice-close" (click)="dismissed.emit()" [attr.aria-label]="text().close">×</button> }
    </section>
  }`,
  styleUrl: './result-notice.component.scss',
})
export class ResultNoticeComponent {
  readonly message = input<string | null | undefined>('');
  readonly title = input<string | null | undefined>('');
  readonly tone = input<FeedbackTone>('info');
  readonly details = input<readonly FeedbackDetail[]>([]);
  readonly dismissible = input(false);
  readonly dismissed = output<void>();
  private readonly language = inject(FEEDBACK_LANGUAGE);
  readonly text = computed(() => FEEDBACK_TEXT[this.language()]);
}
