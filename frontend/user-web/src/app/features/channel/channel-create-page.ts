import { Component, ElementRef, ViewChild, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { ChannelDetail, ChannelService } from '../../core/channel.service';
import { AuthService, errorMessage } from '../../core/auth.service';

@Component({
  selector: 'app-channel-create-page',
  imports: [FormsModule, RouterLink],
  templateUrl: './channel-create-page.html',
  styleUrl: './channel-create-page.scss'
})
export class ChannelCreatePage {
  private channelService = inject(ChannelService);
  private auth = inject(AuthService);
  private router = inject(Router);

  @ViewChild('avatarInput') avatarInput?: ElementRef<HTMLInputElement>;
  @ViewChild('bannerInput') bannerInput?: ElementRef<HTMLInputElement>;

  readonly existingChannel = signal<ChannelDetail | null>(null);
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
  }

  onHandleInput() {
    clearTimeout(this.debounceTimer);
    const clean = this.handle.trim().replace(/^@/, '');
    if (!clean || clean.length < 3) {
      this.handleFeedback.set('Handle cần tối thiểu 3 ký tự.');
      this.handleValid.set(false);
      return;
    }

    this.debounceTimer = setTimeout(() => {
      this.channelService.checkHandle(clean).subscribe({
        next: res => {
          this.handleFeedback.set(res.message);
          this.handleValid.set(res.isAvailable);
        },
        error: () => {
          this.handleFeedback.set('Không thể kiểm tra handle lúc này.');
          this.handleValid.set(false);
        }
      });
    }, 350);
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
      this.error.set('Vui lòng nhập tên kênh.');
      return;
    }
    const cleanHandle = this.handle.trim().replace(/^@/, '');
    if (!cleanHandle || cleanHandle.length < 3) {
      this.error.set('Handle cần tối thiểu 3 ký tự (chữ cái, số, _, -, .).');
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
        // Upload avatar / banner if selected
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
          void this.router.navigate(['/channel', created.handle]);
        });
      },
      error: err => {
        this.busy.set(false);
        this.error.set(err?.error?.message || err?.error?.detail || 'Không thể tạo kênh. Vui lòng thử lại.');
      }
    });
  }
}
