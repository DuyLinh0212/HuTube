import { Component, ElementRef, HostListener, computed, inject, signal } from '@angular/core';
import { NavigationEnd, Router, RouterLink } from '@angular/router';
import { takeUntilDestroyed, toSignal } from '@angular/core/rxjs-interop';
import { filter, map, startWith } from 'rxjs';
import { UploadStateService } from '../../core/upload-state.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-upload-progress-tray',
  imports: [RouterLink, LocaleNumberPipe, TranslatePipe],
  templateUrl: './upload-progress-tray.component.html',
  styleUrl: './upload-progress-tray.component.scss',
  host: { '[style.left.px]': 'position().x', '[style.top.px]': 'position().y' },
})
export class UploadProgressTrayComponent {
  private readonly router = inject(Router);
  private readonly routeUrl = toSignal(this.router.events.pipe(
    filter((event): event is NavigationEnd => event instanceof NavigationEnd),
    map(event => event.urlAfterRedirects), startWith(this.router.url),
  ), { initialValue: this.router.url });
  readonly isUploadPage = computed(() => this.routeUrl().split(/[?#]/)[0] === '/studio/upload');
  readonly expanded = signal(false);
  private readonly element: ElementRef<HTMLElement> = inject(ElementRef);
  readonly position = signal({ x: 0, y: 0 });
  readonly viewport = signal({ width: 0, height: 0 });
  readonly dragging = signal(false);
  readonly progress = computed(() => Math.max(0, Math.min(100, this.upload.state().progress)));
  readonly opensUp = computed(() => this.position().y > this.viewport().height / 2);
  readonly panelLeft = computed(() => Math.max(12, Math.min(this.position().x, this.viewport().width - Math.min(360, this.viewport().width - 24) - 12)) - this.position().x);
  readonly panelHeight = computed(() => this.opensUp() ? this.position().y - 24 : this.viewport().height - this.position().y - 92);
  private pointer: { id: number; x: number; y: number; startX: number; startY: number; moved: boolean } | null = null;
  private suppressClick = false;
  readonly upload = inject(UploadStateService);
  readonly i18n = inject(I18nService);

  constructor() {
    if (typeof window !== 'undefined') {
      this.viewport.set({ width: window.innerWidth, height: window.innerHeight });
      this.position.set(this.clamp(window.innerWidth - 88, window.innerHeight - (window.innerWidth <= 640 ? 168 : 96)));
    }
    this.router.events.pipe(takeUntilDestroyed()).subscribe(event => {
      if (event instanceof NavigationEnd) this.expanded.set(false);
    });
  }

  private clamp(x: number, y: number) {
    const { width, height } = this.viewport();
    const bottom = width <= 640 ? 100 : 20;
    return { x: Math.max(12, Math.min(x, width - 80)), y: Math.max(84, Math.min(y, height - 68 - bottom)) };
  }

  @HostListener('window:resize')
  resize() {
    this.viewport.set({ width: window.innerWidth, height: window.innerHeight });
    this.position.set(this.clamp(this.position().x, this.position().y));
  }

  pointerDown(event: PointerEvent) {
    if (!event.isPrimary || event.button !== 0) return;
    this.pointer = { id: event.pointerId, x: event.clientX, y: event.clientY, startX: this.position().x, startY: this.position().y, moved: false };
    this.suppressClick = false;
    (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
  }

  pointerMove(event: PointerEvent) {
    const pointer = this.pointer;
    if (!pointer || pointer.id !== event.pointerId) return;
    const dx = event.clientX - pointer.x, dy = event.clientY - pointer.y;
    if (!pointer.moved && Math.hypot(dx, dy) < 6) return;
    pointer.moved = true;
    this.dragging.set(true);
    this.expanded.set(false);
    this.position.set(this.clamp(pointer.startX + dx, pointer.startY + dy));
  }

  pointerEnd(event: PointerEvent) {
    if (this.pointer?.id !== event.pointerId) return;
    this.suppressClick = this.pointer.moved || event.type === 'pointercancel';
    this.pointer = null;
    this.dragging.set(false);
  }

  toggle(event: MouseEvent) {
    if (this.suppressClick && event.detail !== 0) { this.suppressClick = false; return; }
    this.expanded.update(value => !value);
  }

  moveWithKeyboard(event: KeyboardEvent) {
    const delta: Record<string, [number, number]> = { ArrowLeft: [-20, 0], ArrowRight: [20, 0], ArrowUp: [0, -20], ArrowDown: [0, 20] };
    if (!delta[event.key]) return;
    event.preventDefault();
    const [x, y] = delta[event.key];
    this.position.set(this.clamp(this.position().x + x, this.position().y + y));
  }

  minimize() {
    this.expanded.set(false);
    this.element.nativeElement.querySelector<HTMLButtonElement>('.upload-orb')?.focus();
  }

  @HostListener('document:pointerdown', ['$event'])
  outside(event: PointerEvent) {
    if (!this.element.nativeElement.contains(event.target as Node)) this.expanded.set(false);
  }

  @HostListener('keydown.escape', ['$event'])
  escape(event: Event) {
    if (this.expanded()) { event.stopPropagation(); this.minimize(); }
  }

  isVisible() {
    return this.upload.state().phase !== 'idle';
  }

  isActive() {
    return this.upload.state().phase === 'uploading' || this.upload.state().phase === 'processing';
  }

  label() {
    return this.upload.state().phase === 'uploading'
      ? this.i18n.t('ui.uploading')
      : this.upload.state().phase === 'processing'
        ? this.i18n.t('ui.processingVideo')
        : this.upload.state().phase === 'completed'
          ? this.i18n.t('ui.uploadSuccess')
          : this.i18n.t('ui.uploadFailed');
  }

  bytes(value: number) {
    if (value < 1024) return this.i18n.formatNumber(value, { useGrouping: false }) + ' B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    let size = value;
    let index = -1;
    do {
      size /= 1024;
      index++;
    } while (size >= 1024 && index < units.length - 1);
    return this.i18n.formatNumber(size, { maximumFractionDigits: size >= 10 ? 0 : 1 }) + ' ' + units[index];
  }
}
