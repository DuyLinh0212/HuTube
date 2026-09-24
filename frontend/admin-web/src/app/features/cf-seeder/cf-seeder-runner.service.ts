import { HttpErrorResponse } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { errorMessage } from '../../core/auth.service';
import { CfSeederApiService, UploadCfSeedRenditionRequest, UploadCfSeedVideoRequest } from './cf-seeder-api.service';
import {
  CfSeedAccountInput,
  CfSeedFileEntry,
  CfSeedRenditionFile,
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

const VIDEO_EXTENSIONS = new Set(['mp4']);
const HISTORY_KEY = 'hutube.cf-seeder.history.v1';
const MAX_HISTORY = 8;
const MAX_VISIBLE_LOGS = 400;
const DEFAULT_CHUNK_SIZE = 24 * 1024 * 1024;
const QUALITY_HEIGHTS = [144, 240, 360, 480, 720, 1080, 1440, 2160];

type CfSeedVideoMetadata = { duration: number; width: number; height: number };
type ScannedFile = { file: File; relativePath: string };

@Injectable({ providedIn: 'root' })
export class CfSeederRunnerService {
  private readonly api = inject(CfSeederApiService);
  private cancelRequested = false;
  private startedAtMs = 0;
  private elapsedTimer?: number;

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
    if (!picker) throw new Error('Trình duyệt không hỗ trợ chọn thư mục.');
    const directory = await picker({ mode: 'read' });
    const scanned: ScannedFile[] = [];
    let ignoredFileCount = 0;
    const visit = async (current: FileSystemDirectoryHandle, parentPath: string): Promise<void> => {
      for await (const [name, handle] of current.entries()) {
        const relativePath = parentPath ? `${parentPath}/${name}` : name;
        if (handle.kind === 'directory') {
          await visit(handle as FileSystemDirectoryHandle, relativePath);
          continue;
        }
        const file = await (handle as FileSystemFileHandle).getFile();
        if (isVideoFile(file) || isMetadataFile(file)) scanned.push({ file, relativePath });
        else ignoredFileCount++;
      }
    };
    await visit(directory, '');
    await this.loadScannedFolder(directory.name, scanned, ignoredFileCount);
  }

  async useFallbackFiles(files: FileList): Promise<void> {
    const allFiles = Array.from(files);
    const scanned = allFiles
      .filter(file => isVideoFile(file) || isMetadataFile(file))
      .map(file => ({
        file,
        relativePath: file.webkitRelativePath.split('/').slice(1).join('/') || file.name,
      }));
    const firstPath = allFiles[0]?.webkitRelativePath ?? '';
    await this.loadScannedFolder(firstPath.split('/')[0] || 'Thư mục đã chọn', scanned,
      allFiles.length - scanned.length);
  }

  private async loadScannedFolder(name: string, scanned: ScannedFile[], ignoredFileCount: number): Promise<void> {
    const videoCount = scanned.filter(item => isVideoFile(item.file)).length;
    this.qualityScan.set({ status: 'scanning', processedFiles: 0, totalFiles: videoCount });
    const discovered = await discoverVideoEntries(scanned, processedFiles => {
      this.qualityScan.update(current => ({ ...current, processedFiles }));
    });
    const files = discovered.entries.sort((a, b) => a.relativePath.localeCompare(b.relativePath, 'vi', { numeric: true }));
    const totalBytes = files.reduce((sum, item) => sum + item.renditions.reduce((bytes, rendition) => bytes + rendition.file.size, 0), 0);
    this.folder.set({ name, files, ignoredFileCount: ignoredFileCount + discovered.ignoredCount, totalBytes, canDeleteSources: false });
    if (!files.length) {
      this.qualityScan.set({
        status: 'error', processedFiles: discovered.processedFiles, totalFiles: videoCount,
        error: 'Không tìm thấy thư mục video hợp lệ có rendition và metadata chất lượng đọc được.',
      });
      return;
    }
    const qualityCounts = QUALITY_HEIGHTS.slice().reverse()
      .map(height => ({ quality: `${height}p`, videoCount: files.filter(video => video.renditions.some(rendition => rendition.quality === `${height}p`)).length }))
      .filter(item => item.videoCount > 0);
    this.qualityScan.set({
      status: 'ready', processedFiles: discovered.processedFiles, totalFiles: videoCount, qualityCounts,
      duplicateFormatCount: discovered.duplicateFormatCount,
    });
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
    if (this.qualityScan().status !== 'ready')
      throw new Error(this.qualityScan().error || 'Chưa phân tích xong các rendition trong thư mục.');

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
          sizeBytes: entry.renditions.reduce((sum, rendition) => sum + rendition.file.size, 0),
          qualities: entry.renditions.map(rendition => rendition.quality),
        };
        this.log(`Đang upload ${entry.name}: ${entry.renditions.map(rendition => rendition.quality).join(', ')}.`);
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
          const source = [...entry.renditions].sort((a, b) => b.height - a.height)[0];
          if (!source) throw new Error('Video chưa có rendition hợp lệ.');
          const sourceQuality = source.quality;
          this.log(`Upload ${sequence}/${targetFiles.length} vào kênh @${account.channelHandle}; rendition nguồn ${sourceQuality}...`);
          uploadStartedAt = performance.now();
          const uploaded = await this.uploadVideoWithRetry({
            batchId: provision.batchId,
            userId: account.userId,
            channelId: account.channelId,
            categoryId: config.categoryId,
            title: entry.name.slice(0, 100),
            visibility: config.visibility,
            duration: entry.duration,
            sourceQuality,
            sourceWidth: source.width,
            sourceHeight: source.height,
            description: entry.description,
            sequence,
            useExistingAccount: config.accountMode === 'existing',
            file: withVideoType(source.file),
          });
          result.videoId = uploaded.videoId;
          this.updateMetrics({ uploadedBytes: this.metrics().uploadedBytes + source.file.size });
          this.log(`✓ Đã upload rendition nguồn ${source.quality} lên R2.`);
          for (const rendition of entry.renditions.filter(item => item.quality !== source.quality)
            .sort((a, b) => b.height - a.height)) {
            this.log(`Đang upload ${rendition.quality} (${formatBytes(rendition.file.size)}) lên R2...`);
            await this.uploadRenditionWithRetry(uploaded.videoId, rendition);
            this.updateMetrics({ uploadedBytes: this.metrics().uploadedBytes + rendition.file.size });
            this.log(`✓ ${rendition.quality} đã sẵn sàng trên R2.`);
          }
          recordUploadDuration();
          result.uploaded = true;
          this.updateMetrics({
            uploadedVideos: this.metrics().uploadedVideos + 1,
          });
          this.log(`✓ ${entry.name}: đã đưa ${entry.renditions.length} rendition lên R2; file dataset được giữ nguyên.`);
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
        this.log('Đã dừng theo yêu cầu sau khi xử lý xong video hiện tại.');
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
        qualities: [...new Set(targetFiles.flatMap(video => video.renditions.map(rendition => rendition.quality)))],
        visibility: config.visibility,
        canDeleteSources: false,
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
    this.log('Đã nhận yêu cầu dừng; sẽ dừng sau khi hoàn tất video hiện tại.');
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

  private async uploadRenditionWithRetry(videoId: string, rendition: CfSeedRenditionFile): Promise<void> {
    const request: UploadCfSeedRenditionRequest = {
      quality: rendition.quality,
      width: rendition.width,
      height: rendition.height,
      bitrateKbps: rendition.bitrateKbps,
      codec: rendition.codec,
      file: withVideoType(rendition.file),
    };
    try {
      await this.withTransientRetry(
        () => firstValueFrom(this.api.uploadRendition(videoId, request)),
        `upload rendition ${rendition.quality}`,
        error => isTransientUploadError(error) && !isDirectUploadSizeFailure(error, request.file.size),
      );
    } catch (error) {
      if (!isDirectUploadSizeFailure(error, request.file.size)) throw error;
      this.log(`Rendition ${rendition.quality} bị giới hạn khi upload trực tiếp; chuyển sang upload từng phần.`);
      await this.uploadRenditionInChunks(videoId, request);
    }
  }

  private async uploadRenditionInChunks(videoId: string, request: UploadCfSeedRenditionRequest): Promise<void> {
    const expectedChunks = Math.ceil(request.file.size / DEFAULT_CHUNK_SIZE);
    const session = await this.withTransientRetry(
      () => firstValueFrom(this.api.startChunkedUpload(crypto.randomUUID(), request.file, expectedChunks)),
      'khởi tạo upload rendition',
    );
    if (session.chunkSize !== DEFAULT_CHUNK_SIZE)
      throw new Error('Kích thước chunk giữa giao diện và API không đồng nhất.');
    for (let chunkIndex = 0; chunkIndex < expectedChunks; chunkIndex++) {
      const start = chunkIndex * session.chunkSize;
      const chunk = request.file.slice(start, Math.min(start + session.chunkSize, request.file.size));
      await this.withTransientRetry(
        () => firstValueFrom(this.api.uploadChunk(session.uploadId, chunkIndex, chunk)),
        `phần ${chunkIndex + 1}/${expectedChunks} của ${request.quality}`,
      );
    }
    const { file: _, ...completion } = request;
    await this.withTransientRetry(
      () => firstValueFrom(this.api.completeChunkedRenditionUpload(session.uploadId, videoId, completion)),
      `hoàn tất rendition ${request.quality}`,
    );
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

type VideoFormatMetadata = {
  format_id?: string;
  height?: number;
  width?: number;
  tbr?: number;
  vcodec?: string;
};

type DatasetInfo = {
  title?: string;
  id?: string;
  duration?: number;
  duration_string?: string;
  description?: string;
  formats?: VideoFormatMetadata[];
};

async function discoverVideoEntries(
  scanned: ScannedFile[],
  onProgress: (processed: number) => void,
): Promise<{ entries: CfSeedFileEntry[]; ignoredCount: number; duplicateFormatCount: number; processedFiles: number }> {
  const videos = scanned.filter(item => isVideoFile(item.file));
  const byDirectory = new Map<string, ScannedFile[]>();
  for (const item of videos) {
    const parent = item.relativePath.includes('/') ? item.relativePath.slice(0, item.relativePath.lastIndexOf('/')) : '';
    byDirectory.set(parent, [...(byDirectory.get(parent) ?? []), item]);
  }

  const entries: CfSeedFileEntry[] = [];
  let ignoredCount = 0;
  let duplicateFormatCount = 0;
  let processedFiles = 0;
  for (const [directory, directoryVideos] of byDirectory) {
    const sidecars = scanned.filter(item => {
      const parent = item.relativePath.includes('/') ? item.relativePath.slice(0, item.relativePath.lastIndexOf('/')) : '';
      return parent === directory;
    });
    const infoFiles = sidecars.filter(item => item.file.name.toLowerCase().endsWith('.info.json'));
    const descriptionFiles = sidecars.filter(item => item.file.name.toLowerCase().endsWith('.description'));
    const formatNamedVideos = directoryVideos.filter(item => parseQualityFilename(item.file.name));
    const isRenditionFolder = formatNamedVideos.length > 0;
    const groups = isRenditionFolder
      ? [{ videos: formatNamedVideos, titleFallback: datasetFolderTitle(leafName(directory)) || leafName(formatNamedVideos[0].relativePath) }]
      : directoryVideos.map(item => ({ videos: [item], titleFallback: item.file.name.replace(/\.[^.]+$/, '') }));

    for (const group of groups) {
      let info: DatasetInfo | undefined;
      const infoFile = infoFiles.length === 1 ? infoFiles[0] : infoFiles.find(item => {
        const id = item.file.name.replace(/\.info\.json$/i, '').split('_').slice(-2, -1)[0];
        return !!id && group.videos.some(video => video.file.name.includes(id));
      });
      if (infoFile) {
        try {
          const parsed: unknown = JSON.parse(await infoFile.file.text());
          if (isObject(parsed)) info = parsed as DatasetInfo;
        } catch { ignoredCount++; }
      }
      const formatMap = new Map<string, VideoFormatMetadata>();
      for (const format of info?.formats ?? []) {
        if (typeof format.format_id === 'string') formatMap.set(format.format_id, format);
      }
      const candidates: Array<CfSeedRenditionFile & { bitrate: number }> = [];
      let duration = finiteNumber(info?.duration) ? Math.ceil(info!.duration!) : parseDuration(info?.duration_string);
      let discoveredTitle = typeof info?.title === 'string' ? info.title.trim() : group.titleFallback;

      for (const item of group.videos) {
        const parsedName = parseQualityFilename(item.file.name);
        const format = parsedName?.formatId ? formatMap.get(parsedName.formatId) : undefined;
        let height = finiteNumber(format?.height) ? format!.height! : parsedName?.height ?? 0;
        let width = finiteNumber(format?.width) ? format!.width! : 0;
        if (!height || !duration) {
          try {
            const media = await readVideoMetadata(item.file);
            if (!duration) duration = media.duration;
            if (!height) height = media.height;
            if (!width) width = media.width;
          } catch { /* Sidecar and filename metadata are still used when the browser cannot decode the codec. */ }
        }
        const qualityHeight = height > 2160 ? 0 : highestQualityForHeight(height);
        if (!qualityHeight) {
          ignoredCount++;
          processedFiles++;
          onProgress(processedFiles);
          continue;
        }
        const videoCodec = typeof format?.vcodec === 'string' ? format.vcodec : '';
        const bitrate = finiteNumber(format?.tbr) ? format!.tbr! : 0;
        candidates.push({
          name: item.file.name,
          file: item.file,
          quality: `${qualityHeight}p`,
          width: width > 0 ? width : Math.round(height * 16 / 9),
          height,
          bitrateKbps: bitrate > 0 ? Math.round(bitrate) : undefined,
          codec: videoCodec || undefined,
          bitrate,
        });
        processedFiles++;
        onProgress(processedFiles);
      }

      if (!duration || candidates.length === 0) {
        ignoredCount += candidates.length;
        continue;
      }
      const bestByQuality = new Map<string, typeof candidates>();
      for (const candidate of candidates) bestByQuality.set(candidate.quality, [...(bestByQuality.get(candidate.quality) ?? []), candidate]);
      const renditions: CfSeedRenditionFile[] = [];
      for (const [quality, duplicates] of bestByQuality) {
        duplicates.sort((a, b) => b.bitrate - a.bitrate || b.file.size - a.file.size);
        const selected = duplicates[0];
        renditions.push({
          name: selected.name, file: selected.file, quality, width: selected.width, height: selected.height,
          bitrateKbps: selected.bitrateKbps, codec: selected.codec,
        });
        duplicateFormatCount += duplicates.length - 1;
      }
      renditions.sort((a, b) => a.height - b.height);
      const descriptionSidecar = descriptionFiles[0];
      let description = typeof info?.description === 'string' ? info.description : undefined;
      if (descriptionSidecar) {
        try { description = await descriptionSidecar.file.text(); }
        catch { /* Keep the description embedded in the info JSON. */ }
      }
      const title = (discoveredTitle || group.titleFallback).slice(0, 100) || 'CF Seed Video';
      entries.push({
        name: title,
        relativePath: group.videos[0]?.relativePath ?? directory,
        duration,
        description: description?.trim() || undefined,
        renditions,
      });
    }
  }
  return { entries, ignoredCount, duplicateFormatCount, processedFiles };
}

function parseQualityFilename(fileName: string): { height: number; formatId?: string } | undefined {
  const stem = fileName.replace(/\.[^.]+$/, '');
  const match = /^(\d{2,4})p(?:_(.+))?$/i.exec(stem);
  if (!match) return undefined;
  const height = Number.parseInt(match[1], 10);
  return Number.isFinite(height) ? { height, formatId: match[2] } : undefined;
}

function isMetadataFile(file: File): boolean {
  const lowerName = file.name.toLowerCase();
  return lowerName.endsWith('.info.json') || lowerName.endsWith('.description');
}

function leafName(path: string): string {
  return path.split('/').filter(Boolean).at(-1) ?? '';
}

function datasetFolderTitle(folderName: string): string {
  return folderName.replace(/_[A-Za-z0-9_-]{10,12}$/, '').trim();
}

function finiteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0;
}

function parseDuration(value: unknown): number {
  if (typeof value !== 'string') return 0;
  const pieces = value.split(':').map(item => Number.parseInt(item, 10));
  if (pieces.some(item => !Number.isFinite(item))) return 0;
  return pieces.reduce((total, part) => total * 60 + part, 0);
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
  return VIDEO_EXTENSIONS.has(extension(file.name));
}

function withVideoType(file: File): File {
  if (file.type.startsWith('video/')) return file;
  const contentTypes: Record<string, string> = {
    mp4: 'video/mp4', mov: 'video/quicktime', webm: 'video/webm', mkv: 'video/x-matroska',
  };
  return new File([file], file.name, { type: contentTypes[extension(file.name)] ?? 'video/mp4', lastModified: file.lastModified });
}

async function readVideoMetadata(file: File): Promise<CfSeedVideoMetadata> {
  const url = URL.createObjectURL(file);
  try {
    return await new Promise((resolve, reject) => {
      const video = document.createElement('video');
      const timeout = window.setTimeout(() => reject(new Error('Không đọc được metadata video sau 30 giây.')), 30_000);
      video.preload = 'metadata';
      video.onloadedmetadata = () => {
        window.clearTimeout(timeout);
        if (!Number.isFinite(video.duration) || video.duration <= 0) reject(new Error('Thời lượng video không hợp lệ.'));
        else resolve({ duration: Math.max(1, Math.ceil(video.duration)), width: video.videoWidth, height: video.videoHeight });
      };
      video.onerror = () => { window.clearTimeout(timeout); reject(new Error('File video bị lỗi hoặc trình duyệt không hỗ trợ codec.')); };
      video.src = url;
    });
  } finally { URL.revokeObjectURL(url); }
}

function highestQualityForHeight(height: number): number {
  return [...QUALITY_HEIGHTS].reverse().find(value => value <= height) ?? 0;
}

function formatBytes(bytes: number): string {
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
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
