import { Component, ElementRef, afterRenderEffect, computed, effect, input, output, signal, viewChild } from '@angular/core';
import { TranslatePipe } from '../../core/translate.pipe';

type DescriptionPart = { text: string; kind: 'text' } | { text: string; kind: 'link'; href: string }
  | { text: string; kind: 'timestamp'; seconds: number };

/** Tokenize plain text rather than interpreting user supplied HTML. */
export function descriptionParts(text: string, duration = 0): DescriptionPart[] {
  const parts: DescriptionPart[] = [];
  const pattern = /https?:\/\/[^\s<>]+|www\.[^\s<>]+|(?<![\w:])(?:\d{1,3}:)?\d{1,3}:[0-5]\d(?![\w:])/gi;
  let cursor = 0;
  for (const match of text.matchAll(pattern)) {
    const index = match.index!;
    if (index > cursor) parts.push({ kind: 'text', text: text.slice(cursor, index) });
    const value = match[0];
    if (/^(?:https?:\/\/|www\.)/i.test(value)) {
      let link = value.replace(/[.,!?;:]+$/, '');
      // Keep balanced parentheses in URLs but exclude punctuation around them.
      while (link.endsWith(')') && (link.match(/\)/g)?.length ?? 0) > (link.match(/\(/g)?.length ?? 0)) link = link.slice(0, -1);
      try {
        const url = new URL(/^www\./i.test(link) ? `https://${link}` : link);
        parts.push({ kind: 'link', text: link, href: url.href });
        if (link.length < value.length) parts.push({ kind: 'text', text: value.slice(link.length) });
      } catch { parts.push({ kind: 'text', text: value }); }
    } else {
      const units = value.split(':').map(Number);
      const seconds = units.reduce((total, unit) => total * 60 + unit, 0);
      const valid = (units.length === 2 || units[1] < 60) && (!duration || seconds <= duration);
      parts.push(valid ? { kind: 'timestamp', text: value, seconds } : { kind: 'text', text: value });
    }
    cursor = index + value.length;
  }
  if (cursor < text.length) parts.push({ kind: 'text', text: text.slice(cursor) });
  return parts;
}

@Component({
  selector: 'app-video-description',
  imports: [TranslatePipe],
  template: `<div #content class="description-content" [class.is-collapsed]="!expanded()" [id]="contentId" (focusin)="revealFocusedLink($event)">
    @for (part of parts(); track $index) {@switch (part.kind) {
    @case ('link') {<a [href]="part.href" target="_blank" rel="noopener noreferrer nofollow ugc">{{ part.text }}</a>}
    @case ('timestamp') {<button type="button" (click)="seek.emit(part.seconds)">{{ part.text }}</button>}
    @default {<span>{{ part.text }}</span>}
  }}</div>
    @if (overflows()) {
      <button type="button" class="description-toggle" [attr.aria-expanded]="expanded()" [attr.aria-controls]="contentId" (click)="toggle($event)">{{ (expanded() ? 'watch.descriptionLess' : 'watch.descriptionMore') | translate }}</button>
    }`,
  styles: `:host { display: block; min-width: 0; line-height: 1.65; }
    .description-content { white-space: pre-wrap; overflow-wrap: anywhere; line-height: 1.65; }
    .is-collapsed { display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 3; line-clamp: 3; max-height: 4.95em; overflow: hidden; }
    a, button { color: var(--status-info-text, #1d4ed8); text-decoration: underline; text-underline-offset: 3px; }
    button { display: inline; padding: 0; border: 0; background: transparent; font: inherit; line-height: inherit; cursor: pointer; }
    a:hover, button:hover { color: var(--ink); }
    a:focus-visible, button:focus-visible { outline: 2px solid var(--primary); outline-offset: 3px; border-radius: 2px; }
    .description-toggle { display: block; min-height: 44px; margin-top: 4px; padding: 8px 0; color: var(--ink); font-weight: 700; text-decoration: none; text-align: start; }
    .description-toggle:hover { text-decoration: underline; }`,
})
export class VideoDescriptionComponent {
  private static nextId = 0;
  readonly contentId = `video-description-${++VideoDescriptionComponent.nextId}`;
  private readonly content = viewChild<ElementRef<HTMLElement>>('content');
  readonly text = input('');
  readonly resetKey = input('');
  readonly duration = input(0);
  readonly seek = output<number>();
  readonly parts = computed(() => descriptionParts(this.text(), this.duration()));
  readonly expanded = signal(false);
  readonly overflows = signal(false);

  constructor() {
    effect(() => { this.text(); this.resetKey(); this.expanded.set(false); });
    afterRenderEffect(cleanup => {
      this.text(); this.expanded(); this.duration();
      const element = this.content()?.nativeElement;
      if (!element) return;
      const measure = () => {
        const lineHeight = parseFloat(getComputedStyle(element).lineHeight);
        this.overflows.set(element.scrollHeight > lineHeight * 3 + 1);
      };
      measure();
      const observer = new ResizeObserver(measure);
      observer.observe(element);
      let alive = true;
      void document.fonts.ready.then(() => { if (alive) measure(); });
      document.fonts.addEventListener('loadingdone', measure);
      cleanup(() => {
        alive = false;
        observer.disconnect();
        document.fonts.removeEventListener('loadingdone', measure);
      });
    });
  }

  toggle(event: MouseEvent) {
    const collapsing = this.expanded();
    const button = event.currentTarget as HTMLElement;
    this.expanded.set(!collapsing);
    if (collapsing) requestAnimationFrame(() => button.scrollIntoView({ block: 'nearest' }));
  }

  // Keyboard navigation must reveal a clipped link rather than leave focus hidden.
  revealFocusedLink(event: FocusEvent) {
    const element = this.content()?.nativeElement;
    const target = event.target as HTMLElement;
    if (element && !this.expanded() && (target.getBoundingClientRect().bottom > element.getBoundingClientRect().bottom + 1 || element.scrollTop > 0)) {
      this.expanded.set(true);
      element.scrollTop = 0;
    }
  }
}
