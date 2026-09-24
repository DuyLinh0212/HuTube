import { CommonModule } from '@angular/common';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { errorMessage } from '../../core/auth.service';
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

@Component({
  selector: 'app-cf-seeder-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './cf-seeder-page.html',
  styleUrl: './cf-seeder-page.scss',
})
export class CfSeederPage implements OnInit {
  private readonly topicsService = inject(AdminTopicsService);
  private readonly seederApi = inject(CfSeederApiService);
  readonly runner = inject(CfSeederRunnerService);
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
    if (!videos || !capacity) return { level: 'info', text: 'Chọn thư mục và cấu hình số kênh để kiểm tra tính khả thi.' };
    if (capacity < videos) return {
      level: 'warning',
      text: `Tổng sức chứa là ${capacity} video, thấp hơn ${videos} video trong thư mục. ${videos - capacity} video sẽ không được upload.`,
    };
    if (capacity > videos) return {
      level: 'warning',
      text: `${this.accountMode === 'existing' ? 'Bạn đã chọn' : 'Bạn tạo'} ${accountCount} kênh với tối đa ${this.safeVideoLimit()} video/kênh (${capacity} chỗ), nhưng chỉ có ${videos} video. Một số kênh sẽ có ít video hơn giới hạn.`,
    };
    return { level: 'success', text: `Cấu hình vừa đủ cho ${videos} video: ${accountCount} kênh, mỗi kênh tối đa ${this.safeVideoLimit()} video.` };
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
  readonly stateLabel = computed(() => stateLabel(this.runner.state()));

  ngOnInit(): void {
    this.topicsService.getTopics('active').subscribe({
      next: topics => {
        this.topics.set(topics);
        if (!this.categoryId && topics.length) this.categoryId = topics[0].categoryId;
        this.loadingTopics.set(false);
      },
      error: error => {
        this.pageError.set(errorMessage(error));
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
        this.pageError.set(errorMessage(error));
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
      this.pageError.set('Mỗi lượt seed chỉ được chọn tối đa 100 user/kênh.');
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
      this.pageError.set(error instanceof Error ? error.message : 'Không thể đọc thư mục đã chọn.');
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
    catch (error) { this.pageError.set(error instanceof Error ? error.message : 'File account JSON không hợp lệ.'); }
    input.value = '';
  }

  async start(): Promise<void> {
    if (!this.canStart()) return;
    const folder = this.runner.folder();
    if (!folder) return;
    if (!window.confirm(`Bắt đầu upload tối đa ${Math.min(folder.files.length, this.capacity())} video và toàn bộ rendition đã phát hiện? File dataset sẽ được giữ lại.`)) return;
    this.pageError.set('');
    const config: CfSeedRunConfig = {
      accountMode: this.accountMode,
      categoryId: this.categoryId,
      categoryName: this.selectedTopic()?.name ?? 'Không xác định',
      userCount: this.effectiveAccountCount(),
      existingAccounts: this.selectedExistingAccounts(),
      maxVideosPerChannel: this.safeVideoLimit(),
      visibility: this.visibility,
    };
    try { await this.runner.start(config); }
    catch (error) { this.pageError.set(error instanceof Error ? error.message : 'Không thể bắt đầu CF Data Seeder.'); }
  }

  safeUserCount(): number { return Math.max(0, Math.trunc(Number(this.userCount) || 0)); }
  safeVideoLimit(): number { return Math.max(0, Math.trunc(Number(this.maxVideosPerChannel) || 0)); }
  formatBytes(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    const units = ['KB', 'MB', 'GB', 'TB'];
    let value = bytes / 1024;
    let unit = units[0];
    for (let index = 1; index < units.length && value >= 1024; index++) { value /= 1024; unit = units[index]; }
    return `${value.toFixed(value >= 10 ? 1 : 2)} ${unit}`;
  }
  formatDuration(seconds: number): string {
    const hours = Math.floor(seconds / 3600).toString().padStart(2, '0');
    const minutes = Math.floor(seconds % 3600 / 60).toString().padStart(2, '0');
    const rest = Math.floor(seconds % 60).toString().padStart(2, '0');
    return `${hours}:${minutes}:${rest}`;
  }
  trackLog(index: number): number { return index; }

}

function stateLabel(state: CfSeedRunState): string {
  const labels: Record<CfSeedRunState, string> = {
    idle: 'Sẵn sàng', provisioning: 'Đang tạo tài khoản', running: 'Đang chạy',
    completed: 'Hoàn thành', completed_with_errors: 'Xong, có lỗi', cancelled: 'Đã dừng', failed: 'Thất bại',
  };
  return labels[state];
}
