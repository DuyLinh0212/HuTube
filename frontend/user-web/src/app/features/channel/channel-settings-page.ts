import { Component, ElementRef, ViewChild, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';
import { ChannelDetail, ChannelService } from '../../core/channel.service';
import { errorMessage } from '../../core/auth.service';

type SettingsTab = 'basic' | 'branding' | 'danger';

@Component({
  selector: 'app-channel-settings-page',
  imports: [FormsModule, RouterLink],
  templateUrl: './channel-settings-page.html',
  styleUrl: './channel-settings-page.scss'
})
export class ChannelSettingsPage {
  private route = inject(ActivatedRoute);
  private channelService = inject(ChannelService);
  private router = inject(Router);

  @ViewChild('avatarInput') avatarInput?: ElementRef<HTMLInputElement>;
  @ViewChild('bannerInput') bannerInput?: ElementRef<HTMLInputElement>;

  readonly channel = signal<ChannelDetail | null>(null);
  readonly activeTab = signal<SettingsTab>('basic');
  readonly loading = signal(true);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly message = signal('');

  // Form bindings
  name = '';
  handle = '';
  description = '';
  contactEmail = '';
  watermarkUrl = '';

  // Delete channel confirmation
  confirmChannelName = '';
  showDeleteModal = signal(false);

  constructor() {
    this.loadChannel();
  }

  loadChannel() {
    this.loading.set(true);
    this.channelService.getMyChannel().pipe(finalize(() => this.loading.set(false))).subscribe({
      next: ch => {
        this.channel.set(ch);
        this.name = ch.name;
        this.handle = ch.handle;
        this.description = ch.description ?? '';
        this.contactEmail = ch.contactEmail ?? '';
        this.watermarkUrl = ch.watermarkUrl ?? '';
      },
      error: err => this.error.set(errorMessage(err) || 'Không thể tải thông tin kênh.')
    });
  }

  setTab(tab: SettingsTab) {
    this.activeTab.set(tab);
    this.error.set('');
    this.message.set('');
  }

  onSaveBasicInfo() {
    const ch = this.channel();
    if (!ch || this.busy()) return;

    if (!this.name.trim()) {
      this.error.set('Tên kênh không được để trống.');
      return;
    }
    const cleanHandle = this.handle.trim().replace(/^@/, '');
    if (!cleanHandle || cleanHandle.length < 3) {
      this.error.set('Handle cần từ 3 đến 50 ký tự.');
      return;
    }

    this.busy.set(true);
    this.error.set('');
    this.message.set('');

    this.channelService.updateChannel(ch.channelId, {
      name: this.name.trim(),
      handle: cleanHandle,
      description: this.description.trim() || undefined,
      contactEmail: this.contactEmail.trim() || undefined,
      watermarkUrl: this.watermarkUrl.trim() || undefined
    }).pipe(finalize(() => this.busy.set(false))).subscribe({
      next: updated => {
        this.message.set('Đã cập nhật thông tin kênh thành công.');
        this.loadChannel();
      },
      error: err => this.error.set(errorMessage(err))
    });
  }

  onAvatarSelected(event: Event) {
    const ch = this.channel();
    const input = event.target as HTMLInputElement;
    if (!ch || !input.files || input.files.length === 0) return;

    this.busy.set(true);
    this.error.set('');
    this.channelService.uploadAvatar(ch.channelId, input.files[0]).pipe(
      finalize(() => this.busy.set(false))
    ).subscribe({
      next: () => {
        this.message.set('Đã cập nhật ảnh đại diện kênh.');
        this.loadChannel();
      },
      error: err => this.error.set(errorMessage(err))
    });
  }

  onBannerSelected(event: Event) {
    const ch = this.channel();
    const input = event.target as HTMLInputElement;
    if (!ch || !input.files || input.files.length === 0) return;

    this.busy.set(true);
    this.error.set('');
    this.channelService.uploadBanner(ch.channelId, input.files[0]).pipe(
      finalize(() => this.busy.set(false))
    ).subscribe({
      next: () => {
        this.message.set('Đã cập nhật ảnh bìa kênh.');
        this.loadChannel();
      },
      error: err => this.error.set(errorMessage(err))
    });
  }

  onConfirmDeleteChannel() {
    const ch = this.channel();
    if (!ch || this.busy()) return;

    if (this.confirmChannelName.trim() !== ch.name.trim()) {
      this.error.set('Tên kênh xác nhận chưa khớp chính xác.');
      return;
    }

    this.busy.set(true);
    this.error.set('');
    this.channelService.deleteChannel(ch.channelId).pipe(
      finalize(() => this.busy.set(false))
    ).subscribe({
      next: () => {
        this.showDeleteModal.set(false);
        void this.router.navigate(['/account']);
      },
      error: err => this.error.set(errorMessage(err))
    });
  }
}
