import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { Component, OnDestroy, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { errorMessage } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { RuntimeConfig } from '../../core/runtime-config';
import { TranslatePipe } from '../../core/translate.pipe';

interface Counts { pairs: number; users: number; videos: number; }
interface MatrixPreview {
  columns: string[]; rows: string[][]; total: number;
  displayColumns?: string[]; displayRows?: string[][];
}
interface MatrixDiff {
  state: 'ready' | 'uninitialized'; modelVersion: string | null; csvKey: string | null;
  csvSha256: string | null; updatedAt: string | null; active: Counts; current: Counts;
  added: number; changed: number; removed: number; changeRate: number; modelAlgorithm: string | null;
}
interface Person { userId: string; username: string; displayName: string; isBot: boolean; }
interface Category { categoryId: string; name: string; slug: string; }
interface Video {
  videoId: string; channelId: string; title: string; duration: number;
  categoryId?: string | null; categoryName?: string; categorySlug?: string;
}
interface VideoPage { items: Video[]; page: number; pageSize: number; total: number; }
interface Job {
  jobId: string; kind: string; status: string; step: string;
  completed: number; total: number; logsJson: string; error: string | null;
}
const MAX_SIMULATION_USERS = 200;
const MAX_SIMULATION_VIDEOS = 10_000;
const MAX_SIMULATION_ACTIONS_PER_USER = 1_000;
const MAX_SIMULATION_ACTIONS = 10_000;

type SimulatorTab = 'target' | 'cluster' | 'comments';
type PageTab = 'model' | 'simulation';
type ScoreMode = 'average' | 'weighted';
type ScoreFeature = 'rating' | 'like' | 'dislike' | 'watch' | 'comment' | 'subscribe';
type ModelAlgorithm = 'item_based' | 'incremental' | 'batch_incremental' | 'batch_incremental_partial_topk';
interface ConsoleEntry {
  timestamp: string; userId: string; behavior: string; videoId: string | null; watchPercent: number | null; error: string;
}

@Component({
  selector: 'app-recommendations-page', standalone: true,
  imports: [CommonModule, FormsModule, TranslatePipe],
  templateUrl: './recommendations-page.html', styleUrl: './recommendations-page.scss',
})
export class RecommendationsPage implements OnInit, OnDestroy {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);
  private readonly i18n = inject(I18nService);
  private pollHandle?: ReturnType<typeof setInterval>;
  private readonly base = () => `${this.config.apiBaseUrl}/admin/recommendations`;

  readonly diff = signal<MatrixDiff | null>(null);
  readonly preview = signal<MatrixPreview | null>(null);
  readonly modelPreviewVisible = signal(false);
  readonly users = signal<Person[]>([]);
  readonly categories = signal<Category[]>([]);
  readonly videos = signal<Video[]>([]);
  readonly loadingVideos = signal(false);
  readonly videoPage = signal(0);
  readonly videoTotal = signal(0);
  readonly videoHasMore = signal(false);
  readonly job = signal<Job | null>(null);
  readonly activePageTab = signal<PageTab>('model');
  readonly activeSimulatorTab = signal<SimulatorTab>('target');
  readonly commentCategory = signal('default');
  readonly commentBanks = signal<Record<string, string[]>>({});
  readonly logClearOffset = signal(0);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly notice = signal('');
  readonly selectedUsers = new Set<string>();
  private readonly selectedPeople = new Map<string, Person>();
  readonly selectedVideos = new Set<string>();
  private readonly videoLookup = new Map<string, Video>();
  private videoLoadRequest = 0;
  private readonly commentBankStorageKey = 'hutube.admin.recommendations.comment-bank.v1';

  userSearch = '';
  videoSearch = '';
  categorySearch = '';
  categoryPickerOpen = false;
  botPrefix = 'cfbot';
  quickBotName = '';
  botCount = 10;
  selectedCategoryId = '';
  readonly selectedCategoryIds = new Set<string>();
  categoryRates: Record<string, number> = {};
  mode: 'target' | 'cluster' = 'target';
  actionsPerUser = 5;
  videosPerBot = 15;
  preferredCategoryRatio = 80;
  delayMs = 0;
  viewRate = 100;
  likeRate = 70;
  dislikeRate = 20;
  ratingRate = 60;
  commentRate = 35;
  subscribeRate = 35;
  videoSkipRate = 20;
  newCommentTemplate = '';
  confirmRealUsers = false;
  scoreMode: ScoreMode = 'average';
  modelAlgorithm: ModelAlgorithm = 'batch_incremental_partial_topk';
  readonly modelAlgorithms: Array<{ value: ModelAlgorithm; labelKey: string; hintKey: string }> = [
    { value: 'item_based', labelKey: 'recommendations.algorithm.itemBased', hintKey: 'recommendations.algorithm.itemBasedHint' },
    { value: 'incremental', labelKey: 'recommendations.algorithm.incremental', hintKey: 'recommendations.algorithm.incrementalHint' },
    { value: 'batch_incremental', labelKey: 'recommendations.algorithm.batchIncremental', hintKey: 'recommendations.algorithm.batchIncrementalHint' },
    { value: 'batch_incremental_partial_topk', labelKey: 'recommendations.algorithm.partialTopK', hintKey: 'recommendations.algorithm.partialTopKHint' },
  ];
  readonly scoreFeatures: ScoreFeature[] = ['rating', 'like', 'dislike', 'watch', 'comment', 'subscribe'];
  scoreWeights: Record<ScoreFeature, number> = {
    rating: 1, like: 1, dislike: 1, watch: 1, comment: 1, subscribe: 1,
  };

  ngOnInit(): void {
    this.loadCommentBank();
    this.check();
    this.loadUsers();
    this.loadCategories();
    this.loadMatrix();
  }

  ngOnDestroy(): void {
    if (this.pollHandle) clearInterval(this.pollHandle);
  }

  check(): void {
    this.busy.set(true);
    this.error.set('');
    this.http.get<MatrixDiff>(`${this.base()}/status`).subscribe({
      next: value => { this.diff.set(value); this.busy.set(false); },
      error: err => { this.error.set(errorMessage(err, this.i18n)); this.busy.set(false); },
    });
  }

  loadUsers(): void {
    this.http.get<Person[]>(`${this.base()}/users`, { params: { search: this.userSearch } }).subscribe({
      next: value => this.users.set(value),
      error: err => this.error.set(errorMessage(err, this.i18n)),
    });
  }

  loadCategories(): void {
    this.http.get<Category[]>(`${this.base()}/categories`).subscribe({
      next: value => {
        this.categories.set(value);
        const available = new Set(value.map(category => category.categoryId));
        for (const id of [...this.selectedCategoryIds]) if (!available.has(id)) this.selectedCategoryIds.delete(id);
        if (!this.selectedCategoryIds.size && value[0]) this.selectedCategoryIds.add(value[0].categoryId);
        this.selectedCategoryId = [...this.selectedCategoryIds][0] ?? '';
        this.normalizeCategoryRates();
        if (!value.some(category => category.slug === this.commentCategory())) {
          this.commentCategory.set(value[0]?.slug ?? 'default');
        }
        this.loadVideos();
      },
      error: err => {
        this.error.set(errorMessage(err, this.i18n));
        this.loadVideos();
      },
    });
  }

  loadVideos(): void {
    this.videoPage.set(0);
    this.videoTotal.set(0);
    this.videoHasMore.set(false);
    this.videos.set([]);
    this.loadVideoPage(1, false);
  }

  loadMoreVideos(): void {
    if (this.loadingVideos() || !this.videoHasMore()) return;
    this.loadVideoPage(this.videoPage() + 1, true);
  }

  private loadVideoPage(page: number, append: boolean): void {
    const params: Record<string, string> = { search: this.videoSearch };
    if (this.mode === 'target' && this.selectedCategoryIds.size > 0)
      params['categoryIds'] = [...this.selectedCategoryIds].join(',');
    params['page'] = String(page);
    this.loadingVideos.set(true);
    const requestId = ++this.videoLoadRequest;
    this.http.get<VideoPage>(`${this.base()}/videos`, { params }).subscribe({
      next: result => {
        if (requestId !== this.videoLoadRequest) return;
        this.videos.set(append ? [...this.videos(), ...result.items] : result.items);
        result.items.forEach(video => this.videoLookup.set(video.videoId, video));
        this.videoPage.set(result.page);
        this.videoTotal.set(result.total);
        this.videoHasMore.set(result.page * result.pageSize < result.total);
        this.loadingVideos.set(false);
      },
      error: err => {
        if (requestId !== this.videoLoadRequest) return;
        this.error.set(errorMessage(err, this.i18n));
        this.loadingVideos.set(false);
      },
    });
  }

  onCategoryChanged(): void { this.loadVideos(); }

  filteredCategories(): Category[] {
    const term = this.categorySearch.trim().toLocaleLowerCase();
    return term
      ? this.categories().filter(category => `${category.name} ${category.slug}`.toLocaleLowerCase().includes(term))
      : this.categories();
  }

  isCategorySelected(categoryId: string): boolean { return this.selectedCategoryIds.has(categoryId); }

  selectedCategoryNames(): string {
    return this.categories().filter(category => this.selectedCategoryIds.has(category.categoryId)).map(category => category.name).join(', ');
  }

  toggleCategory(categoryId: string): void {
    if (this.selectedCategoryIds.has(categoryId)) this.selectedCategoryIds.delete(categoryId);
    else this.selectedCategoryIds.add(categoryId);
    this.selectedCategoryId = [...this.selectedCategoryIds][0] ?? '';
    this.normalizeCategoryRates();
    this.selectedVideos.clear();
    this.loadVideos();
  }

  selectAllCategories(): void {
    this.categories().forEach(category => this.selectedCategoryIds.add(category.categoryId));
    this.selectedCategoryId = [...this.selectedCategoryIds][0] ?? '';
    this.normalizeCategoryRates();
    this.selectedVideos.clear();
    this.loadVideos();
  }

  clearCategories(): void {
    this.selectedCategoryIds.clear();
    this.selectedCategoryId = '';
    this.categoryRates = {};
    this.selectedVideos.clear();
    this.loadVideos();
  }

  categoryRate(categoryId: string): number { return this.categoryRates[categoryId] ?? 0; }

  setCategoryRate(categoryId: string, value: number | string): void {
    if (!this.selectedCategoryIds.has(categoryId)) return;
    const numeric = Math.max(1, Math.min(10, Math.round(Number(value) || 1)));
    this.categoryRates = { ...this.categoryRates, [categoryId]: numeric };
  }

  private normalizeCategoryRates(): void {
    const ids = [...this.selectedCategoryIds];
    if (!ids.length) { this.categoryRates = {}; return; }
    const next: Record<string, number> = {};
    for (const id of ids) {
      next[id] = Math.max(1, Math.min(10, Math.round(this.categoryRates[id] ?? 1)));
    }
    this.categoryRates = next;
  }

  categoryPercent(categoryId: string): number {
    return this.normalizedCategoryRates().find(rate => rate.categoryId === categoryId)?.rate ?? 0;
  }

  categoryRatesPayload(): Array<{ categoryId: string; rate: number }> {
    return this.normalizedCategoryRates();
  }

  private normalizedCategoryRates(): Array<{ categoryId: string; rate: number }> {
    const entries = [...this.selectedCategoryIds].map(categoryId => ({
      categoryId,
      weight: Math.max(1, Math.min(10, Math.round(this.categoryRate(categoryId) || 1))),
    }));
    const total = entries.reduce((sum, entry) => sum + entry.weight, 0);
    if (!total) return [];

    const rounded = entries.map(entry => {
      const exact = entry.weight * 100 / total;
      return { categoryId: entry.categoryId, rate: Math.floor(exact), remainder: exact - Math.floor(exact) };
    });
    let remaining = 100 - rounded.reduce((sum, entry) => sum + entry.rate, 0);
    for (const entry of [...rounded].sort((a, b) => b.remainder - a.remainder)) {
      if (remaining <= 0) break;
      entry.rate++;
      remaining--;
    }
    return rounded.map(({ categoryId, rate }) => ({ categoryId, rate }));
  }

  toggleUser(person: Person): void {
    if (this.selectedUsers.has(person.userId)) {
      this.selectedUsers.delete(person.userId);
      this.selectedPeople.delete(person.userId);
    } else {
      this.selectedUsers.add(person.userId);
      this.selectedPeople.set(person.userId, person);
    }
  }

  toggleVideo(id: string): void {
    this.selectedVideos.has(id) ? this.selectedVideos.delete(id) : this.selectedVideos.add(id);
  }

  allVisibleVideosSelected(): boolean {
    const visible = this.videos();
    return visible.length > 0 && visible.every(video => this.selectedVideos.has(video.videoId));
  }

  toggleAllVideos(): void {
    if (this.allVisibleVideosSelected()) this.videos().forEach(video => this.selectedVideos.delete(video.videoId));
    else this.videos().forEach(video => this.selectedVideos.add(video.videoId));
  }

  selectAllUsers(): void {
    this.users().forEach(person => {
      this.selectedUsers.add(person.userId);
      this.selectedPeople.set(person.userId, person);
    });
  }

  clearSelectedUsers(): void {
    this.selectedUsers.clear();
    this.selectedPeople.clear();
    this.confirmRealUsers = false;
  }

  toggleSimulatorTab(tab: SimulatorTab): void {
    this.activeSimulatorTab.set(tab);
    if (tab === 'comments') return;
    this.mode = tab;
    this.selectedVideos.clear();
    if (!this.selectedCategoryIds.size && this.categories()[0]) {
      this.selectedCategoryIds.add(this.categories()[0].categoryId);
      this.selectedCategoryId = this.categories()[0].categoryId;
      this.normalizeCategoryRates();
    }
    this.loadVideos();
  }

  setPageTab(tab: PageTab): void {
    this.activePageTab.set(tab);
  }

  modelAlgorithmLabel(value: string | null): string {
    const normalized = value || 'item_based';
    const option = this.modelAlgorithms.find(item => item.value === normalized);
    return option ? this.i18n.t(option.labelKey) : normalized;
  }

  modelAlgorithmHint(): string {
    const option = this.modelAlgorithms.find(item => item.value === this.modelAlgorithm);
    return option ? this.i18n.t(option.hintKey) : '';
  }

  toggleModelPreview(): void {
    this.modelPreviewVisible.update(value => !value);
  }

  selectedCategoryName(): string {
    return this.categories().find(category => category.categoryId === this.selectedCategoryId)?.name ?? '';
  }

  categoryName(video: Video): string {
    return video.categoryName || this.categories().find(x => x.categoryId === video.categoryId)?.name || '';
  }

  commentsForActiveCategory(): string[] {
    const category = this.commentCategory();
    return this.commentBanks()[category] ?? this.commentBanks()['default'] ?? [];
  }

  addCommentTemplate(): void {
    const value = this.newCommentTemplate.trim();
    if (value.length < 3) return;
    const category = this.commentCategory();
    const next = {
      ...this.commentBanks(),
      [category]: [...this.commentsForActiveCategory(), value].slice(0, 100),
    };
    this.commentBanks.set(next);
    this.persistCommentBank(next);
    this.newCommentTemplate = '';
  }

  removeCommentTemplate(index: number): void {
    const category = this.commentCategory();
    const next = {
      ...this.commentBanks(),
      [category]: this.commentsForActiveCategory().filter((_, i) => i !== index),
    };
    this.commentBanks.set(next);
    this.persistCommentBank(next);
  }

  onLikeRateChange(): void {
    if (this.likeRate + this.dislikeRate > 100) this.dislikeRate = 100 - this.likeRate;
  }

  onDislikeRateChange(): void {
    if (this.likeRate + this.dislikeRate > 100) this.likeRate = 100 - this.dislikeRate;
  }

  hasRealUsers(): boolean {
    return [...this.selectedPeople.values()].some(person => !person.isBot);
  }

  rawLogs(): string[] {
    if (this.job()?.kind !== 'simulation') return [];
    try {
      const value: unknown = JSON.parse(this.job()?.logsJson ?? '[]');
      return Array.isArray(value) ? value.filter((line): line is string => typeof line === 'string') : [];
    } catch { return []; }
  }

  consoleEntries(): ConsoleEntry[] {
    return this.rawLogs().slice(this.logClearOffset()).map(line => {
      const match = line.match(/^(\S+)\s+(\S+)\s+([a-z_]+):?(?:\s+(.*))?$/i);
      if (!match) return { timestamp: '', userId: '', behavior: 'system', videoId: null, watchPercent: null, error: line };
      const tail = (match[4] ?? '').trim();
      const tailParts = tail.split(/\s+/).filter(Boolean);
      const first = tailParts[0] ?? '';
      const hasVideo = /^[\da-f-]{36}$/i.test(first);
      const parsedPercent = match[3].toLowerCase() === 'view' && hasVideo
        ? Number.parseInt((tailParts[1] ?? '').replace('%', ''), 10)
        : Number.NaN;
      return {
        timestamp: match[1], userId: match[2], behavior: match[3].toLowerCase(),
        videoId: hasVideo ? first : null,
        watchPercent: Number.isInteger(parsedPercent) && parsedPercent >= 1 && parsedPercent <= 100 ? parsedPercent : null,
        error: hasVideo ? '' : tail,
      };
    });
  }

  consoleUser(entry: ConsoleEntry): string {
    const person = this.selectedPeople.get(entry.userId) ?? this.users().find(x => x.userId === entry.userId);
    return person?.displayName || (entry.userId ? `${entry.userId.slice(0, 8)}…` : 'SYSTEM');
  }

  consoleVideo(entry: ConsoleEntry): string {
    if (!entry.videoId) return '';
    const video = this.videoLookup.get(entry.videoId) ?? this.videos().find(x => x.videoId === entry.videoId);
    return video?.title || `${entry.videoId.slice(0, 8)}…`;
  }

  consoleType(entry: ConsoleEntry): string {
    if (entry.error) return 'ERROR';
    const labels: Record<string, string> = {
      view: 'WATCH_PROGRESS', like: 'REACTION', dislike: 'REACTION',
      rating: 'RATING', subscribe: 'SUBSCRIBE', comment: 'COMMENT', skip: 'SKIP_VIDEO',
    };
    return labels[entry.behavior] ?? entry.behavior.toUpperCase();
  }

  consoleDetail(entry: ConsoleEntry): string {
    if (entry.error) return entry.error;
    const video = this.consoleVideo(entry);
    const title = video ? `“${video}”` : '';
    const details: Record<string, string> = {
      view: this.i18n.t('recommendations.event.view', { percent: String(entry.watchPercent ?? '1–100'), video: title }),
      like: this.i18n.t('recommendations.event.like', { video: title }),
      dislike: this.i18n.t('recommendations.event.dislike', { video: title }),
      rating: this.i18n.t('recommendations.event.rating', { video: title }),
      subscribe: this.i18n.t('recommendations.event.subscribe', { video: title }),
      comment: this.i18n.t('recommendations.event.comment', { video: title }),
      skip: this.i18n.t('recommendations.event.skip', { video: title }),
    };
    return details[entry.behavior] ?? title;
  }

  metrics(): { total: number; likes: number; comments: number; ratings: number; subscriptions: number; dislikes: number; views: number } {
    const successful = this.rawLogs().map(line => {
      const match = line.match(/^\S+\s+\S+\s+([a-z_]+):?(?:\s+(.*))?$/i);
      const firstDetail = (match?.[2] ?? '').trim().split(/\s+/, 1)[0];
      return match ? { behavior: match[1].toLowerCase(), error: !/^[\da-f-]{36}$/i.test(firstDetail) } : null;
    }).filter((entry): entry is { behavior: string; error: boolean } => !!entry && !entry.error);
    const count = (behavior: string) => successful.filter(entry => entry.behavior === behavior).length;
    const likes = count('like');
    const dislikes = count('dislike');
    const comments = count('comment');
    return {
      total: likes + dislikes + comments, likes, comments,
      ratings: count('rating'), subscriptions: count('subscribe'), dislikes, views: count('view'),
    };
  }

  isSimulationLive(): boolean {
    return this.job()?.kind === 'simulation' && ['queued', 'running', 'cancelling'].includes(this.job()?.status ?? '');
  }

  clearLogs(): void { this.logClearOffset.set(this.rawLogs().length); }

  progress(): number {
    const value = this.job();
    return value?.total ? Math.min(100, Math.round(value.completed * 100 / value.total)) : 0;
  }

  jobStatus(status: string): string {
    const known = ['queued', 'running', 'cancelling', 'cancelled', 'completed', 'failed'];
    return known.includes(status) ? this.i18n.t(`recommendations.job.${status}`) : status;
  }

  jobStep(step: string): string {
    const known = ['matrix', 'upload_csv', 'train_model', 'verify_manifest', 'interactions'];
    return known.includes(step) ? this.i18n.t(`recommendations.step.${step}`) : step;
  }

  scoreFeatureLabel(feature: ScoreFeature): string {
    return this.i18n.t(`recommendations.scoreFeature.${feature}`);
  }

  setScoreWeight(feature: ScoreFeature, value: number | string): void {
    const parsed = Number(value);
    this.scoreWeights = {
      ...this.scoreWeights,
      [feature]: Number.isFinite(parsed) && parsed >= 0 ? parsed : 0,
    };
  }

  updateModel(): void {
    if (this.busy()) return;
    if (this.scoreMode === 'weighted' && !this.scoreFeatures.some(feature => this.scoreWeights[feature] > 0)) {
      this.error.set(this.i18n.t('recommendations.scoreWeightsInvalid'));
      return;
    }
    this.busy.set(true);
    this.error.set('');
    this.notice.set('');
    const payload = this.scoreMode === 'weighted'
      ? { modelAlgorithm: this.modelAlgorithm, mode: this.scoreMode, weights: this.scoreWeights }
      : { modelAlgorithm: this.modelAlgorithm, mode: this.scoreMode };
    this.http.post<{ jobId: string }>(`${this.base()}/model-jobs`, payload).subscribe({
      next: value => { this.busy.set(false); this.watch(value.jobId); },
      error: err => { this.error.set(errorMessage(err, this.i18n)); this.busy.set(false); },
    });
  }

  createBots(): void { this.createBotBatch(this.botCount); }

  createQuickBot(): void {
    const displayName = this.quickBotName.trim();
    if (displayName.length < 2) {
      this.error.set(this.i18n.t('recommendations.quickBotNameRequired'));
      return;
    }
    this.createBotBatch(1, displayName);
  }

  private createBotBatch(count: number, displayName?: string): void {
    if (this.busy()) return;
    this.busy.set(true);
    this.error.set('');
    this.http.post<Person[]>(`${this.base()}/bots`, { count, prefix: this.botPrefix, displayName }).subscribe({
      next: value => {
        this.busy.set(false);
        this.users.set([...value, ...this.users()]);
        value.forEach(person => {
          this.selectedUsers.add(person.userId);
          this.selectedPeople.set(person.userId, person);
        });
        this.quickBotName = '';
        this.notice.set(this.i18n.t('recommendations.botsCreated', { count: String(value.length) }));
      },
      error: err => { this.error.set(errorMessage(err, this.i18n)); this.busy.set(false); },
    });
  }

  simulate(): void {
    if (this.busy() || this.activeSimulatorTab() === 'comments') return;
    if (this.activeSimulatorTab() === 'cluster') {
      this.runPersonaCluster();
      return;
    }
    const userIds = [...this.selectedUsers];
    const videoIds = [...this.selectedVideos];
    if (!userIds.length || !videoIds.length || !this.selectedCategoryIds.size) {
      this.error.set(this.i18n.t('recommendations.selectRequired'));
      return;
    }
    if (!this.validateSimulation(userIds.length, videoIds.length, 'target')) return;
    if (this.hasRealUsers() && !this.confirmRealUsers) {
      this.error.set(this.i18n.t('recommendations.confirmRequired'));
      return;
    }
    if (this.hasRealUsers() && !window.confirm(this.i18n.t('recommendations.confirmPrompt', { count: String(userIds.length) }))) return;
    this.startSimulation(userIds, videoIds, 'target');
  }

  private runPersonaCluster(): void {
    const videoIds = this.videos().map(video => video.videoId);
    if (!videoIds.length || !this.selectedCategoryIds.size) {
      this.error.set(this.i18n.t('recommendations.selectRequired'));
      return;
    }
    if (this.botCount < 1 || this.botCount > 100) {
      this.error.set(this.i18n.t('recommendations.botCountRange'));
      return;
    }
    if (!this.validateSimulation(this.botCount, videoIds.length, 'cluster')) return;
    this.busy.set(true);
    this.error.set('');
    this.notice.set('');
    this.http.post<Person[]>(`${this.base()}/bots`, { count: this.botCount, prefix: this.botPrefix }).subscribe({
      next: bots => {
        this.users.set([...bots, ...this.users()]);
        bots.forEach(person => {
          this.selectedUsers.add(person.userId);
          this.selectedPeople.set(person.userId, person);
        });
        this.startSimulation(bots.map(person => person.userId), videoIds, 'cluster');
      },
      error: err => { this.error.set(errorMessage(err, this.i18n)); this.busy.set(false); },
    });
  }

  private startSimulation(userIds: string[], videoIds: string[], mode: 'target' | 'cluster'): void {
    if (!this.validateSimulation(userIds.length, videoIds.length, mode)) return;
    this.busy.set(true);
    this.error.set('');
    this.notice.set('');
    this.logClearOffset.set(0);
    this.job.set(null);
    this.http.post<{ jobId: string }>(`${this.base()}/simulation-jobs`, {
      userIds, videoIds, mode,
      actionsPerUser: mode === 'cluster' ? this.videosPerBot : this.actionsPerUser,
      delayMs: this.delayMs,
      viewRate: this.viewRate, likeRate: this.likeRate, dislikeRate: this.dislikeRate,
      ratingRate: this.ratingRate, commentRate: this.commentRate, subscribeRate: this.subscribeRate,
      videoSkipRate: this.videoSkipRate,
      commentTemplates: this.commentsForActiveCategory().slice(0, 100),
      confirmRealUsers: mode === 'target' && this.confirmRealUsers,
      categoryRates: this.categoryRatesPayload(),
    }).subscribe({
      next: value => { this.busy.set(false); this.watch(value.jobId); },
      error: err => { this.error.set(errorMessage(err, this.i18n)); this.busy.set(false); },
    });
  }

  private validateSimulation(userCount: number, videoCount: number, mode: 'target' | 'cluster'): boolean {
    const actionsPerUser = Number(mode === 'cluster' ? this.videosPerBot : this.actionsPerUser);
    const delayMs = Number(this.delayMs);
    if (!Number.isInteger(userCount) || userCount < 1 || userCount > MAX_SIMULATION_USERS) {
      this.error.set(this.i18n.t('recommendations.simulationUserLimit'));
      return false;
    }
    if (!Number.isInteger(videoCount) || videoCount < 1 || videoCount > MAX_SIMULATION_VIDEOS) {
      this.error.set(this.i18n.t('recommendations.simulationVideoLimit'));
      return false;
    }
    if (!Number.isInteger(actionsPerUser) || actionsPerUser < 1 || actionsPerUser > MAX_SIMULATION_ACTIONS_PER_USER) {
      this.error.set(this.i18n.t('recommendations.simulationActionsRange'));
      return false;
    }
    if (userCount * actionsPerUser > MAX_SIMULATION_ACTIONS) {
      this.error.set(this.i18n.t('recommendations.simulationActionLimit'));
      return false;
    }
    if (!Number.isInteger(delayMs) || delayMs < 0 || delayMs > 5000) {
      this.error.set(this.i18n.t('recommendations.simulationDelayRange'));
      return false;
    }
    return true;
  }

  stop(): void {
    const id = this.job()?.jobId;
    if (!id) return;
    this.http.post(`${this.base()}/jobs/${id}/stop`, {}).subscribe({
      next: () => this.notice.set(this.i18n.t('recommendations.stopRequested')),
      error: err => this.error.set(errorMessage(err, this.i18n)),
    });
  }

  exportCsv(): void {
    this.http.get(`${this.base()}/matrix.csv`, { responseType: 'blob' }).subscribe({
      next: blob => {
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = 'interactions_current.csv';
        link.click();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      },
      error: err => this.error.set(errorMessage(err, this.i18n)),
    });
  }

  private loadMatrix(): void {
    this.http.get<MatrixPreview>(`${this.base()}/matrix-preview`).subscribe({
      next: value => this.preview.set(value.displayColumns?.length && value.displayRows
        ? { ...value, columns: value.displayColumns, rows: value.displayRows }
        : value),
      error: err => this.error.set(errorMessage(err, this.i18n)),
    });
  }

  private watch(id: string): void {
    if (this.pollHandle) clearInterval(this.pollHandle);
    this.refreshJob(id);
    this.pollHandle = setInterval(() => this.refreshJob(id), 2000);
  }

  private refreshJob(id: string): void {
    this.http.get<Job>(`${this.base()}/jobs/${id}`).subscribe({
      next: value => {
        this.job.set(value);
        setTimeout(() => {
          const consoleElement = document.getElementById('recommendation-live-console');
          if (consoleElement) consoleElement.scrollTop = consoleElement.scrollHeight;
        });
        if (['completed', 'failed', 'cancelled'].includes(value.status)) {
          if (this.pollHandle) clearInterval(this.pollHandle);
          this.pollHandle = undefined;
          if (value.status === 'completed') {
            this.notice.set(this.i18n.t('recommendations.jobCompleted'));
            this.check();
            if (value.kind === 'simulation') this.loadMatrix();
          }
          if (value.error) this.error.set(value.error);
        }
      },
      error: err => this.error.set(errorMessage(err, this.i18n)),
    });
  }

  matrixColumn(column: string): string {
    const key = `recommendations.matrix.column.${column}`;
    const translated = this.i18n.t(key);
    return translated === key ? column : translated;
  }

  matrixCell(column: string, value: string): string {
    if (column === 'watch_percent' && value) return `${value}%`;
    if (column === 'reaction' && value) return this.i18n.t(`recommendations.matrix.${value}`);
    if (column === 'subscription' && value) return this.i18n.t('recommendations.matrix.subscribed');
    return value || '—';
  }

  private defaultCommentBank(): Record<string, string[]> {
    return {
      music: [
        'Bài này nghe cuốn thật sự, replay từ sáng đến giờ không chán!',
        'Giai điệu bắt tai quá, beat đỉnh chóp luôn.',
        'Giọng hát truyền cảm và ca từ rất ý nghĩa.',
        'Đoạn điệp khúc nghe nổi da gà, quá xuất sắc!',
        'Hóng MV chính thức và các bản live tiếp theo của ca sĩ ạ.',
        'Một tác phẩm âm nhạc quá chất lượng, hòa âm phối khí đỉnh cao.',
        'Nhạc chill hợp nghe lúc làm việc hay thư giãn buổi tối ghê.',
        'Ca khúc này chắc chắn sẽ thành hit lớn trong năm nay!',
        'Nghe xong thấy thư thái và nhiều năng lượng tích cực hẳn.',
        'Phối khí hay quá, phần bass đánh rất tròn và đã tai.',
      ],
      'khoa-hoc': [
        'Video giải thích rất trực quan, dễ hiểu hơn hẳn lý thuyết trong sách vở.',
        'Kiến thức bổ ích và thực tế, cảm ơn tác giả đã chia sẻ tâm huyết!',
        'Thí nghiệm này ấn tượng thật sự, xem mở mang tầm mắt.',
        'Phần phân tích logic và dẫn chứng dữ liệu rất thuyết phục.',
        'Mong kênh tiếp tục ra thêm nhiều video chuyên sâu về chủ đề này ạ!',
        'Một góc nhìn khoa học rất mới mẻ và dễ tiếp cận cho mọi người.',
        'Giải thích ngắn gọn mà súc tích, người mới tìm hiểu xem cũng hiểu ngay.',
      ],
      'cong-nghe': [
        'Đánh giá chi tiết và khách quan, giúp mình có thêm căn cứ để chọn mua.',
        'Công nghệ mới này đột phá thật sự, tiềm năng ứng dụng rất lớn.',
        'Trải nghiệm thực tế hữu ích, phân tích rõ cả ưu điểm lẫn nhược điểm.',
        'Kênh cập nhật xu hướng công nghệ nhanh và chuẩn xác ghê.',
        'Cách giải thích nguyên lý hoạt động của thiết bị rất mạch lạc.',
      ],
      sports: [
        'Pha xử lý quá đẳng cấp, xem lại highlight vẫn thấy mãn nhãn!',
        'Trận đấu kịch tính đến những phút bù giờ cuối cùng.',
        'Phong độ thi đấu tuyệt vời, bàn thắng đẹp như tranh vẽ.',
        'Chiến thuật của ban huấn luyện trận này quá chuẩn xác và hiệu quả.',
        'Tinh thần thi đấu quả cảm, xứng đáng nhận được tràng pháo tay!',
      ],
      football: [
        'Bàn thắng quá đẹp mắt, thủ môn hoàn toàn không có cơ hội cản phá!',
        'Trận derby rực lửa đúng nghĩa, các cầu thủ đá hết mình vì màu cờ sắc áo.',
        'Highlight cắt cúp rất mượt, bình luận viên phân tích nhiệt huyết ghê.',
        'Phòng ngự chắc chắn, phản công sắc bén, chiến thắng xứng đáng!',
      ],
      game: [
        'Pha combat đỉnh cao lật kèo phút chót quá mãn nhãn anh ơi!',
        'Hướng dẫn lên đồ và combo chi tiết quá, áp dụng leo rank hiệu quả liền.',
        'Xem vừa giải trí vừa học hỏi được khối mẹo chơi game hay.',
        'Kỹ năng cá nhân quá ghê, phản xạ nhanh như chớp.',
        'Tựa game này đồ họa đẹp và cốt truyện sâu sắc thật sự.',
      ],
      'hai-huoc': [
        'Xem video cười đau cả bụng, giải tỏa stress sau ngày làm việc mệt mỏi.',
        'Nội dung duyên dáng, gần gũi và hài hước một cách tự nhiên.',
        'Cách diễn xuất và lồng ghép âm thanh ăn ý ghê.',
        'Xem đi xem lại đoạn giữa vẫn không nhịn được cười haha.',
      ],
      daily: [
        'Một ngày bình yên và nhiều điều thú vị, xem thấy lòng nhẹ nhàng hơn.',
        'Không khí ấm cúng và cách chia sẻ câu chuyện rất chân thật.',
        'Góc quay đẹp, tông màu ấm áp và âm nhạc nền rất hợp.',
        'Cảm ơn bạn đã lan tỏa năng lượng tích cực đến mọi người.',
      ],
      default: [
        'Nội dung video rất chất lượng và bổ ích, cảm ơn kênh nhiều ạ!',
        'Đã like và theo dõi kênh, mong chờ các video tiếp theo của bạn.',
        'Video đầu tư công phu, hình ảnh và âm thanh đều rất chỉn chu.',
        'Một sản phẩm nội dung rất đáng xem, chúc kênh ngày càng phát triển!',
        'Cảm ơn tác giả đã chia sẻ những góc nhìn thú vị này.',
      ],
    };
  }

  private loadCommentBank(): void {
    const defaults = this.defaultCommentBank();
    try {
      const raw = localStorage.getItem(this.commentBankStorageKey);
      if (!raw) { this.commentBanks.set(defaults); return; }
      const stored: unknown = JSON.parse(raw);
      if (!stored || typeof stored !== 'object') { this.commentBanks.set(defaults); return; }
      const merged = { ...defaults } as Record<string, string[]>;
      for (const [category, value] of Object.entries(stored as Record<string, unknown>)) {
        if (Array.isArray(value)) merged[category] = value.filter((item): item is string => typeof item === 'string').slice(0, 100);
      }
      this.commentBanks.set(merged);
    } catch { this.commentBanks.set(defaults); }
  }

  private persistCommentBank(bank: Record<string, string[]>): void {
    try { localStorage.setItem(this.commentBankStorageKey, JSON.stringify(bank)); }
    catch { this.notice.set(this.i18n.t('recommendations.commentSaveFailed')); }
  }
}
