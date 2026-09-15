import { Component, ElementRef, Input, ViewChild, inject, signal } from '@angular/core';
import { COMPOSITION_BUFFER_MODE, FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { ChannelDetail, ChannelInvitation, ChannelService } from '../../core/channel.service';
import { AuthService, errorMessage } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-channel-create-page',
  imports: [FormsModule, RouterLink, TranslatePipe],
  providers: [
    { provide: COMPOSITION_BUFFER_MODE, useValue: false }
  ],
  templateUrl: './channel-create-page.html',
  styleUrl: './channel-create-page.scss'
})
export class ChannelCreatePage {
  @Input() studioMode = false;
  private channelService = inject(ChannelService);
  private auth = inject(AuthService);
  private router = inject(Router);
  private readonly i18n = inject(I18nService);

  @ViewChild('avatarInput') avatarInput?: ElementRef<HTMLInputElement>;
  @ViewChild('bannerInput') bannerInput?: ElementRef<HTMLInputElement>;

  readonly existingChannel = signal<ChannelDetail | null>(null);
  readonly pendingInvitations = signal<ChannelInvitation[]>([]);
  readonly loading = signal(true);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly handleFeedback = signal('');
  readonly handleValid = signal<boolean | null>(null);

  name = '';
  handle = '';
  description = '';
  contactEmail = '';
  avatarPreview = '';
  bannerPreview = '';

  private avatarFile?: File;
  private bannerFile?: File;
  private debounceTimer?: any;

  constructor() {
    this.checkExisting();
  }

  checkExisting() {
    this.loading.set(true);
    this.channelService.getMyChannel().pipe(finalize(() => this.loading.set(false))).subscribe({
      next: ch => this.existingChannel.set(ch),
      error: () => this.existingChannel.set(null)
    });
    this.channelService.getMyInvitations().subscribe({
      next: invitations => this.pendingInvitations.set(invitations),
      error: () => this.pendingInvitations.set([])
    });
  }

  onHandleInput(eventOrVal?: Event | string) {
    let raw = '';
    if (typeof eventOrVal === 'string') {
      raw = eventOrVal;
    } else if (eventOrVal && (eventOrVal.target as HTMLInputElement)?.value !== undefined) {
      raw = (eventOrVal.target as HTMLInputElement).value;
    } else {
      raw = this.handle || '';
    }

    this.handle = raw;
    clearTimeout(this.debounceTimer);

    const clean = raw.trim().replace(/^@+/, '').trim();
    if (!clean) {
      this.handleFeedback.set('');
      this.handleValid.set(null);
      return;
    }

    if (clean.length < 3) {
      this.handleFeedback.set(this.i18n.t('channel.handleMinCreate'));
      this.handleValid.set(false);
      return;
    }

    if (clean.length > 50) {
      this.handleFeedback.set(this.i18n.t('channel.handleMaxCreate'));
      this.handleValid.set(false);
      return;
    }

    if (/\s/.test(clean)) {
      this.handleFeedback.set(this.i18n.t('channel.handleNoSpaces'));
      this.handleValid.set(false);
      return;
    }

    if (!/^[A-Za-z0-9_.-]+$/.test(clean)) {
      this.handleFeedback.set(this.i18n.t('channel.handleChars'));
      this.handleValid.set(false);
      return;
    }

    // Format is valid -> clear error immediately so user is not blocked
    this.handleFeedback.set(this.i18n.t('channel.handleChecking'));
    this.handleValid.set(null);

    this.debounceTimer = setTimeout(() => {
      this.channelService.checkHandle(clean).subscribe({
        next: res => {
          const currentClean = (this.handle || '').trim().replace(/^@+/, '').trim();
          if (currentClean === clean) {
            this.handleFeedback.set(this.i18n.t(res.isAvailable ? 'channel.handleAvailable' : 'channel.handleTaken'));
            this.handleValid.set(res.isAvailable);
          }
        },
        error: () => {
          const currentClean = (this.handle || '').trim().replace(/^@+/, '').trim();
          if (currentClean === clean) {
            this.handleFeedback.set(this.i18n.t('channel.handleCheckError'));
            this.handleValid.set(false);
          }
        }
      });
    }, 250);
  }

  onHandleBlur(event?: Event) {
    this.onHandleInput(event);
    const clean = (this.handle || '').trim().replace(/^@+/, '').trim();
    if (this.handle !== clean) {
      this.handle = clean;
    }
  }

  onAvatarSelected(event: Event) {
    const input = event.target as HTMLInputElement;
    if (input.files && input.files[0]) {
      this.avatarFile = input.files[0];
      const reader = new FileReader();
      reader.onload = e => this.avatarPreview = e.target?.result as string;
      reader.readAsDataURL(this.avatarFile);
    }
  }

  onBannerSelected(event: Event) {
    const input = event.target as HTMLInputElement;
    if (input.files && input.files[0]) {
      this.bannerFile = input.files[0];
      const reader = new FileReader();
      reader.onload = e => this.bannerPreview = e.target?.result as string;
      reader.readAsDataURL(this.bannerFile);
    }
  }

  onSubmit() {
    if (this.busy()) return;

    if (!this.name.trim()) {
      this.error.set(this.i18n.t('channel.nameError'));
      return;
    }
    const cleanHandle = this.handle.trim().replace(/^@+/, '').trim();
    if (!cleanHandle || cleanHandle.length < 3) {
      this.error.set(this.i18n.t('channel.handleMinError'));
      return;
    }

    if (!/^[A-Za-z0-9_.-]+$/.test(cleanHandle)) {
      this.error.set(this.i18n.t('channel.handleCharsError'));
      return;
    }

    if (this.handleValid() === false) {
      this.error.set(this.handleFeedback() || this.i18n.t('channel.handleInvalidError'));
      return;
    }

    this.busy.set(true);
    this.error.set('');

    this.channelService.createChannel({
      name: this.name.trim(),
      handle: cleanHandle,
      description: this.description.trim() || undefined,
      contactEmail: this.contactEmail.trim() || undefined
    }).subscribe({
      next: created => {
        const uploadQueue: Promise<unknown>[] = [];
        if (this.avatarFile) {
          uploadQueue.push(new Promise(resolve => {
            this.channelService.uploadAvatar(created.channelId, this.avatarFile!).subscribe({
              next: () => resolve(true),
              error: () => resolve(false)
            });
          }));
        }
        if (this.bannerFile) {
          uploadQueue.push(new Promise(resolve => {
            this.channelService.uploadBanner(created.channelId, this.bannerFile!).subscribe({
              next: () => resolve(true),
              error: () => resolve(false)
            });
          }));
        }

        Promise.all(uploadQueue).then(() => {
          this.busy.set(false);
          void this.router.navigate(this.studioMode ? ['/studio/overview'] : ['/channel', created.handle]);
        });
      },
      error: err => {
        this.busy.set(false);
        this.error.set(errorMessage(err, this.i18n) || this.i18n.t('channel.createError'));
      }
    });
  }
}
