import { Component, DestroyRef, ElementRef, HostListener, effect, inject, input, output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Subject, catchError, debounceTime, map, of, switchMap } from 'rxjs';
import { TranslatePipe } from '../../core/translate.pipe';
import { AdminModerationService, ModerationChannelOption } from './admin-moderation.service';

@Component({
  selector: 'app-channel-picker',
  standalone: true,
  imports: [FormsModule, TranslatePipe],
  template: `
    <div class="channel-picker">
      <label [for]="id">{{ 'channelPicker.label' | translate }} <span aria-hidden="true">*</span></label>
      <input [id]="id" type="search" role="combobox" aria-autocomplete="list" autocomplete="off" spellcheck="false"
        [disabled]="disabled()" [ngModel]="query()" (ngModelChange)="search($event)" (focus)="expanded.set(true)"
        [placeholder]="'channelPicker.placeholder' | translate" [attr.aria-expanded]="expanded() && !channel()"
        [attr.aria-controls]="id + '-options'" [attr.aria-describedby]="id + '-hint'"
        [attr.aria-activedescendant]="expanded() && results().length ? id + '-option-' + activeIndex() : null"
        (keydown)="onKeydown($event)" />
      <small [id]="id + '-hint'">{{ 'channelPicker.hint' | translate }}</small>
      @if (channel(); as selected) {
        <div class="selected-channel" role="status"><strong>{{ selected.name }}</strong><span>&#64;{{ selected.handle || '—' }}</span></div>
      } @else if (expanded()) {
        <div class="channel-options" [id]="id + '-options'" role="listbox" [attr.aria-label]="'channelPicker.results' | translate">
          @if (loading()) { <p role="status">{{ 'channelPicker.loading' | translate }}</p> }
          @else if (failed()) { <p role="alert">{{ 'channelPicker.error' | translate }}</p><button type="button" (click)="search(query())">{{ 'channelPicker.retry' | translate }}</button> }
          @else {
            @for (option of results(); track option.channelId; let index = $index) {
              <button type="button" role="option" tabindex="-1" [id]="id + '-option-' + index" [attr.aria-selected]="index === activeIndex()"
                [class.active]="index === activeIndex()" (mousedown)="$event.preventDefault()" (click)="choose(option)">
                <span><strong>&#64;{{ option.handle }}</strong><small>{{ option.name }}</small></span>
                <em>{{ (option.status === 'active' ? 'channelPicker.active' : option.status === 'suspended' ? 'channelPicker.suspended' : 'channelPicker.unavailable') | translate }}</em>
              </button>
            } @empty { @if (query().trim().replace('@', '').length >= 2) { <p role="status">{{ 'channelPicker.empty' | translate }}</p> } }
          }
        </div>
      }
    </div>`,
  styles: `
    :host { display:block;min-width:0; } .channel-picker { display:grid;gap:8px;position:relative; }
    label { color:var(--ink);font-size:.84rem;font-weight:650; } label span { color:var(--danger); }
    input { width:100%;box-sizing:border-box;min-height:44px;padding:10px 12px;border:1px solid var(--line);border-radius:8px;background:var(--surface);color:var(--ink);font:inherit; }
    input:focus-visible,button:focus-visible { outline:2px solid var(--primary);outline-offset:2px; }
    small { color:var(--text-muted);font-size:.76rem;line-height:1.6; } .channel-options { display:grid;gap:4px;max-height:240px;overflow-y:auto;border-radius:8px;background:var(--surface); }
    .channel-options:has(button),.channel-options:has(p) { border:1px solid var(--line);padding:6px; }
    .channel-options button { display:flex;align-items:center;justify-content:space-between;gap:12px;min-height:48px;padding:9px 10px;border:0;border-radius:6px;background:transparent;color:var(--ink);text-align:left;font:inherit;cursor:pointer; }
    .channel-options button:hover,.channel-options button.active { background:var(--primary-soft); }.channel-options button > span { display:grid;min-width:0; }.channel-options strong { font-size:.85rem;overflow-wrap:anywhere; }.channel-options em { color:var(--text-muted);font-size:.7rem;font-style:normal; }
    .channel-options p { margin:0;padding:10px;color:var(--text-muted);font-size:.8rem;line-height:1.6; }.selected-channel { display:flex;flex-wrap:wrap;justify-content:space-between;gap:8px;padding:12px;border:1px solid var(--line);border-radius:8px;background:var(--primary-soft);font-size:.84rem; }.selected-channel span { color:var(--text-muted);overflow-wrap:anywhere; }
  `
})
export class ChannelPickerComponent {
  private static nextId = 0;
  readonly id = `moderation-channel-${++ChannelPickerComponent.nextId}`;
  readonly channel = input<ModerationChannelOption | null>(null);
  readonly disabled = input(false);
  readonly picked = output<ModerationChannelOption | null>();
  readonly query = signal('');
  readonly results = signal<ModerationChannelOption[]>([]);
  readonly loading = signal(false);
  readonly failed = signal(false);
  readonly expanded = signal(false);
  readonly activeIndex = signal(0);
  private readonly service = inject(AdminModerationService);
  private readonly element = inject(ElementRef<HTMLElement>);
  private readonly destroyRef = inject(DestroyRef);
  private readonly requests = new Subject<{ text: string; generation: number }>();
  private generation = 0;

  constructor() {
    effect(() => { const channel = this.channel(); if (channel) { this.query.set(channel.handle ? '@' + channel.handle : channel.name); this.expanded.set(false); } });
    this.requests.pipe(debounceTime(250), switchMap(request => {
      const text = request.text.trim().replace(/^@/, '');
      return text.length < 2 ? of({ items: [] as ModerationChannelOption[], generation: request.generation, failed: false })
        : this.service.lookupChannels(text).pipe(map(items => ({ items, generation: request.generation, failed: false })),
            catchError(() => of({ items: [] as ModerationChannelOption[], generation: request.generation, failed: true })));
    }), takeUntilDestroyed(this.destroyRef)).subscribe(result => {
      if (result.generation !== this.generation) return;
      this.results.set(result.items); this.failed.set(result.failed); this.loading.set(false); this.activeIndex.set(0);
    });
  }
  search(text: string): void {
    if (this.disabled()) return;
    this.picked.emit(null); this.query.set(text); this.results.set([]); this.failed.set(false); this.expanded.set(true);
    this.loading.set(text.trim().replace(/^@/, '').length >= 2);
    this.requests.next({ text, generation: ++this.generation });
  }
  choose(channel: ModerationChannelOption): void {
    if (this.disabled()) return;
    this.generation++; this.requests.next({ text: '', generation: this.generation });
    this.query.set('@' + channel.handle); this.results.set([]); this.loading.set(false); this.expanded.set(false); this.picked.emit(channel);
  }
  onKeydown(event: KeyboardEvent): void {
    if (event.key === 'Escape' && this.expanded()) { event.preventDefault(); event.stopPropagation(); this.expanded.set(false); }
    else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault(); const count = this.results().length; this.expanded.set(true);
      if (count) this.activeIndex.update(index => (index + (event.key === 'ArrowDown' ? 1 : count - 1)) % count);
    } else if (event.key === 'Enter') {
      event.preventDefault(); const option = this.expanded() ? this.results()[this.activeIndex()] : null; if (option) this.choose(option);
    }
  }
  @HostListener('document:click', ['$event'])
  outsideClick(event: MouseEvent): void { if (!this.element.nativeElement.contains(event.target as Node)) this.expanded.set(false); }
}
