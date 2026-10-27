import { Component, DestroyRef, inject, signal } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ContentService, Rendition } from '../../core/content.service';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-embed-page',
  imports: [TranslatePipe],
  template: `
    <main id="main-content" class="embed-player">
      @if (source(); as video) {
        <video controls controlsList="nodownload" disablePictureInPicture playsinline preload="metadata" [src]="video.url" [attr.aria-label]="title()"></video>
      } @else {
        <p role="status">{{ 'watch.notReady' | translate }}</p>
      }
    </main>
  `,
  styles: [`
    :host { display: block; position: fixed; inset: 0; background: #090b10; }
    .embed-player { width: 100%; height: 100%; display: grid; place-items: center; color: white; }
    video { width: 100%; height: 100%; object-fit: contain; }
  `],
})
export class EmbedPage {
  readonly source = signal<Rendition | null>(null);
  readonly title = signal('');

  constructor() {
    const route = inject(ActivatedRoute);
    const content = inject(ContentService);
    const destroy = inject(DestroyRef);
    const id = route.snapshot.paramMap.get('id');
    if (!id) return;
    content.playback(id).pipe(takeUntilDestroyed(destroy)).subscribe({
      next: playback => {
        // Private playback remains on the authenticated watch page.
        if (playback.visibility === 'private') return;
        this.title.set(playback.title);
        this.source.set(playback.renditions.reduce<Rendition | null>(
          (best, item) => !best || item.height > best.height ? item : best, null));
      },
      error: () => this.source.set(null),
    });
  }
}
