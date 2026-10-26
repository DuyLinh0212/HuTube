import { Component, DestroyRef, ElementRef, EventEmitter, HostListener, Input, Output, ViewChild, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { ChannelDetail } from '../../core/channel.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';

@Component({
  selector: 'app-collaboration-channel-picker',
  imports: [FormsModule, RouterLink, LocaleNumberPipe],
  templateUrl: './collaboration-channel-picker.component.html',
  styleUrl: './collaboration-channel-picker.component.scss',
})
export class CollaborationChannelPickerComponent {
  readonly i18n = inject(I18nService);
  @Input({ required: true }) set channels(value: ChannelDetail[]) { this.items.set(value); }
  @Output() readonly channelOpened = new EventEmitter<void>();
  @ViewChild('picker') private picker?: ElementRef<HTMLElement>;
  @ViewChild('trigger') private trigger?: ElementRef<HTMLButtonElement>;
  readonly items = signal<ChannelDetail[]>([]);
  readonly query = signal('');
  readonly open = signal(false);
  readonly position = signal({ left: 0, top: 0, width: 0, maxHeight: 350, above: false });
  // The on-screen keyboard resizes the visual viewport without dismissing the picker.
  private readonly resizePicker = () => this.reposition();
  readonly filtered = computed(() => {
    const normalize = (value: string) => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/đ/gi, 'd').toLowerCase();
    const query = normalize(this.query().trim()).replace(/^@/, '');
    return this.items().filter(channel => !query || normalize(channel.name + ' ' + channel.handle).includes(query));
  });

  constructor() {
    const viewport = window.visualViewport;
    viewport?.addEventListener('resize', this.resizePicker);
    inject(DestroyRef).onDestroy(() => viewport?.removeEventListener('resize', this.resizePicker));
  }

  tx(vi: string, en: string): string { return this.i18n.currentLang() === 'vi' ? vi : en; }
  role(value: string | null): string {
    return value && ['manager', 'editor', 'moderator', 'viewer'].includes(value)
      ? this.i18n.t('channel.role' + value[0].toUpperCase() + value.slice(1)) : this.i18n.t('studio.roleContributor');
  }

  positionPicker(event: Event) {
    const open = (event as ToggleEvent).newState === 'open';
    this.open.set(open);
    if (!open) { this.query.set(''); return; }
    this.reposition();
  }

  @HostListener('window:resize')
  reposition() {
    if (!this.open()) return;
    const rect = this.trigger?.nativeElement.getBoundingClientRect();
    if (!rect) return;
    const viewport = window.visualViewport;
    const viewportTop = viewport?.offsetTop ?? 0;
    const below = viewportTop + (viewport?.height ?? window.innerHeight) - rect.bottom - 16;
    const above = rect.top - viewportTop - 16;
    const flip = below < 220 && above > below;
    this.position.set({ left: rect.left, top: flip ? rect.top - 8 : rect.bottom + 8,
      width: rect.width, maxHeight: Math.max(80, Math.min(350, flip ? above : below)), above: flip });
  }

  close() {
    if (this.picker?.nativeElement.matches(':popover-open')) this.picker.nativeElement.hidePopover();
    this.open.set(false);
    this.query.set('');
  }

  escape(event: Event) {
    event.preventDefault(); event.stopPropagation();
    this.close(); this.trigger?.nativeElement.focus();
  }

  navigate() { this.close(); this.channelOpened.emit(); }
}
