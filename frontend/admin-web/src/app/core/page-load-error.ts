import { Component, inject } from '@angular/core';
import { DOCUMENT } from '@angular/common';
import { ActivatedRoute } from '@angular/router';
import { internalPath } from './chunk-load-recovery';
import { TranslatePipe } from './translate.pipe';

// Eagerly bundled: this screen must remain available when a lazy chunk is missing.
@Component({
  selector: 'app-page-load-error',
  imports: [TranslatePipe],
  template: `<section role="alert" class="page-load-error">
    <h1>{{ 'pageLoad.title' | translate }}</h1>
    <p>{{ 'pageLoad.message' | translate }}</p>
    <button type="button" (click)="retry()">{{ 'common.retry' | translate }}</button>
  </section>`,
  styles: [`.page-load-error { max-width: 36rem; margin: 3rem auto; padding: 1.5rem; }
    button { padding: .75rem 1.25rem; cursor: pointer; }`],
})
export class PageLoadError {
  private readonly browser = inject(DOCUMENT).defaultView;
  private readonly route = inject(ActivatedRoute);

  retry(): void {
    const browser = this.browser;
    if (!browser) return;
    const target = internalPath(this.route.snapshot.queryParamMap.get('returnUrl') || '/roles', browser.location.origin);
    browser.location.replace(target && !target.startsWith('/load-error') ? target : '/roles');
  }
}
