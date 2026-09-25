import {
  Component,
  ElementRef,
  EventEmitter,
  HostListener,
  Input,
  Output,
  signal
} from '@angular/core';
import { CommonModule } from '@angular/common';

export interface CustomSelectOption {
  value: string;
  label: string;
}

@Component({
  selector: 'app-custom-select',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="custom-select-wrap" [class.is-open]="isOpen()">
      <button
        type="button"
        class="custom-select-trigger"
        [class.is-open]="isOpen()"
        [class.is-filtered]="value !== 'all' && value !== ''"
        (click)="toggle($event)"
        [attr.aria-expanded]="isOpen()"
      >
        @if (prefix) {
          <span class="prefix-label">{{ prefix }}:</span>
        }
        <span class="value-label">{{ selectedLabel() }}</span>
        <svg
          class="chevron-icon"
          [class.is-rotated]="isOpen()"
          viewBox="0 0 20 20"
          fill="currentColor"
        >
          <path
            fill-rule="evenodd"
            d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z"
            clip-rule="evenodd"
          />
        </svg>
      </button>

      @if (isOpen()) {
        <div class="custom-select-menu" [class.align-right]="alignRight()" (click)="$event.stopPropagation()">
          <ul class="options-list" role="listbox">
            @for (opt of options; track opt.value) {
              <li
                class="option-item"
                [class.is-selected]="opt.value === value"
                (click)="onSelect(opt)"
                role="option"
                [attr.aria-selected]="opt.value === value"
              >
                <span class="option-label">{{ opt.label }}</span>
                @if (opt.value === value) {
                  <svg class="check-icon" viewBox="0 0 20 20" fill="currentColor">
                    <path
                      fill-rule="evenodd"
                      d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                      clip-rule="evenodd"
                    />
                  </svg>
                }
              </li>
            }
          </ul>
        </div>
      }
    </div>
  `,
  styleUrl: './custom-select.component.scss'
})
export class CustomSelectComponent {
  @Input() prefix = '';
  @Input() options: CustomSelectOption[] = [];
  @Input() value: string = 'all';
  @Output() valueChange = new EventEmitter<string>();

  readonly isOpen = signal(false);
  readonly alignRight = signal(false);

  constructor(private readonly elementRef: ElementRef) {}

  selectedLabel(): string {
    const found = this.options.find(o => o.value === this.value);
    return found ? found.label : (this.options[0]?.label ?? 'Tất cả');
  }

  toggle(event: MouseEvent): void {
    event.stopPropagation();
    const nextState = !this.isOpen();
    if (nextState) {
      const rect = this.elementRef.nativeElement.getBoundingClientRect();
      this.alignRight.set(window.innerWidth - rect.left < 260);
    }
    this.isOpen.set(nextState);
  }

  onSelect(opt: CustomSelectOption): void {
    this.value = opt.value;
    this.valueChange.emit(opt.value);
    this.isOpen.set(false);
  }

  @HostListener('document:click', ['$event'])
  onClickOutside(event: MouseEvent): void {
    if (!this.elementRef.nativeElement.contains(event.target)) {
      this.isOpen.set(false);
    }
  }

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.isOpen.set(false);
  }
}
