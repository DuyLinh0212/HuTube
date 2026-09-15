import { Component, EventEmitter, Input, Output, inject } from '@angular/core';
import { Router, RouterLink, RouterLinkActive } from '@angular/router';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';
import { StudioDataService } from '../../core/studio-data.service';

@Component({
  selector: 'app-studio-sidebar',
  imports: [RouterLink, RouterLinkActive, TranslatePipe],
  templateUrl: './studio-sidebar.component.html',
  styleUrl: './studio-sidebar.component.scss'
})
export class StudioSidebarComponent {
  readonly i18n = inject(I18nService);
  readonly data = inject(StudioDataService);
  private router = inject(Router);

  @Input() open = false;
  @Input({ required: true }) collapsed = false;
  @Output() readonly collapsedChange = new EventEmitter<boolean>();
  @Output() readonly navigationClosed = new EventEmitter<void>();

  toggleCollapsed() { this.collapsedChange.emit(!this.collapsed); }
  closeNavigation() { this.navigationClosed.emit(); }
}
