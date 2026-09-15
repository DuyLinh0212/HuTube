import { CommonModule } from '@angular/common';
import { Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { ContentService, VideoDetail } from '../../../core/content.service';
import { StudioDataService } from '../../../core/studio-data.service';
import { I18nService } from '../../../core/i18n.service';
import { LocaleDatePipe } from '../../../core/locale-date.pipe';
import { LocaleNumberPipe } from '../../../core/locale-number.pipe';
import { TranslatePipe } from '../../../core/translate.pipe';

@Component({
  selector: 'app-studio-content-page',
  standalone: true,
  imports: [CommonModule, RouterLink, LocaleDatePipe, LocaleNumberPipe, TranslatePipe],
  templateUrl: './studio-content-page.html',
  styleUrl: './studio-content-page.scss',
})
export class StudioContentPage implements OnInit {
  readonly data = inject(StudioDataService);
  readonly content = inject(ContentService);
  readonly search = signal('');
  readonly updatingId = signal<string | null>(null);
  readonly toastMessage = signal('');
  readonly i18n = inject(I18nService);

  ngOnInit() {
    this.data.load();
  }

  filtered() {
    const query = this.search().toLowerCase();
    return this.data.videos().filter(video => video.title.toLowerCase().includes(query));
  }

  changeVisibility(video: VideoDetail, newVisibility: string) {
    if (!this.data.hasPermission('video.edit') || newVisibility === video.visibility) return;

    this.updatingId.set(video.videoId);
    this.content.update(video.videoId, { visibility: newVisibility }).subscribe({
      next: updated => {
        video.visibility = updated.visibility || newVisibility;
        video.moderationStatus = updated.moderationStatus;
        video.status = updated.status;
        this.updatingId.set(null);

        if (newVisibility === 'public' && updated.moderationStatus !== 'approved') {
          this.toastMessage.set(this.i18n.t('studio.publicModerationToast', { title: video.title }));
        } else if (newVisibility === 'public') {
          this.toastMessage.set(this.i18n.t('studio.publicToast', { title: video.title }));
        } else if (newVisibility === 'unlisted') {
          this.toastMessage.set(this.i18n.t('studio.unlistedToast', { title: video.title }));
        } else {
          this.toastMessage.set(this.i18n.t('studio.privateToast', { title: video.title }));
        }

        setTimeout(() => this.toastMessage.set(''), 5000);
      },
      error: () => {
        this.updatingId.set(null);
        this.toastMessage.set(this.i18n.t('studio.visibilityError'));
        setTimeout(() => this.toastMessage.set(''), 5000);
      },
    });
  }

  visibilityLabel(value: string): string {
    if (value === 'public') return this.i18n.t('ui.public');
    if (value === 'unlisted') return this.i18n.t('ui.unlisted');
    return this.i18n.t('ui.private');
  }

  moderationLabel(value: string | null | undefined, video: VideoDetail): string {
    if (value === 'approved' || (video.status === 'published' && video.visibility === 'public')) return this.i18n.t('ui.moderationApproved');
    if (value === 'pending' || video.visibility === 'public') return this.i18n.t('ui.moderationPending');
    if (value === 'reviewing') return this.i18n.t('ui.moderationReviewing');
    if (value === 'rejected') return this.i18n.t('ui.moderationRejected');
    return this.i18n.t('ui.moderationNotSubmitted');
  }
}
