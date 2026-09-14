import { Component, ElementRef, OnInit, ViewChild, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { AuthService, errorMessage } from '../../core/auth.service';
import { AccountService, UserProfile } from '../../core/account.service';
import { ChannelDetail, ChannelService } from '../../core/channel.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';
import { finalize } from 'rxjs';

export interface ProfileGenre {
  id: string;
  nameKey: string;
  icon: string;
  color: string;
  bg: string;
  selected: boolean;
}

@Component({
  selector: 'app-profile-page',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, TranslatePipe],
  templateUrl: './profile-page.html',
  styleUrl: './profile-page.scss'
})
export class ProfilePage implements OnInit {
  readonly auth = inject(AuthService);
  readonly account = inject(AccountService);
  readonly channelService = inject(ChannelService);
  readonly i18n = inject(I18nService);

  @ViewChild('avatarInput') avatarInput?: ElementRef<HTMLInputElement>;

  readonly profile = signal<UserProfile | null>(null);
  readonly myChannel = signal<ChannelDetail | null>(null);
  readonly savingProfile = signal(false);
  readonly message = signal('');
  readonly error = signal('');

  readonly editingProfile = signal(false);
  readonly aboutModalOpen = signal(false);

  // Edit form model
  editDisplayName = '';
  editBio = '';

  // Favorite genres (User explicitly preserved emojis here)
  readonly genres = signal<ProfileGenre[]>([
    { id: 'travel', nameKey: 'profile.genre.travel', icon: '✈️', color: '#0ea5e9', bg: 'rgba(14, 165, 233, 0.1)', selected: true },
    { id: 'food', nameKey: 'profile.genre.food', icon: '🍜', color: '#f43f5e', bg: 'rgba(244, 63, 94, 0.1)', selected: true },
    { id: 'music', nameKey: 'profile.genre.music', icon: '🎵', color: '#8b5cf6', bg: 'rgba(139, 92, 246, 0.1)', selected: true },
    { id: 'film', nameKey: 'profile.genre.film', icon: '🎬', color: '#a855f7', bg: 'rgba(168, 85, 247, 0.1)', selected: true },
    { id: 'education', nameKey: 'profile.genre.education', icon: '🎓', color: '#3b82f6', bg: 'rgba(59, 130, 246, 0.1)', selected: true },
    { id: 'tech', nameKey: 'profile.genre.tech', icon: '💻', color: '#475569', bg: 'rgba(71, 85, 105, 0.1)', selected: true },
    { id: 'lifestyle', nameKey: 'profile.genre.lifestyle', icon: '🍃', color: '#10b981', bg: 'rgba(16, 185, 129, 0.1)', selected: true },
    { id: 'health', nameKey: 'profile.genre.health', icon: '💖', color: '#ec4899', bg: 'rgba(236, 72, 153, 0.1)', selected: true },
    { id: 'other', nameKey: 'profile.genre.other', icon: '•••', color: '#64748b', bg: 'rgba(100, 116, 139, 0.1)', selected: false }
  ]);

  // Full joined date string matching Image 2 (e.g. "Đã tham gia 25 thg 2, 2018")
  readonly fullJoinedDate = computed(() => {
    const p = this.profile();
    if (!p?.createdAt) {
      const d = new Date();
      return `${this.i18n.currentLang() === 'vi' ? 'Đã tham gia' : 'Joined'} ${d.getDate()} thg ${d.getMonth() + 1}, ${d.getFullYear()}`;
    }
    const d = new Date(p.createdAt);
    return `${this.i18n.currentLang() === 'vi' ? 'Đã tham gia' : 'Joined'} ${d.getDate()} thg ${d.getMonth() + 1}, ${d.getFullYear()}`;
  });

  // Profile URL string matching Image 2 (e.g. "www.youtube.com/@danhcongngo6005")
  readonly profileUrlDisplay = computed(() => {
    const handle = this.profile()?.username || this.myChannel()?.handle || 'ncdanh';
    const host = typeof window !== 'undefined' && window.location.host ? window.location.host : 'www.hutube.com';
    return `${host}/@${handle}`;
  });

  ngOnInit() {
    this.loadData();
  }

  loadData() {
    this.account.getProfile().subscribe({
      next: p => {
        this.profile.set(p);
        this.editDisplayName = p.displayName;
        this.editBio = p.bio || '';
      },
      error: () => {}
    });

    this.channelService.getMyChannel().subscribe({
      next: ch => this.myChannel.set(ch),
      error: () => this.myChannel.set(null)
    });
  }

  toggleGenre(genreId: string) {
    this.genres.update(items =>
      items.map(g => g.id === genreId ? { ...g, selected: !g.selected } : g)
    );
  }

  openEditProfile() {
    const p = this.profile();
    this.editDisplayName = p?.displayName || this.auth.user()?.displayName || '';
    this.editBio = p?.bio || '';
    this.editingProfile.set(true);
  }

  closeEditProfile() {
    this.editingProfile.set(false);
  }

  openAboutModal() {
    this.aboutModalOpen.set(true);
  }

  closeAboutModal() {
    this.aboutModalOpen.set(false);
  }

  shareProfile() {
    const url = typeof window !== 'undefined'
      ? `${window.location.origin}/@${this.profile()?.username || this.myChannel()?.handle || 'ncdanh'}`
      : '';
    if (navigator.clipboard && url) {
      void navigator.clipboard.writeText(url).then(() => {
        this.message.set(this.i18n.t('profile.copiedLink'));
        setTimeout(() => this.message.set(''), 3000);
      });
    } else {
      this.message.set(this.i18n.t('profile.copiedLink'));
      setTimeout(() => this.message.set(''), 3000);
    }
  }

  saveProfile() {
    if (this.savingProfile()) return;
    this.savingProfile.set(true);
    this.error.set('');

    this.account.updateProfile({
      displayName: this.editDisplayName.trim(),
      bio: this.editBio.trim()
    }).pipe(finalize(() => this.savingProfile.set(false))).subscribe({
      next: updated => {
        this.profile.set(updated);
        this.editingProfile.set(false);
        this.message.set(this.i18n.t('account.profileSaved'));
        setTimeout(() => this.message.set(''), 3000);
      },
      error: err => this.error.set(errorMessage(err))
    });
  }

  triggerAvatarUpload() {
    this.avatarInput?.nativeElement.click();
  }

  onAvatarSelected(event: Event) {
    const input = event.target as HTMLInputElement;
    if (!input.files || input.files.length === 0) return;

    const file = input.files[0];
    if (file.size > 5 * 1024 * 1024) {
      this.error.set(this.i18n.t('account.avatarSizeError'));
      return;
    }

    this.account.uploadAvatar(file).subscribe({
      next: updated => {
        this.profile.set(updated);
        this.message.set(this.i18n.t('account.avatarUpdated'));
        setTimeout(() => this.message.set(''), 3000);
      },
      error: err => this.error.set(errorMessage(err))
    });
  }

}
