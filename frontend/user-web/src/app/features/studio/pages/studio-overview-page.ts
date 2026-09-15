import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { I18nService } from '../../../core/i18n.service';
import { LocaleDatePipe } from '../../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../../core/locale-number.pipe';
import { StudioDataService } from '../../../core/studio-data.service';
import { TranslatePipe } from '../../../core/translate.pipe';

@Component({
  selector: 'app-studio-overview-page',
  imports: [RouterLink, LocaleDatePipe, LocaleNumberPipe, TranslatePipe],
  templateUrl: './studio-overview-page.html',
  styleUrl: './studio-overview-page.scss',
})
export class StudioOverviewPage implements OnInit {
  readonly data = inject(StudioDataService);
  readonly i18n = inject(I18nService);

  visibilityLabel(value: string): string {
    if (value === 'public') return this.i18n.t('ui.public');
    if (value === 'unlisted') return this.i18n.t('ui.unlisted');
    return this.i18n.t('ui.private');
  }

  statusLabel(value: string | null | undefined): string {
    switch (value) {
      case 'published': return this.i18n.t('ui.statusPublished');
      case 'draft': return this.i18n.t('ui.statusDraft');
      case 'processing': return this.i18n.t('ui.statusProcessing');
      case 'scheduled': return this.i18n.t('ui.statusScheduled');
      case 'pending': return this.i18n.t('ui.statusPending');
      case 'rejected': return this.i18n.t('ui.statusRejected');
      default: return value || this.i18n.t('ui.status');
    }
  }

  ngOnInit() {
    this.data.load();
  }
}
