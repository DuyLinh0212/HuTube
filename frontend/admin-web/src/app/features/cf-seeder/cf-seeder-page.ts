import { CommonModule } from '@angular/common';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { errorMessage } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { AdminTopic, AdminTopicsService } from '../topics/admin-topics.service';
import { CfSeederApiService } from './cf-seeder-api.service';
import {
  CfSeedAccount,
  CfSeedAccountMode,
  CfSeedRunConfig,
  CfSeedRunState,
  CfSeedVisibility,
} from './cf-seeder.models';
import { CfSeederRunnerService } from './cf-seeder-runner.service';
import { TranslatePipe } from '../../core/translate.pipe';

@Component({
  selector: 'app-cf-seeder-page',
  standalone: true,
  imports: [CommonModule, FormsModule, TranslatePipe],
  templateUrl: './cf-seeder-page.html',
  styleUrl: './cf-seeder-page.scss',
})
export class CfSeederPage implements OnInit {
  private readonly topicsService = inject(AdminTopicsService);
  private readonly seederApi = inject(CfSeederApiService);
  readonly runner = inject(CfSeederRunnerService);
  readonly i18n = inject(I18nService);
  readonly topics = signal<AdminTopic[]>([]);
  readonly existingAccounts = signal<CfSeedAccount[]>([]);
  readonly selectedExistingAccounts = signal<CfSeedAccount[]>([]);
  readonly loadingExistingAccounts = signal(false);
  readonly loadingTopics = signal(true);
  readonly pageError = signal('');

  categoryId = '';
  accountMode: CfSeedAccountMode = 'new';
  existingSearch = '';
  userCount = 10;
  maxVideosPerChannel = 15;
  visibility: CfSeedVisibility = 'public';

  capacity(): number { return this.effectiveAccountCount() * this.safeVideoLimit(); }
  selectedVideoCount(): number { return this.runner.folder()?.files.length ?? 0; }
  effectiveAccountCount(): number {
    return this.accountMode === 'existing' ? this.selectedExistingAccounts().length : this.safeUserCount();
  }
  selectedTopic(): AdminTopic | undefined { return this.topics().find(topic => topic.categoryId === this.categoryId); }
  feasibility(): { level: string; text: string } {
    const videos = this.selectedVideoCount();
    const capacity = this.capacity();
    const accountCount = this.effectiveAccountCount();
    if (!videos || !capacity) return { level: 'info', text: this.i18n.t('seeder.chooseInputs') };
    if (capacity < videos) return {
      level: 'warning',
      text: this.i18n.format('seeder.capacityTooSmall', { capacity, videos, remaining: videos - capacity }),
    };
    if (capacity > videos) return {
      level: 'warning',
      text: this.i18n.format('seeder.capacityUnused', {
        accountChoice: this.i18n.t(this.accountMode === 'existing' ? 'seeder.selectedAccountChoice' : 'seeder.createdAccountChoice'),
        accounts: accountCount,
        limit: this.safeVideoLimit(),
        capacity,
        videos,
      }),
    };
    return {
      level: 'success',
      text: this.i18n.format('seeder.capacityExact', { videos, accounts: accountCount, limit: this.safeVideoLimit() }),
    };
  }
  canStart(): boolean {
    const qualityScan = this.runner.qualityScan();
    const accountCount = this.effectiveAccountCount();
    const hasRequiredAccounts = this.accountMode === 'existing'
      ? this.selectedExistingAccounts().length > 0
      : this.runner.accounts().length >= this.safeUserCount();
    return !this.runner.isRunning()
    && !!this.runner.folder()?.files.length
    && !!this.categoryId
    && accountCount >= 1
    && accountCount <= 100
    && this.safeVideoLimit() >= 1
    && hasRequiredAccounts
    && qualityScan.status === 'ready';
  }
  readonly stateLabel = computed(() => {
    const state = this.runner.state();
    return this.i18n.t(`seeder.state.${state === 'completed_with_errors' ? 'completedWithErrors' : state}`);
  });

  statusLabel(state: CfSeedRunState): string {
    const suffix = state === 'completed_with_errors' ? 'partial' : state;
    const key = `seeder.status.${suffix}`;
    return this.i18n.t(key);
  }

  ngOnInit(): void {
    this.topicsService.getTopics('active').subscribe({
      next: topics => {
        this.topics.set(topics);
        if (!this.categoryId && topics.length) this.categoryId = topics[0].categoryId;
        this.loadingTopics.set(false);
      },
      error: error => {
        this.pageError.set(errorMessage(error, this.i18n));
        this.loadingTopics.set(false);
      },
    });
  }

  onAccountModeChange(): void {
    this.pageError.set('');
    if (this.accountMode === 'existing' && this.existingAccounts().length === 0)
      this.loadExistingAccounts();
  }

  loadExistingAccounts(): void {
    if (this.loadingExistingAccounts()) return;
    this.loadingExistingAccounts.set(true);
    this.seederApi.getExistingAccounts(this.existingSearch).subscribe({
      next: accounts => {
        this.existingAccounts.set(accounts);
        this.loadingExistingAccounts.set(false);
      },
      error: error => {
        this.pageError.set(errorMessage(error, this.i18n));
        this.loadingExistingAccounts.set(false);
      },
    });
  }

  toggleExistingAccount(account: CfSeedAccount): void {
    if (this.runner.isRunning()) return;
    const selected = this.selectedExistingAccounts();
    const index = selected.findIndex(item => item.userId === account.userId);
    if (index >= 0) {
      this.selectedExistingAccounts.set(selected.filter(item => item.userId !== account.userId));
      return;
    }
    if (selected.length >= 100) {
      this.pageError.set(this.i18n.t('seeder.maxUsers'));
      return;
    }
    this.pageError.set('');
    this.selectedExistingAccounts.set([...selected, account]);
  }

  isExistingAccountSelected(account: CfSeedAccount): boolean {
    return this.selectedExistingAccounts().some(item => item.userId === account.userId);
  }

  async chooseFolder(fallbackInput: HTMLInputElement): Promise<void> {
    this.pageError.set('');
    if (!this.runner.supportsDirectoryPicker) {
      fallbackInput.click();
      return;
    }
    try {
      await this.runner.selectDirectory();
    }
    catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') return;
      this.pageError.set(error instanceof Error ? error.message : this.i18n.t('seeder.readFolderError'));
    }
  }

  async onFallbackFolder(event: Event): Promise<void> {
    const input = event.target as HTMLInputElement;
    if (input.files?.length) {
      await this.runner.useFallbackFiles(input.files);
    }
    input.value = '';
  }

  async onAccountFile(event: Event): Promise<void> {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    this.pageError.set('');
    try { await this.runner.loadAccountFile(file); }
    catch (error) { this.pageError.set(error instanceof Error ? error.message : this.i18n.t('seeder.invalidAccountFile')); }
    input.value = '';
  }

  async start(): Promise<void> {
    if (!this.canStart()) return;
    const folder = this.runner.folder();
    if (!folder) return;
    if (!window.confirm(this.i18n.format('seeder.confirmStart', { count: Math.min(folder.files.length, this.capacity()) }))) return;
    this.pageError.set('');
    const config: CfSeedRunConfig = {
      accountMode: this.accountMode,
      categoryId: this.categoryId,
      categoryName: this.selectedTopic()?.name ?? this.i18n.t('seeder.unknownCategory'),
      userCount: this.effectiveAccountCount(),
      existingAccounts: this.selectedExistingAccounts(),
      maxVideosPerChannel: this.safeVideoLimit(),
      visibility: this.visibility,
    };
    try { await this.runner.start(config); }
    catch (error) { this.pageError.set(error instanceof Error ? error.message : this.i18n.t('seeder.startError')); }
  }

  safeUserCount(): number { return Math.max(0, Math.trunc(Number(this.userCount) || 0)); }
  safeVideoLimit(): number { return Math.max(0, Math.trunc(Number(this.maxVideosPerChannel) || 0)); }
  formatBytes(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    const units = ['KB', 'MB', 'GB', 'TB'];
    let value = bytes / 1024;
    let unit = units[0];
    for (let index = 1; index < units.length && value >= 1024; index++) { value /= 1024; unit = units[index]; }
    const formatted = new Intl.NumberFormat(this.i18n.currentLang() === 'en' ? 'en-US' : 'vi-VN', {
      maximumFractionDigits: value >= 10 ? 1 : 2,
    }).format(value);
    return `${formatted} ${unit}`;
  }
  formatDuration(seconds: number): string {
    const hours = Math.floor(seconds / 3600).toString().padStart(2, '0');
    const minutes = Math.floor(seconds % 3600 / 60).toString().padStart(2, '0');
    const rest = Math.floor(seconds % 60).toString().padStart(2, '0');
    return `${hours}:${minutes}:${rest}`;
  }
  trackLog(index: number): number { return index; }

  dateLocale(): string {
    return this.i18n.currentLang() === 'en' ? 'en-US' : 'vi-VN';
  }

}
