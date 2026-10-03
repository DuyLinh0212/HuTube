import { Component, EventEmitter, Input, Output, inject } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { TranslatePipe } from '../../core/translate.pipe';
import { StudioDataService } from '../../core/studio-data.service';

@Component({
  selector: 'app-studio-sidebar',
  imports: [RouterLink, RouterLinkActive, TranslatePipe],
  templateUrl: './studio-sidebar.component.html',
  styleUrl: './studio-sidebar.component.scss'
})
export class StudioSidebarComponent {
  readonly data = inject(StudioDataService);

  @Input() open = false;
  @Input({ required: true }) collapsed = false;
  @Output() readonly navigationClosed = new EventEmitter<void>();

  closeNavigation() { this.navigationClosed.emit(); }
}
