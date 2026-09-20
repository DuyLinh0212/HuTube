import { HttpErrorResponse } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { errorMessage } from '../../core/auth.service';
import { CfSeederApiService, UploadCfSeedVideoRequest } from './cf-seeder-api.service';
import {
  CfSeedAccountInput,
  CfSeedFileEntry,
  CfSeedFolderSelection,
  CfSeedMetrics,
  CfSeedRunConfig,
  CfSeedRunHistory,
  CfSeedRunState,
  CfSeedQualityScan,
  CfSeedProvisionResponse,
  EMPTY_CF_SEED_QUALITY_SCAN,
  CfSeedVideoResult,
  EMPTY_CF_SEED_METRICS,
} from './cf-seeder.models';

const VIDEO_EXTENSIONS = new Set(['mp4', 'mov', 'webm', 'mkv']);
const HISTORY_KEY = 'hutube.cf-seeder.history.v1';
const MAX_HISTORY = 8;
const MAX_VISIBLE_LOGS = 400;
const DEFAULT_CHUNK_SIZE = 24 * 1024 * 1024;
const QUALITY_HEIGHTS = [360, 480, 720, 1080, 1440, 2160];

type CfSeedVideoMetadata = { duration: number; height: number };

@Injectable({ providedIn: 'root' })
export class CfSeederRunnerService {
  private readonly api = inject(CfSeederApiService);
  private cancelRequested = false;
  private startedAtMs = 0;
  private elapsedTimer?: number;
  private qualityScanToken = 0;
  private readonly metadataCache = new WeakMap<File, CfSeedVideoMetadata>();

  readonly folder = signal<CfSeedFolderSelection | null>(null);
  readonly qualityScan = signal<CfSeedQualityScan>({ ...EMPTY_CF_SEED_QUALITY_SCAN });
  readonly accounts = signal<CfSeedAccountInput[]>([]);
  readonly accountFileName = signal('');
  readonly state = signal<CfSeedRunState>('idle');
  readonly metrics = signal<CfSeedMetrics>({ ...EMPTY_CF_SEED_METRICS });
  readonly logs = signal<string[]>([]);
  readonly elapsedSeconds = signal(0);
  readonly histories = signal<CfSeedRunHistory[]>(this.readHistory());
  readonly currentError = signal('');
  readonly isRunning = computed(() => this.state() === 'provisioning' || this.state() === 'running');
  readonly averageUploadDurationMs = computed(() => {
    const metrics = this.metrics();
    return metrics.uploadCount > 0 ? metrics.totalUploadDurationMs / metrics.uploadCount : 0;
  });
  readonly progressPercent = computed(() => {
    const value = this.metrics();
    return value.targetVideos === 0 ? 0 : Math.round(value.processedVideos * 100 / value.targetVideos);
  });

  get supportsDirectoryPicker(): boolean {
    return typeof window !== 'undefined' && 'showDirectoryPicker' in window;
  }

  async selectDirectory(): Promise<void> {
    const picker = (window as Window & {
      showDirectoryPicker?: (options?: { mode?: 'read' | 'readwrite' }) => Promise<FileSystemDirectoryHandle>;
    }).showDirectoryPicker;
    if (!picker) throw new Error('Trình duyệt không hỗ trợ chọn thư mục có quyền xóa file.');
    const directory = await picker({ mode: 'readwrite' });
    const entries: CfSeedFileEntry[] = [];
    let ignoredFileCount = 0;
    let totalBytes = 0;
    for await (const [name, handle] of directory.entries()) {
      if (handle.kind !== 'file') {
        ignoredFileCount++;
        continue;
      }
      const fileHandle = handle as FileSystemFileHandle;
      const file = await fileHandle.getFile();
      if (!isVideoFile(file)) {
        ignoredFileCount++;
        continue;
      }
      entries.push({ name, file, handle: fileHandle });
      totalBytes += file.size;
    }
    entries.sort((a, b) => a.name.localeCompare(b.name, 'vi', { numeric: true }));
    this.folder.set({
      name: directory.name,
      files: entries,
      ignoredFileCount,
      totalBytes,
      directoryHandle: directory,
      canDeleteSources: true,
    });
    await this.scanFolderQuality();
  }

  async useFallbackFiles(files: FileList): Promise<void> {
    const videoFiles = Array.from(files).filter(isVideoFile);
    const entries = videoFiles.map(file => ({ name: file.name, file }));
    const firstPath = videoFiles[0]?.webkitRelativePath ?? '';
    this.folder.set({
      name: firstPath.split('/')[0] || 'Thư mục đã chọn',
      files: entries,
      ignoredFileCount: files.length - entries.length,
      totalBytes: entries.reduce((sum, item) => sum + item.file.size, 0),
      canDeleteSources: false,
    });
    await this.scanFolderQuality();
  }

  async loadAccountFile(file: File): Promise<void> {
    const parsed: unknown = JSON.parse(await file.text());
    const list = Array.isArray(parsed) ? parsed : isObject(parsed) && Array.isArray(parsed['accounts'])
      ? parsed['accounts']
      : null;
    if (!list) throw new Error('JSON phải là một mảng account hoặc object có thuộc tính "accounts".');
    const accounts = list.map((value, index) => parseAccount(value, index));
    if (accounts.length === 0 || accounts.length > 100)
      throw new Error('File JSON phải có từ 1 đến 100 account.');
    this.accounts.set(accounts);
    this.accountFileName.set(file.name);
  }

  downloadAccountTemplate(): void {
    const template = {
      accounts: [
        {
          username: 'minhnguyen2003',
          displayName: 'Minh Nguyễn',
          channelName: 'Minh Nguyễn Official',
          password: 'MinhNguyen123!',
        },
        {
          username: 'huyen_tran',
          displayName: 'Huyền Trân',
          channelName: 'Huyền Trân',
          password: 'HuyenTran123!',
        },
        {
          username: 'hoangnam.travel',
          displayName: 'Hoàng Nam',
          channelName: 'Nam Đi Đây',
          password: 'HoangNam123!',
        },
      ],
    };
    downloadJson(template, 'cf-seeder-accounts.sample.json');
  }

  async start(config: CfSeedRunConfig): Promise<void> {
    if (this.isRunning()) return;
    const folder = this.folder();
    if (!folder || folder.files.length === 0) throw new Error('Hãy chọn thư mục có ít nhất một video hợp lệ.');
    if (config.accountMode === 'new' && this.accounts().length < config.userCount)
      throw new Error(`File JSON chỉ có ${this.accounts().length} account, cần ít nhất ${config.userCount}.`);
    if (config.accountMode === 'existing' && config.existingAccounts.length === 0)
      throw new Error('Hãy chọn ít nhất một user/kênh hiện có.');
    const qualityScan = this.qualityScan();
    if (qualityScan.status !== 'ready' || !qualityScan.maxCommonQuality)
      throw new Error(qualityScan.error || 'Chưa phân tích xong chất lượng của toàn bộ video.');
    if (qualityHeight(config.maxQuality) > qualityHeight(qualityScan.maxCommonQuality))
      throw new Error(`Chất lượng đã chọn vượt quá mức chung ${qualityScan.maxCommonQuality} của toàn bộ video.`);

    const runId = crypto.randomUUID();
    const startedAt = new Date().toISOString();
    const accountCount = config.accountMode === 'existing' ? config.existingAccounts.length : config.userCount;
    if (accountCount < 1 || accountCount > 100)
      throw new Error('Mỗi lượt seed phải có từ 1 đến 100 user/kênh.');
    const targetFiles = folder.files.slice(0, accountCount * config.maxVideosPerChannel);
    const results: CfSeedVideoResult[] = [];
    let batchId: string | undefined;
    this.cancelRequested = false;
    this.currentError.set('');
    this.logs.set([]);
    this.metrics.set({ ...EMPTY_CF_SEED_METRICS, targetVideos: targetFiles.length });
    this.state.set('provisioning');
    this.startClock();
    this.log(`Bắt đầu lượt seed ${runId.slice(0, 8)} với ${targetFiles.length} video.`);

    try {
      let provision: CfSeedProvisionResponse;
      if (config.accountMode === 'existing') {
        this.log(`Đang dùng ${config.existingAccounts.length} user/kênh hiện có...`);
        provision = {
          batchId: crypto.randomUUID(),
          accounts: config.existingAccounts,
        };
        this.log(`Đã chọn ${provision.accounts.length} user/kênh hiện có. Bắt đầu upload.`);
      } else {
        const selectedAccounts = this.accounts().slice(0, config.userCount);
        this.log(`Đang tạo ${selectedAccounts.length} tài khoản và kênh...`);
        provision = await firstValueFrom(this.api.createAccounts(selectedAccounts));
        this.log(`Đã tạo ${provision.accounts.length} tài khoản seed. Bắt đầu upload.`);
      }
      batchId = provision.batchId;
      this.updateMetrics({ usersCreated: provision.accounts.length, channelsCreated: provision.accounts.length });
      this.state.set('running');

      for (let index = 0; index < targetFiles.length; index++) {
        if (this.cancelRequested) break;
        const entry = targetFiles[index];
        const account = provision.accounts[Math.floor(index / config.maxVideosPerChannel)];
        const sequence = index + 1;
        const result: CfSeedVideoResult = {
          sequence,
          fileName: entry.name,
          username: account.username,
          channelId: account.channelId,
          uploaded: false,
          sourceDeleted: false,
          sizeBytes: entry.file.size,
        };
        this.log(`Đang đọc metadata ${entry.name}...`);
        let uploadStartedAt: number | undefined;
        const recordUploadDuration = (): void => {
          if (uploadStartedAt === undefined) return;
          const durationMs = Math.max(0, Math.round(performance.now() - uploadStartedAt));
          uploadStartedAt = undefined;
          result.uploadDurationMs = durationMs;
          const metrics = this.metrics();
          this.updateMetrics({
            totalUploadDurationMs: metrics.totalUploadDurationMs + durationMs,
            lastUploadDurationMs: durationMs,
            uploadCount: metrics.uploadCount + 1,
          });
          this.log(`⏱ Upload ${entry.name}: ${this.formatUploadDuration(durationMs)}.`);
        };
        try {
          const metadata = await this.readVideoMetadata(entry.file);
          const sourceQuality = capQuality(config.maxQuality, metadata.height);
          this.log(`Upload ${sequence}/${targetFiles.length} vào kênh @${account.channelHandle} (${sourceQuality})...`);
          uploadStartedAt = performance.now();
          const uploaded = await this.uploadVideoWithRetry({
            batchId: provision.batchId,
            userId: account.userId,
            channelId: account.channelId,
            categoryId: config.categoryId,
            title: titleFromFile(entry.name),
            visibility: config.visibility,
            duration: metadata.duration,
            sourceQuality,
            sequence,
            useExistingAccount: config.accountMode === 'existing',
            file: withVideoType(entry.file),
          });
          recordUploadDuration();
          result.uploaded = true;
          result.videoId = uploaded.videoId;
          this.updateMetrics({
            uploadedVideos: this.metrics().uploadedVideos + 1,
            uploadedBytes: this.metrics().uploadedBytes + entry.file.size,
          });
          if (folder.directoryHandle && entry.handle) {
            try {
              await folder.directoryHandle.removeEntry(entry.name);
              result.sourceDeleted = true;
              this.updateMetrics({ deletedSources: this.metrics().deletedSources + 1 });
              this.log(`✓ Upload xong và đã xóa file nguồn: ${entry.name}`);
            } catch (deleteError) {
              this.log(`⚠ Upload thành công nhưng không xóa được ${entry.name}: ${plainError(deleteError)}`);
            }
          } else {
            this.log(`✓ Upload xong ${entry.name}; trình duyệt không cấp quyền xóa file nguồn.`);
          }
        } catch (uploadError) {
          recordUploadDuration();
          result.error = displayError(uploadError);
          this.updateMetrics({ failedVideos: this.metrics().failedVideos + 1 });
          this.log(`✕ Không upload được ${entry.name}: ${result.error}`);
        } finally {
          results.push(result);
          this.updateMetrics({ processedVideos: this.metrics().processedVideos + 1 });
        }
      }

      if (this.cancelRequested) {
        this.state.set('cancelled');
        this.log('Đã dừng theo yêu cầu. Video đang upload trước đó đã được xử lý xong.');
      } else if (this.metrics().failedVideos > 0) {
        this.state.set('completed_with_errors');
        this.log(`Hoàn tất với ${this.metrics().failedVideos} video lỗi.`);
      } else {
        this.state.set('completed');
        this.log(`Hoàn tất ${this.metrics().uploadedVideos}/${targetFiles.length} video.`);
      }
    } catch (runError) {
      const message = displayError(runError);
      this.currentError.set(message);
      this.state.set('failed');
      this.log(`Lượt seed thất bại: ${message}`);
    } finally {
      this.stopClock();
      const history: CfSeedRunHistory = {
        schemaVersion: 1,
        runId,
        batchId,
        startedAt,
        completedAt: new Date().toISOString(),
        status: this.state(),
        sourceFolder: folder.name,
        categoryId: config.categoryId,
        categoryName: config.categoryName,
        accountMode: config.accountMode,
        userCount: accountCount,
        channelCount: this.metrics().channelsCreated,
        maxVideosPerChannel: config.maxVideosPerChannel,
        selectedVideoCount: folder.files.length,
        targetVideoCount: targetFiles.length,
        maxQuality: config.maxQuality,
        visibility: config.visibility,
        canDeleteSources: folder.canDeleteSources,
        metrics: { ...this.metrics() },
        results,
        logs: [...this.logs()],
        error: this.currentError() || undefined,
      };
      this.saveHistory(history);
      this.downloadHistory(history);
    }
  }

  cancel(): void {
    if (!this.isRunning()) return;
    this.cancelRequested = true;
    this.log('Đã nhận yêu cầu dừng; sẽ dừng sau file đang xử lý.');
  }

  downloadHistory(history: CfSeedRunHistory): void {
    const stamp = history.startedAt.replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
    downloadJson(history, `cf-seeder-${stamp}.json`);
  }

  clearLogs(): void {
    this.logs.set([]);
  }

  formatUploadDuration(milliseconds: number): string {
    if (!Number.isFinite(milliseconds) || milliseconds <= 0) return '—';
    const seconds = milliseconds / 1000;
    if (seconds < 60) return `${seconds.toFixed(seconds < 10 ? 1 : 0)} giây`;
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds - minutes * 60;
    return `${minutes} phút ${remainingSeconds.toFixed(0).padStart(2, '0')} giây`;
  }

  private async scanFolderQuality(): Promise<void> {
    const folder = this.folder();
    const token = ++this.qualityScanToken;
    if (!folder || folder.files.length === 0) {
      this.qualityScan.set({ ...EMPTY_CF_SEED_QUALITY_SCAN });
      return;
    }

    this.qualityScan.set({
      status: 'scanning',
      processedFiles: 0,
      totalFiles: folder.files.length,
    });

    let minimumSourceHeight = Number.POSITIVE_INFINITY;
    for (let index = 0; index < folder.files.length; index++) {
      if (token !== this.qualityScanToken) return;
      const entry = folder.files[index];
      try {
        const metadata = await this.readVideoMetadata(entry.file);
        if (!Number.isFinite(metadata.height) || metadata.height <= 0)
          throw new Error('không xác định được độ phân giải');
        minimumSourceHeight = Math.min(minimumSourceHeight, metadata.height);
      } catch (error) {
        if (token !== this.qualityScanToken) return;
        this.qualityScan.set({
          status: 'error',
          processedFiles: index + 1,
          totalFiles: folder.files.length,
          error: `Không thể đọc chất lượng video “${entry.name}”: ${plainError(error)}`,
        });
        return;
      }
      this.qualityScan.update(current => ({ ...current, processedFiles: index + 1 }));
    }

    const commonQualityHeight = highestQualityForHeight(minimumSourceHeight);
    if (commonQualityHeight === 0) {
      this.qualityScan.set({
        status: 'error',
        processedFiles: folder.files.length,
        totalFiles: folder.files.length,
        minimumSourceHeight,
        error: 'Có video thấp hơn 360p; hệ thống hiện chỉ hỗ trợ chất lượng từ 360p trở lên.',
      });
      return;
    }
    this.qualityScan.set({
      status: 'ready',
      processedFiles: folder.files.length,
      totalFiles: folder.files.length,
      minimumSourceHeight,
      maxCommonQuality: `${commonQualityHeight}p`,
    });
  }

  private async readVideoMetadata(file: File): Promise<CfSeedVideoMetadata> {
    const cached = this.metadataCache.get(file);
    if (cached) return cached;
    const metadata = await readVideoMetadata(file);
    this.metadataCache.set(file, metadata);
    return metadata;
  }

  private updateMetrics(change: Partial<CfSeedMetrics>): void {
    this.metrics.update(current => ({ ...current, ...change }));
  }

  private async uploadVideoWithRetry(request: UploadCfSeedVideoRequest) {
    // The API upload endpoint streams directly to storage and has no ASP.NET
    // request-size limit. Prefer that path for every file so large videos do
    // not get written to the temporary chunk store and then read back again.
    // If a Cloudflare/proxy in front of the API rejects the body, fall back to
    // the resumable endpoint instead of making the user retry manually.
    try {
      return await this.withTransientRetry(
        () => firstValueFrom(this.api.uploadVideo(request)),
        'upload video',
        error => isTransientUploadError(error) && !isDirectUploadSizeFailure(error, request.file.size),
      );
    } catch (error) {
      if (!isDirectUploadSizeFailure(error, request.file.size)) throw error;
      this.log(`Upload trực tiếp bị giới hạn hoặc bị reset; chuyển ${request.file.name} sang upload từng phần.`);
      return this.uploadVideoInChunks(request);
    }
  }

  private async uploadVideoInChunks(request: UploadCfSeedVideoRequest) {
    const expectedChunks = Math.ceil(request.file.size / DEFAULT_CHUNK_SIZE);
    const clientUploadId = crypto.randomUUID();
    const session = await this.withTransientRetry(
      () => firstValueFrom(this.api.startChunkedUpload(clientUploadId, request.file, expectedChunks)),
      'khởi tạo upload',
    );
    if (session.chunkSize !== DEFAULT_CHUNK_SIZE)
      throw new Error('Kích thước chunk giữa giao diện và API không đồng nhất.');
    this.log(`Đang upload ${request.file.name} theo ${expectedChunks} phần ${Math.round(session.chunkSize / 1024 / 1024)} MB.`);
    for (let chunkIndex = 0; chunkIndex < expectedChunks; chunkIndex++) {
      if (this.cancelRequested) throw new Error('Đã hủy trong lúc upload từng phần.');
      const start = chunkIndex * session.chunkSize;
      const chunk = request.file.slice(start, Math.min(start + session.chunkSize, request.file.size));
      await this.withTransientRetry(
        () => firstValueFrom(this.api.uploadChunk(session.uploadId, chunkIndex, chunk)),
        `phần ${chunkIndex + 1}/${expectedChunks}`,
      );
    }
    const { file: _, ...completion } = request;
    return this.withTransientRetry(
      () => firstValueFrom(this.api.completeChunkedUpload(session.uploadId, completion)),
      'hoàn tất video',
    );
  }

  private async withTransientRetry<T>(operation: () => Promise<T>, operationName: string,
    shouldRetry: (error: unknown) => boolean = isTransientUploadError): Promise<T> {
    const maxAttempts = 4;
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try { return await operation(); }
      catch (error) {
        if (!shouldRetry(error) || attempt === maxAttempts) throw error;
        const delayMs = retryDelayMs(error, attempt);
        this.log(`⚠ ${operationName} tạm thời bị gián đoạn; thử lại ${attempt}/${maxAttempts - 1} sau ${Math.ceil(delayMs / 1000)} giây.`);
        await delay(delayMs);
        if (this.cancelRequested) throw new Error('Đã hủy trong lúc chờ thử lại upload.');
      }
    }
    throw new Error('Không thể upload video sau nhiều lần thử.');
  }

  private log(message: string): void {
    const time = new Date().toLocaleTimeString('vi-VN', { hour12: false });
    this.logs.update(current => [...current, `[${time}] ${message}`].slice(-MAX_VISIBLE_LOGS));
  }

  private startClock(): void {
    this.stopClock();
    this.startedAtMs = Date.now();
    this.elapsedSeconds.set(0);
    this.elapsedTimer = window.setInterval(() => {
      this.elapsedSeconds.set(Math.floor((Date.now() - this.startedAtMs) / 1000));
    }, 1000);
  }

  private stopClock(): void {
    if (this.elapsedTimer !== undefined) window.clearInterval(this.elapsedTimer);
    this.elapsedTimer = undefined;
    if (this.startedAtMs) this.elapsedSeconds.set(Math.floor((Date.now() - this.startedAtMs) / 1000));
  }

  private readHistory(): CfSeedRunHistory[] {
    try {
      const value: unknown = JSON.parse(localStorage.getItem(HISTORY_KEY) ?? '[]');
      return Array.isArray(value) ? value as CfSeedRunHistory[] : [];
    } catch { return []; }
  }

  private saveHistory(history: CfSeedRunHistory): void {
    const histories = [history, ...this.histories()].slice(0, MAX_HISTORY);
    this.histories.set(histories);
    try { localStorage.setItem(HISTORY_KEY, JSON.stringify(histories)); }
    catch {
      try { localStorage.setItem(HISTORY_KEY, JSON.stringify(histories.map(item => ({ ...item, results: [], logs: [] })))); }
      catch { /* JSON download still preserves this run when browser storage is full. */ }
    }
  }
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function parseAccount(value: unknown, index: number): CfSeedAccountInput {
  if (!isObject(value)) throw new Error(`Account #${index + 1} phải là một object.`);
  const username = typeof value['username'] === 'string' ? value['username'].trim() : '';
  const displayName = typeof value['displayName'] === 'string' ? value['displayName'].trim() : '';
  const channelName = typeof value['channelName'] === 'string' ? value['channelName'].trim() : undefined;
  const password = typeof value['password'] === 'string' ? value['password'] : '';
  if (!/^[A-Za-z0-9_.-]{3,50}$/.test(username))
    throw new Error(`Account #${index + 1}: username không hợp lệ.`);
  if (!displayName || displayName.length > 120)
    throw new Error(`Account #${index + 1}: displayName không hợp lệ.`);
  if (password.length < 10 || password.length > 128 || !/[A-Z]/.test(password)
    || !/[a-z]/.test(password) || !/[0-9]/.test(password))
    throw new Error(`Account #${index + 1}: password cần 10–128 ký tự, gồm chữ hoa, chữ thường và số.`);
  return { username, displayName, channelName, password };
}

function extension(fileName: string): string {
  return fileName.split('.').pop()?.toLowerCase() ?? '';
}

function isVideoFile(file: File): boolean {
  return file.type.startsWith('video/') || VIDEO_EXTENSIONS.has(extension(file.name));
}

function withVideoType(file: File): File {
  if (file.type) return file;
  const contentTypes: Record<string, string> = {
    mp4: 'video/mp4', mov: 'video/quicktime', webm: 'video/webm', mkv: 'video/x-matroska',
  };
  return new File([file], file.name, { type: contentTypes[extension(file.name)] ?? 'video/mp4', lastModified: file.lastModified });
}

function titleFromFile(fileName: string): string {
  return fileName.replace(/\.[^.]+$/, '').replace(/[_-]+/g, ' ').trim().slice(0, 100) || 'CF Seed Video';
}

async function readVideoMetadata(file: File): Promise<{ duration: number; height: number }> {
  const url = URL.createObjectURL(file);
  try {
    return await new Promise((resolve, reject) => {
      const video = document.createElement('video');
      const timeout = window.setTimeout(() => reject(new Error('Không đọc được metadata video sau 30 giây.')), 30_000);
      video.preload = 'metadata';
      video.onloadedmetadata = () => {
        window.clearTimeout(timeout);
        if (!Number.isFinite(video.duration) || video.duration <= 0) reject(new Error('Thời lượng video không hợp lệ.'));
        else resolve({ duration: Math.max(1, Math.ceil(video.duration)), height: video.videoHeight });
      };
      video.onerror = () => { window.clearTimeout(timeout); reject(new Error('File video bị lỗi hoặc trình duyệt không hỗ trợ codec.')); };
      video.src = url;
    });
  } finally { URL.revokeObjectURL(url); }
}

function capQuality(selected: string, height: number): string {
  const selectedHeight = Number.parseInt(selected, 10) || 720;
  const limit = height > 0 ? Math.min(selectedHeight, height) : selectedHeight;
  const chosen = highestQualityForHeight(limit) || 360;
  return `${chosen}p`;
}

function qualityHeight(value: string): number {
  return Number.parseInt(value, 10) || 0;
}

function highestQualityForHeight(height: number): number {
  return [...QUALITY_HEIGHTS].reverse().find(value => value <= height) ?? 0;
}

function plainError(error: unknown): string {
  return error instanceof Error ? error.message : 'Lỗi không xác định.';
}

function displayError(error: unknown): string {
  return error instanceof HttpErrorResponse ? errorMessage(error) : plainError(error);
}

function isDirectUploadSizeFailure(error: unknown, fileSize: number): boolean {
  if (!(error instanceof HttpErrorResponse)) return false;
  return error.status === 413 || (fileSize >= 80 * 1024 * 1024 && error.status === 0);
}

function isTransientUploadError(error: unknown): boolean {
  return error instanceof HttpErrorResponse
    && (error.status === 0 || error.status === 408 || error.status === 425 || error.status === 429 || error.status >= 500);
}

function retryDelayMs(error: unknown, attempt: number): number {
  if (error instanceof HttpErrorResponse) {
    const retryAfter = error.headers.get('Retry-After');
    const seconds = retryAfter ? Number.parseInt(retryAfter, 10) : Number.NaN;
    if (Number.isFinite(seconds) && seconds >= 0) return Math.min(seconds * 1000, 60_000);
  }
  return Math.min(1000 * 2 ** (attempt - 1) + Math.floor(Math.random() * 500), 15_000);
}

function delay(milliseconds: number): Promise<void> {
  return new Promise(resolve => window.setTimeout(resolve, milliseconds));
}

function downloadJson(value: unknown, fileName: string): void {
  const blob = new Blob([JSON.stringify(value, null, 2)], { type: 'application/json;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = fileName;
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}
