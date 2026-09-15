import { HttpErrorResponse } from '@angular/common/http';
import { Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { ContentService, VideoCard } from '../../core/content.service';
import { I18nService } from '../../core/i18n.service';
import { LocaleDatePipe } from '../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../core/locale-number.pipe';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-home-page',
  imports: [RouterLink, LocaleDatePipe, LocaleNumberPipe, TranslatePipe],
  templateUrl: './home-page.html',
  styleUrl: './home-page.scss',
})
export class HomePage {
  private readonly content = inject(ContentService);
  private readonly i18n = inject(I18nService);

  readonly videos = signal<VideoCard[]>([]);
  readonly loading = signal(true);
  readonly error = signal('');

  constructor() {
    this.load();
  }

  load() {
    this.loading.set(true);
    this.content.feed('home', 1, 20, undefined, undefined, 'popular')
      .subscribe({
        next: value => {
          this.videos.set(value.items ?? []);
          this.error.set('');
          this.loading.set(false);
        },
        error: (reason: unknown) => {
          this.videos.set([]);
          this.error.set(
            reason instanceof HttpErrorResponse && reason.status === 404
              ? ''
              : this.i18n.t('home.error'),
          );
          this.loading.set(false);
        },
      });
  }

  duration(value: number) {
    return `${Math.floor(value / 60)}:${String(value % 60).padStart(2, '0')}`;
  }

}
