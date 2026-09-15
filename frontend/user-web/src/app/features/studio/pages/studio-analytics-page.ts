import { Component, OnInit, inject } from '@angular/core';
import { StudioDataService } from '../../../core/studio-data.service';
import { LocaleNumberPipe } from '../../../core/locale-number.pipe';
import { TranslatePipe } from '../../../core/translate.pipe';

@Component({
  selector: 'app-studio-analytics-page',
  imports: [LocaleNumberPipe, TranslatePipe],
  templateUrl: './studio-analytics-page.html',
  styleUrl: './studio-analytics-page.scss',
})
export class StudioAnalyticsPage implements OnInit {
  readonly data = inject(StudioDataService);

  ngOnInit() {
    this.data.load();
  }
}
