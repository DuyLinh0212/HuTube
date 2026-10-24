import { DestroyRef, Directive, ElementRef, Input, inject } from '@angular/core';
import { LoginPromptService } from '../../core/login-prompt.service';

/** Capture before RouterLink and action handlers so a guest never sends a protected request. */
@Directive({ selector: '[appRequireLogin]' })
export class RequireLoginDirective {
  @Input() appRequireLogin = '';
  private readonly login = inject(LoginPromptService);

  constructor() {
    const element = inject(ElementRef<HTMLElement>).nativeElement;
    const guard = (event: Event) => {
      const target = event.target instanceof Element
        ? event.target.closest<HTMLElement>('button, a, input, textarea') ?? element : element;
      if (this.login.require(target, this.appRequireLogin)) return;
      event.preventDefault();
      event.stopImmediatePropagation();
    };
    element.addEventListener('click', guard, true);
    element.addEventListener('submit', guard, true);
    inject(DestroyRef).onDestroy(() => {
      element.removeEventListener('click', guard, true);
      element.removeEventListener('submit', guard, true);
    });
  }
}
