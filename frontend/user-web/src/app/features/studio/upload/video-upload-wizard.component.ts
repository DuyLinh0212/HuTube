import { Component, ElementRef, HostListener, OnDestroy, ViewChild, effect, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { I18nService } from '../../../core/i18n.service';
import { TranslatePipe } from '../../../core/translate.pipe';
import { ChannelService } from '../../../core/channel.service';
import { Category, ContentService, UploadPreflight } from '../../../core/content.service';
import { UploadStateService } from '../../../core/upload-state.service';

export interface Chapter {
  id: number;
  title: string;
  time: string;
}

interface ThumbnailOption {
  id: number;
  url: string;
  label: string;
}

@Component({
  selector: 'app-video-upload-wizard',
  imports: [CommonModule, FormsModule, TranslatePipe],
  templateUrl: './video-upload-wizard.component.html',
  styleUrl: './video-upload-wizard.component.scss'
})
export class VideoUploadWizardComponent implements OnDestroy {
  readonly i18n = inject(I18nService);
  private readonly router = inject(Router);
  private readonly channels = inject(ChannelService);
  private readonly content = inject(ContentService);
  readonly uploadState = inject(UploadStateService);

  @ViewChild('previewPlayer') private previewPlayer?: ElementRef<HTMLVideoElement>;
  @ViewChild('timelineTrack') private timelineTrack?: ElementRef<HTMLDivElement>;
  @ViewChild('newChapterTitleInput') private newChapterTitleInput?: ElementRef<HTMLInputElement>;

  readonly currentStep = signal<number>(1);
  readonly uploadProgress = signal<number>(0);
  readonly isUploading = signal<boolean>(false);
  readonly hasFile = signal<boolean>(false);
  readonly isFileDragActive = signal<boolean>(false);
  readonly isPreparing = signal<boolean>(false);
  readonly uploadError = signal('');
  readonly preflightError = signal('');
  readonly preflight = signal<UploadPreflight | null>(null);
  readonly preflightLoading = signal(false);
  readonly categoryOptions = signal<Category[]>([]);
  readonly previewVideoUrl = signal('');
  readonly previewPlaying = signal(false);
  readonly timelineSeconds = signal(0);

  private channelId = '';
  private selectedFile?: File;
  private thumbnailFile?: File;
  private videoObjectUrl = '';
  private thumbnailObjectUrls: string[] = [];
  private thumbnailFiles = new Map<number, File>();
  private customThumbnailId = 10_000;
  private handledUploadVideoId: string | null = null;
  private activeDrag: 'timeline' | 'chapter' | null = null;
  private draggedChapterId: number | null = null;

  duration = 0;
  videoWidth = 0;
  videoHeight = 0;
  fileType = '';
  sourceQuality = '720p';
  readonly sourceQualityOptions = ['360p', '480p', '720p', '1080p', '1440p', '2160p'];

  // Video Details (Step 2)
  videoTitle = '';
  videoDesc = '';
  selectedThumbnail = 0;
  category = '';
  tags = signal<string[]>([]);
  newTag = '';
  videoLang = 'vi';
  thumbnails: ThumbnailOption[] = [];

  // Chapters (Step 3)
  chapters = signal<Chapter[]>([]);
  newChapterTitle = '';
  newChapterTime = '';
  autoSubtitles = true;

  // Visibility (Step 5)
  visibility = 'private';
  publishMode = 'now';
  scheduleDate = '2026-09-15';
  scheduleTime = '19:00';
  allowComments = true;
  selectedPlaylist = 'dalat-trips';

  // Step 6 State
  readonly copied = signal(false);
  publishedVideoUrl = '';

  constructor() {
    this.channels.getMyChannel().subscribe({
      next: channel => {
        this.channelId = channel.channelId;
        this.runPreflight();
      }
    });
    this.content.categories().subscribe({ next: items => this.categoryOptions.set(items) });

    effect(() => {
      const state = this.uploadState.state();
      this.uploadProgress.set(state.progress);
      this.isUploading.set(state.phase === 'uploading' || state.phase === 'processing');
      if (state.phase === 'failed' && state.error) this.uploadError.set(state.error);
      if (state.phase === 'completed' && state.video && this.handledUploadVideoId !== state.video.videoId) {
        this.handledUploadVideoId = state.video.videoId;
        this.publishedVideoUrl = `${location.origin}/watch/${state.video.videoId}`;
        this.currentStep.set(6);
        window.scrollTo({ top: 0, behavior: 'smooth' });
      }
      if (state.phase === 'idle') this.handledUploadVideoId = null;
    });
  }

  selectVideo(event: Event) {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (file) this.acceptVideoFile(file);
  }

  onVideoDragOver(event: DragEvent) {
    event.preventDefault();
    this.isFileDragActive.set(true);
  }

  onVideoDragLeave(event: DragEvent) {
    event.preventDefault();
    this.isFileDragActive.set(false);
  }

  onVideoDrop(event: DragEvent) {
    event.preventDefault();
    this.isFileDragActive.set(false);
    const file = event.dataTransfer?.files?.[0];
    if (file) this.acceptVideoFile(file);
  }

  private acceptVideoFile(file: File) {
    const extension = file.name.split('.').pop()?.toLowerCase() ?? '';
    const supported = file.type.startsWith('video/') || ['mp4', 'webm', 'mov', 'mkv'].includes(extension);
    if (!supported) {
      this.uploadError.set('File không phải định dạng video được hỗ trợ. Chọn MP4, WebM, MOV hoặc MKV.');
      return;
    }
    this.releaseVideoResources();
    this.selectedFile = file;
    this.hasFile.set(true);
    this.uploadError.set('');
    this.preflightError.set('');
    this.preflight.set(null);
    this.preflightLoading.set(false);
    this.fileType = file.type || this.typeFromName(file.name);
    this.videoTitle = file.name.replace(/\.[^.]+$/, '').slice(0, 100);
    this.thumbnails = [];
    this.thumbnailFile = undefined;
    this.thumbnailFiles.clear();
    this.selectedThumbnail = 0;
    this.isPreparing.set(true);
    this.previewPlaying.set(false);
    this.timelineSeconds.set(0);
    void this.prepareVideo(file);
  }

  private async prepareVideo(file: File) {
    const objectUrl = URL.createObjectURL(file);
    this.videoObjectUrl = objectUrl;
    this.previewVideoUrl.set(objectUrl);
    const video = document.createElement('video');
    video.preload = 'auto';
    video.muted = true;
    video.playsInline = true;
    video.src = objectUrl;
    try {
      await this.loadVideoMetadata(video);
      if (this.selectedFile !== file) return;
      this.duration = Math.max(1, Math.round(Number.isFinite(video.duration) ? video.duration : 1));
      this.videoWidth = video.videoWidth;
      this.videoHeight = video.videoHeight;
      this.sourceQuality = this.detectQuality(this.videoHeight);
      await this.generateThumbnails(video, file);
      if (this.selectedFile === file) this.runPreflight();
    } catch {
      if (this.selectedFile === file) this.uploadError.set('Không đọc được thông tin video. File có thể bị hỏng hoặc trình duyệt không hỗ trợ định dạng này.');
    } finally {
      if (this.selectedFile === file) this.isPreparing.set(false);
      video.removeAttribute('src');
      video.load();
    }
  }

  private loadVideoMetadata(video: HTMLVideoElement): Promise<void> {
    return new Promise((resolve, reject) => {
      const cleanup = () => {
        video.removeEventListener('loadedmetadata', loaded);
        video.removeEventListener('error', failed);
      };
      const loaded = () => { cleanup(); resolve(); };
      const failed = () => { cleanup(); reject(new Error('VIDEO_METADATA_ERROR')); };
      video.addEventListener('loadedmetadata', loaded, { once: true });
      video.addEventListener('error', failed, { once: true });
      video.load();
    });
  }

  private async generateThumbnails(video: HTMLVideoElement, file: File) {
    if (video.readyState < 2) await this.waitForLoadedData(video);
    const randomPoint = this.randomFrameFraction();
    const points = [randomPoint, 0.42, 0.76];
    const files: File[] = [];
    const duration = Number.isFinite(video.duration) ? video.duration : this.duration;
    for (let index = 0; index < points.length; index++) {
      const seconds = Math.min(Math.max(duration * points[index], 0.05), Math.max(duration - 0.05, 0));
      await this.seekVideo(video, seconds);
      const thumbnail = await this.captureFrame(video, index + 1);
      if (thumbnail) files.push(thumbnail);
    }
    if (this.selectedFile !== file) return;
    this.thumbnailFiles.clear();
    this.thumbnails = files.map((thumbnail, index) => {
      const id = index;
      const url = URL.createObjectURL(thumbnail);
      this.thumbnailObjectUrls.push(url);
      this.thumbnailFiles.set(id, thumbnail);
      return { id, url, label: `Khung hình ${index + 1}` };
    });
    this.selectedThumbnail = this.thumbnails[0]?.id ?? 0;
    this.thumbnailFile = files[0];
  }

  private randomFrameFraction() {
    const bytes = new Uint32Array(1);
    if (globalThis.crypto?.getRandomValues) globalThis.crypto.getRandomValues(bytes);
    else bytes[0] = Math.floor(Math.random() * 0xffffffff);
    return 0.08 + (bytes[0] / 0xffffffff) * 0.84;
  }

  private waitForLoadedData(video: HTMLVideoElement): Promise<void> {
    return new Promise((resolve, reject) => {
      const loaded = () => { cleanup(); resolve(); };
      const failed = () => { cleanup(); reject(new Error('VIDEO_DATA_ERROR')); };
      const cleanup = () => {
        video.removeEventListener('loadeddata', loaded);
        video.removeEventListener('error', failed);
      };
      video.addEventListener('loadeddata', loaded, { once: true });
      video.addEventListener('error', failed, { once: true });
    });
  }

  private seekVideo(video: HTMLVideoElement, seconds: number): Promise<void> {
    return new Promise(resolve => {
      if (Math.abs(video.currentTime - seconds) < 0.01) { resolve(); return; }
      const seeked = () => { video.removeEventListener('seeked', seeked); resolve(); };
      video.addEventListener('seeked', seeked, { once: true });
      video.currentTime = seconds;
    });
  }

  private captureFrame(video: HTMLVideoElement, index: number): Promise<File | null> {
    const canvas = document.createElement('canvas');
    const sourceWidth = video.videoWidth || 1280;
    const sourceHeight = video.videoHeight || 720;
    const width = Math.min(sourceWidth, 1280);
    const height = Math.round(width * 9 / 16);
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext('2d');
    if (!context) return Promise.resolve(null);
    const sourceAspect = sourceWidth / sourceHeight;
    const targetAspect = 16 / 9;
    let cropWidth = sourceWidth;
    let cropHeight = sourceHeight;
    let sourceX = 0;
    let sourceY = 0;
    if (sourceAspect > targetAspect) {
      cropWidth = sourceHeight * targetAspect;
      sourceX = (sourceWidth - cropWidth) / 2;
    } else if (sourceAspect < targetAspect) {
      cropHeight = sourceWidth / targetAspect;
      sourceY = (sourceHeight - cropHeight) / 2;
    }
    context.drawImage(video, sourceX, sourceY, cropWidth, cropHeight, 0, 0, width, height);
    return new Promise(resolve => {
      try {
        canvas.toBlob(blob => resolve(blob ? new File([blob], `thumbnail-${index}.jpg`, { type: 'image/jpeg' }) : this.canvasDataUrlFile(canvas, index)), 'image/jpeg', 0.88);
      } catch {
        resolve(this.canvasDataUrlFile(canvas, index));
      }
    });
  }

  private canvasDataUrlFile(canvas: HTMLCanvasElement, index: number): File | null {
    try {
      const dataUrl = canvas.toDataURL('image/jpeg', 0.88);
      const [header, data] = dataUrl.split(',');
      if (!header || !data) return null;
      const binary = atob(data);
      const bytes = new Uint8Array(binary.length);
      for (let offset = 0; offset < binary.length; offset++) bytes[offset] = binary.charCodeAt(offset);
      return new File([bytes], `thumbnail-${index}.jpg`, { type: 'image/jpeg' });
    } catch {
      return null;
    }
  }

  selectThumbnail(event: Event) {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (!file) return;
    const id = this.customThumbnailId++;
    const url = URL.createObjectURL(file);
    this.thumbnailObjectUrls.push(url);
    this.thumbnails = [...this.thumbnails, { id, url, label: 'Tùy chỉnh' }];
    this.thumbnailFiles.set(id, file);
    this.chooseThumbnail(id);
  }

  chooseThumbnail(id: number) {
    this.selectedThumbnail = id;
    this.thumbnailFile = this.thumbnailFiles.get(id);
  }

  cancelFile() {
    if (this.isUploading()) this.uploadState.cancel();
    this.releaseVideoResources();
    this.selectedFile = undefined;
    this.thumbnailFile = undefined;
    this.hasFile.set(false);
    this.isPreparing.set(false);
    this.preflight.set(null);
    this.preflightError.set('');
    this.uploadProgress.set(0);
  }

  private releaseVideoResources() {
    if (this.videoObjectUrl) URL.revokeObjectURL(this.videoObjectUrl);
    this.videoObjectUrl = '';
    this.previewVideoUrl.set('');
    this.thumbnailObjectUrls.forEach(url => URL.revokeObjectURL(url));
    this.thumbnailObjectUrls = [];
    this.thumbnailFiles.clear();
  }

  private runPreflight() {
    const file = this.selectedFile;
    if (!file || !this.channelId || this.duration <= 0 || !this.sourceQuality) return;
    this.preflightLoading.set(true);
    this.preflightError.set('');
    this.content.preflight({ channelId: this.channelId, fileSize: file.size, duration: this.duration, contentType: this.fileType, sourceQuality: this.sourceQuality }).subscribe({
      next: value => {
        if (this.selectedFile === file) this.preflight.set(value);
        this.preflightLoading.set(false);
      },
      error: error => {
        if (this.selectedFile === file) this.preflightError.set(this.readError(error));
        this.preflightLoading.set(false);
      }
    });
  }

  onSourceQualityChange(value: string) {
    this.sourceQuality = this.isQualityAboveSource(value) ? this.detectQuality(this.videoHeight) : value;
    this.runPreflight();
  }

  isQualityAboveSource(quality: string) {
    return this.videoHeight > 0 && this.qualityHeight(quality) > this.videoHeight;
  }

  setStep(step: number) {
    if (step < 1 || step > 6) return;
    if (step > 1 && step < 6 && !this.selectedFile) {
      this.uploadError.set('Vui lòng chọn file video trước.');
      return;
    }
    this.currentStep.set(step);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  nextStep() {
    if (this.currentStep() === 1) {
      if (!this.selectedFile) { this.uploadError.set('Vui lòng chọn file video.'); return; }
      if (this.isPreparing()) { this.uploadError.set('Đang đọc video và tạo hình thu nhỏ, vui lòng chờ một chút.'); return; }
      if (this.preflightLoading()) { this.uploadError.set('Đang kiểm tra dung lượng lưu trữ, vui lòng chờ một chút.'); return; }
      if (this.preflightError() || !this.preflight()) { this.uploadError.set(this.preflightError() || 'Chưa kiểm tra được file với máy chủ.'); return; }
    }
    if (this.currentStep() === 2 && !this.videoTitle.trim()) { this.uploadError.set('Vui lòng nhập tiêu đề video.'); return; }
    if (this.currentStep() === 3 && !this.validateChapters()) return;
    if (this.currentStep() === 5) { this.submitUpload(); return; }
    if (this.currentStep() < 6) {
      this.currentStep.update(s => s + 1);
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }
  }

  private submitUpload() {
    if (!this.selectedFile || !this.channelId || this.isUploading()) return;
    if (!this.videoTitle.trim()) { this.uploadError.set('Vui lòng nhập tiêu đề video.'); this.setStep(2); return; }
    if (!this.validateChapters()) { this.setStep(3); return; }
    const data = new FormData();
    data.append('ChannelId', this.channelId);
    data.append('Title', this.videoTitle.trim());
    data.append('Description', this.videoDesc.trim());
    if (this.category) data.append('CategoryId', this.category);
    data.append('LanguageCode', this.videoLang);
    data.append('Visibility', this.visibility);
    data.append('AgeRestricted', 'false');
    data.append('Duration', String(this.duration || 1));
    data.append('SourceQuality', this.sourceQuality);
    data.append('Video', this.selectedFile, this.selectedFile.name);
    if (this.thumbnailFile) data.append('Thumbnail', this.thumbnailFile, this.thumbnailFile.name);
    this.tags().forEach(tag => data.append('Tags', tag));
    data.append('ChaptersJson', JSON.stringify(this.chapters().map(chapter => ({ startSeconds: this.toSeconds(chapter.time), title: chapter.title.trim() }))));
    this.uploadError.set('');
    if (!this.uploadState.start(data, this.selectedFile.name, this.visibility === 'unlisted'))
      this.uploadError.set('Đang có một video khác được tải lên.');
  }

  private validateChapters(): boolean {
    let previous = -1;
    for (const chapter of this.chapters()) {
      const seconds = this.toSeconds(chapter.time);
      if (!chapter.title.trim() || seconds < 0 || seconds >= this.duration || seconds <= previous) {
        this.uploadError.set('Các chương phải có tiêu đề, mốc thời gian tăng dần và nằm trong video.');
        return false;
      }
      previous = seconds;
    }
    return true;
  }

  togglePreview(event?: Event) {
    event?.stopPropagation();
    const player = this.previewPlayer?.nativeElement;
    if (!player) return;
    if (player.paused) void player.play().catch(() => this.uploadError.set('Trình duyệt không thể phát bản xem trước của file này.'));
    else player.pause();
  }

  onPreviewTimeUpdate(event: Event) {
    const player = event.target as HTMLVideoElement;
    this.timelineSeconds.set(player.currentTime || 0);
  }

  beginTimelineDrag(event: PointerEvent) {
    event.preventDefault();
    this.activeDrag = 'timeline';
    (event.currentTarget as HTMLElement).setPointerCapture?.(event.pointerId);
    this.updateTimelineAt(event.clientX);
  }

  beginChapterDrag(event: PointerEvent, id: number) {
    event.preventDefault();
    event.stopPropagation();
    this.activeDrag = 'chapter';
    this.draggedChapterId = id;
    (event.currentTarget as HTMLElement).setPointerCapture?.(event.pointerId);
    this.updateTimelineAt(event.clientX);
  }

  @HostListener('document:pointermove', ['$event'])
  onPointerMove(event: PointerEvent) {
    if (this.activeDrag) this.updateTimelineAt(event.clientX);
  }

  @HostListener('document:pointerup')
  onPointerUp() {
    this.activeDrag = null;
    this.draggedChapterId = null;
  }

  private updateTimelineAt(clientX: number) {
    const track = this.timelineTrack?.nativeElement;
    if (!track || this.duration <= 0) return;
    const bounds = track.getBoundingClientRect();
    const ratio = Math.min(1, Math.max(0, (clientX - bounds.left) / bounds.width));
    const seconds = Math.round(ratio * this.duration);
    if (this.activeDrag === 'chapter' && this.draggedChapterId !== null) {
      this.updateChapterTime(this.draggedChapterId, this.formatDuration(seconds));
      return;
    }
    this.seekTo(seconds);
  }

  private seekTo(seconds: number) {
    const value = Math.min(this.duration, Math.max(0, seconds));
    this.timelineSeconds.set(value);
    const player = this.previewPlayer?.nativeElement;
    if (player) player.currentTime = value;
  }

  chapterPercent(chapter: Chapter) {
    return this.duration > 0 ? Math.min(100, Math.max(0, this.toSeconds(chapter.time) * 100 / this.duration)) : 0;
  }

  timelinePercent() {
    return this.duration > 0 ? Math.min(100, Math.max(0, this.timelineSeconds() * 100 / this.duration)) : 0;
  }

  timelineLabel() { return `${this.formatDuration(this.timelineSeconds())} / ${this.formatDuration(this.duration)}`; }

  updateChapterTitle(id: number, title: string) {
    this.chapters.update(items => items.map(item => item.id === id ? { ...item, title } : item));
  }

  updateChapterTime(id: number, time: string) {
    this.chapters.update(items => {
      const updated = items.map(item => item.id === id ? { ...item, time } : item);
      return this.toSeconds(time) >= 0
        ? updated.sort((a, b) => this.toSeconds(a.time) - this.toSeconds(b.time))
        : updated;
    });
  }

  isChapterValid(id: number) {
    const items = this.chapters();
    const index = items.findIndex(item => item.id === id);
    if (index < 0) return false;
    const seconds = this.toSeconds(items[index].time);
    const previous = index > 0 ? this.toSeconds(items[index - 1].time) : -1;
    return items[index].title.trim().length > 0 && seconds >= 0 && seconds < this.duration && seconds > previous;
  }

  prevStep() {
    if (this.currentStep() > 1) {
      this.currentStep.update(s => s - 1);
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }
  }

  addTag() {
    const val = this.newTag.trim().toLowerCase().replace(/[^a-z0-9\-]/g, '-');
    if (val && !this.tags().includes(val)) {
      this.tags.update(t => [...t, val]);
      this.newTag = '';
    }
  }

  removeTag(tag: string) { this.tags.update(t => t.filter(x => x !== tag)); }

  addChapter() {
    const title = this.newChapterTitle.trim();
    const time = this.newChapterTime.trim();
    const seconds = this.toSeconds(time);
    if (!title || seconds < 0 || seconds >= this.duration) {
      this.uploadError.set('Nhập tiêu đề và mốc thời gian hợp lệ trong video.');
      return;
    }
    if (this.chapters().some(item => this.toSeconds(item.time) === seconds)) {
      this.uploadError.set('Mỗi mốc thời gian chỉ được dùng cho một chương.');
      return;
    }
    this.chapters.update(items => [...items, { id: Math.max(0, ...items.map(item => item.id)) + 1, title, time }]
      .sort((a, b) => this.toSeconds(a.time) - this.toSeconds(b.time)));
    this.newChapterTitle = '';
    this.newChapterTime = '';
    this.uploadError.set('');
  }

  useCurrentTimeForChapter() {
    this.newChapterTime = this.formatDuration(this.timelineSeconds());
    this.uploadError.set('');
    setTimeout(() => this.newChapterTitleInput?.nativeElement.focus());
  }

  removeChapter(id: number) { this.chapters.update(items => items.filter(item => item.id !== id)); }

  copyLink() {
    navigator.clipboard.writeText(this.publishedVideoUrl).then(() => {
      this.copied.set(true);
      setTimeout(() => this.copied.set(false), 2500);
    });
  }

  resetWizard() {
    this.uploadState.reset();
    this.releaseVideoResources();
    this.selectedFile = undefined;
    this.thumbnailFile = undefined;
    this.currentStep.set(1);
    this.hasFile.set(false);
    this.uploadProgress.set(0);
    this.uploadError.set('');
    this.preflight.set(null);
    this.publishedVideoUrl = '';
    this.videoTitle = '';
    this.videoDesc = '';
    this.chapters.set([]);
    this.tags.set([]);
    this.thumbnails = [];
  }

  navigateToContent() { this.router.navigate(['/studio/content']); }

  selectedThumbnailUrl() { return this.thumbnails.find(item => item.id === this.selectedThumbnail)?.url ?? ''; }
  selectedFileName() { return this.selectedFile?.name ?? ''; }
  fileSizeLabel() { return this.formatBytes(this.selectedFile?.size ?? 0); }
  formatDuration(seconds: number) {
    const value = Math.max(0, Math.round(seconds || 0));
    const hours = Math.floor(value / 3600);
    const minutes = Math.floor((value % 3600) / 60);
    const remainder = value % 60;
    return hours > 0 ? `${hours}:${String(minutes).padStart(2, '0')}:${String(remainder).padStart(2, '0')}` : `${minutes}:${String(remainder).padStart(2, '0')}`;
  }
  formatBytes(value: number) {
    if (value <= 0) return '—';
    if (value < 1024) return `${value} B`;
    const units = ['KB', 'MB', 'GB', 'TB'];
    let size = value; let index = -1;
    do { size /= 1024; index++; } while (size >= 1024 && index < units.length - 1);
    return `${size.toFixed(size >= 10 ? 0 : 1)} ${units[index]}`;
  }
  formatType() {
    const type = this.fileType || 'video/unknown';
    const extension = this.selectedFile?.name.split('.').pop()?.toUpperCase() || type.split('/').pop()?.toUpperCase() || 'VIDEO';
    return `${extension} (${type})`;
  }
  resolutionLabel() { return this.videoWidth > 0 && this.videoHeight > 0 ? `${this.videoWidth}×${this.videoHeight} · ${this.sourceQuality}` : 'Đang đọc…'; }
  storagePercent() {
    const value = this.preflight();
    return value && value.storageLimit > 0 ? Math.min(100, value.storageUsed * 100 / value.storageLimit) : 0;
  }
  storageUsageLabel() {
    const value = this.preflight();
    return value ? `${this.formatBytes(value.storageUsed)} / ${this.formatBytes(value.storageLimit)}` : (this.preflightLoading() ? 'Đang kiểm tra…' : 'Chưa có dữ liệu');
  }
  storageRemainingLabel() { const value = this.preflight(); return value ? `Còn lại ${this.formatBytes(value.storageRemaining)}` : ''; }

  private toSeconds(value: string) {
    const parts = value.trim().split(':');
    if (!parts.length || parts.some(part => !/^\d+(?:\.\d+)?$/.test(part))) return -1;
    const numbers = parts.map(Number);
    if (numbers.length === 1) return Math.round(numbers[0]);
    if (numbers.length === 2) return numbers[0] * 60 + numbers[1];
    if (numbers.length === 3) return numbers[0] * 3600 + numbers[1] * 60 + numbers[2];
    return -1;
  }

  private detectQuality(height: number) {
    return height >= 2160 ? '2160p' : height >= 1440 ? '1440p' : height >= 1080 ? '1080p' : height >= 720 ? '720p' : height >= 480 ? '480p' : height >= 360 ? '360p' : '240p';
  }

  private qualityHeight(quality: string) {
    return Number.parseInt(quality, 10) || 0;
  }

  private typeFromName(name: string) {
    const extension = name.split('.').pop()?.toLowerCase();
    return extension === 'webm' ? 'video/webm' : extension === 'mov' ? 'video/quicktime' : extension === 'mkv' ? 'video/x-matroska' : 'video/mp4';
  }

  private readError(error: any) {
    if (error?.status === 404) return 'API hiện tại chưa có endpoint này. Hãy khởi động lại backend local hoặc redeploy API trước khi tải lên.';
    if (error?.status === 0) return 'Không thể kết nối API. Kiểm tra backend, CORS và thử lại.';
    return error?.error?.detail || error?.error?.title || error?.message || 'Không thể kiểm tra file với máy chủ.';
  }

  ngOnDestroy() { this.releaseVideoResources(); }
}
