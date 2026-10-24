import { ResultNoticeComponent } from '@dalitu/ui/result-notice.component';
import { Component, effect, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AccountService } from '../../../core/account.service';
import { ChannelService } from '../../../core/channel.service';
import { I18nService } from '../../../core/i18n.service';
import { StudioDataService } from '../../../core/studio-data.service';
import { ThemeService } from '../../../core/theme.service';
import { TranslatePipe } from '../../../core/translate.pipe';

@Component({
  selector: 'app-studio-settings-page',
  imports: [ResultNoticeComponent, FormsModule, TranslatePipe],
  templateUrl: './studio-settings-page.html',
  styleUrl: './studio-settings-page.scss',
})
export class StudioSettingsPage {
  private readonly channels = inject(ChannelService);
  private readonly account = inject(AccountService);
  readonly data = inject(StudioDataService);
  readonly theme = inject(ThemeService);
  readonly i18n = inject(I18nService);
  readonly message = signal('');
  readonly error = signal('');
  private id = '';
  name = '';
  description = '';
  contactEmail = '';

  constructor() {
    this.data.load(undefined, false);
    effect(() => {
      const channel = this.data.channel();
      if (channel && channel.channelId !== this.id) {
        this.id = channel.channelId;
        this.name = channel.name;
        this.description = channel.description || '';
        this.contactEmail = channel.contactEmail || '';
      }
    });
  }

  saveChannel() {
    if (!this.id) return;
    if (!this.data.hasPermission('channel.edit_profile')) {
      this.error.set(this.i18n.t('studio.permissionError'));
      return;
    }
    this.error.set('');
    this.channels.updateChannel(this.id, {
      name: this.name,
      description: this.description,
      contactEmail: this.contactEmail,
    }).subscribe({
      next: () => this.message.set(this.i18n.t('studio.saved')),
      error: () => this.error.set(this.i18n.t('studio.saveError')),
    });
  }

  setLanguage(language: 'vi' | 'en') {
    this.i18n.setLang(language);
    this.account.updatePreferences({ language }).subscribe({
      error: () => this.error.set(this.i18n.t('studio.saveError'))
    });
  }

  setTheme(theme: 'light' | 'dark') {
    this.theme.setTheme(theme);
    this.account.updatePreferences({ theme }).subscribe({
      error: () => this.error.set(this.i18n.t('studio.saveError'))
    });
  }
}
