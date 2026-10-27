import { Directive, ElementRef, EventEmitter, Input, OnDestroy, Output, inject } from '@angular/core';

@Directive({ selector: '[appInfiniteScroll]' })
export class InfiniteScrollDirective implements OnDestroy {
  private readonly element = inject<ElementRef<HTMLElement>>(ElementRef).nativeElement;
  private readonly observer = typeof IntersectionObserver === 'undefined' ? null : new IntersectionObserver(entries => {
    if (this.enabled && entries.some(entry => entry.isIntersecting)) {
      this.observer?.unobserve(this.element);
      this.reached.emit();
      // Cached responses may complete before Angular renders the loading state.
      // Rearm even when the bound enabled value never changed during that request.
      queueMicrotask(() => { if (this.enabled && !this.destroyed) this.observer?.observe(this.element); });
    }
  }, { rootMargin: '500px 0px' });
  private enabled = false;
  private destroyed = false;

  @Output() readonly reached = new EventEmitter<void>();
  @Input() set appInfiniteScroll(enabled: boolean) {
    this.enabled = enabled;
    if (enabled) this.observer?.observe(this.element);
    else this.observer?.unobserve(this.element);
  }

  ngOnDestroy() { this.destroyed = true; this.observer?.disconnect(); }
}
