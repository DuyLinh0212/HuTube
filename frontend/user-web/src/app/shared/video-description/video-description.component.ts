import { Component, computed, input, output } from '@angular/core';

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
  template: `@for (part of parts(); track $index) {@switch (part.kind) {
    @case ('link') {<a [href]="part.href" target="_blank" rel="noopener noreferrer nofollow ugc">{{ part.text }}</a>}
    @case ('timestamp') {<button type="button" (click)="seek.emit(part.seconds)">{{ part.text }}</button>}
    @default {<span>{{ part.text }}</span>}
  }}`,
  styles: `:host { display: block; white-space: pre-wrap; overflow-wrap: anywhere; line-height: 1.75; }
    a, button { color: var(--status-info-text, #1d4ed8); text-decoration: underline; text-underline-offset: 3px; }
    button { display: inline; padding: 0; border: 0; background: transparent; font: inherit; line-height: inherit; cursor: pointer; }
    a:hover, button:hover { color: var(--ink); }
    a:focus-visible, button:focus-visible { outline: 2px solid var(--primary); outline-offset: 3px; border-radius: 2px; }`,
})
export class VideoDescriptionComponent {
  readonly text = input('');
  readonly duration = input(0);
  readonly seek = output<number>();
  readonly parts = computed(() => descriptionParts(this.text(), this.duration()));
}
