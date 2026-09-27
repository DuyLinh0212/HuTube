import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { Component, OnDestroy, OnInit, effect, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { errorMessage } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { RuntimeConfig } from '../../core/runtime-config';
import { TranslatePipe } from '../../core/translate.pipe';

interface Counts { pairs: number; users: number; videos: number; }
interface MatrixPreview { columns: string[]; rows: string[][]; total: number; }
interface MatrixDiff {
  state: 'ready' | 'uninitialized'; modelVersion: string | null; csvKey: string | null;
  csvSha256: string | null; updatedAt: string | null; active: Counts; current: Counts;
  added: number; changed: number; removed: number; changeRate: number;
}
interface Person { userId: string; username: string; displayName: string; isBot: boolean; }
interface Video { videoId: string; channelId: string; title: string; duration: number; }
interface Job { jobId: string; kind: string; status: string; step: string; completed: number;
  total: number; logsJson: string; error: string | null; }

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
  readonly users = signal<Person[]>([]);
  readonly videos = signal<Video[]>([]);
  readonly job = signal<Job | null>(null);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly notice = signal('');
  readonly selectedUsers = new Set<string>();
  private readonly selectedPeople = new Map<string, Person>();
  readonly selectedVideos = new Set<string>();

  userSearch = '';
  videoSearch = '';
  botPrefix = 'cfbot';
  botCount = 5;
  mode: 'target' | 'cluster' = 'target';
  actionsPerUser = 5;
  delayMs = 0;
  watchPercent = 75;
  viewRate = 100;
  likeRate = 35;
  dislikeRate = 5;
  ratingRate = 20;
  commentRate = 15;
  subscribeRate = 10;
  commentTemplates = '';
  private defaultCommentTemplates = '';
  confirmRealUsers = false;

  constructor() {
    effect(() => {
      this.i18n.currentLang();
      const translatedDefault = this.i18n.t('recommendations.defaultCommentTemplates');
      if (!this.commentTemplates || this.commentTemplates === this.defaultCommentTemplates) {
        this.commentTemplates = translatedDefault;
      }
      this.defaultCommentTemplates = translatedDefault;
    });
  }

  ngOnInit(): void { this.check(); this.loadUsers(); this.loadVideos(); }
  ngOnDestroy(): void { if (this.pollHandle) clearInterval(this.pollHandle); }

  check(): void {
    this.busy.set(true); this.error.set(''); this.preview.set(null);
    this.http.get<MatrixDiff>(`${this.base()}/status`).subscribe({
      next: value => { this.diff.set(value); this.busy.set(false); },
      error: err => { this.error.set(errorMessage(err, this.i18n)); this.busy.set(false); },
    });
  }

  loadUsers(): void {
    this.http.get<Person[]>(`${this.base()}/users`, { params: { search: this.userSearch } }).subscribe({
      next: value => this.users.set(value), error: err => this.error.set(errorMessage(err, this.i18n)),
    });
  }
  loadVideos(): void {
    this.http.get<Video[]>(`${this.base()}/videos`, { params: { search: this.videoSearch } }).subscribe({
      next: value => this.videos.set(value), error: err => this.error.set(errorMessage(err, this.i18n)),
    });
  }
  toggleUser(person: Person): void {
    if (this.selectedUsers.has(person.userId)) {
      this.selectedUsers.delete(person.userId); this.selectedPeople.delete(person.userId);
    } else {
      this.selectedUsers.add(person.userId); this.selectedPeople.set(person.userId, person);
    }
  }
  toggleVideo(id: string): void {
    this.selectedVideos.has(id) ? this.selectedVideos.delete(id) : this.selectedVideos.add(id);
  }
  hasRealUsers(): boolean {
    return [...this.selectedPeople.values()].some(x => !x.isBot);
  }
  lines(): string[] {
    try { return JSON.parse(this.job()?.logsJson ?? '[]') as string[]; }
    catch { return []; }
  }
  progress(): number {
    const value = this.job();
    return value?.total ? Math.min(100, Math.round(value.completed * 100 / value.total)) : 0;
  }

  jobStatus(status: string): string {
    const known = ['queued', 'running', 'cancelling', 'cancelled', 'completed', 'failed'];
    return known.includes(status)
      ? this.i18n.t(`recommendations.job.${status}`)
      : status;
  }

  jobStep(step: string): string {
    const known = ['matrix', 'upload_csv', 'train_model', 'verify_manifest', 'interactions'];
    return known.includes(step)
      ? this.i18n.t(`recommendations.step.${step}`)
      : step;
  }

  updateModel(): void {
    if (this.busy()) return;
    this.busy.set(true); this.error.set(''); this.notice.set('');
    this.http.post<{ jobId: string }>(`${this.base()}/model-jobs`, {}).subscribe({
      next: value => { this.busy.set(false); this.watch(value.jobId); },
      error: err => { this.error.set(errorMessage(err, this.i18n)); this.busy.set(false); },
    });
  }

  createBots(): void {
    if (this.busy()) return;
    this.busy.set(true); this.error.set('');
    this.http.post<Person[]>(`${this.base()}/bots`, { count: this.botCount, prefix: this.botPrefix }).subscribe({
      next: value => {
        this.busy.set(false);
        this.users.set([...value, ...this.users()]);
        value.forEach(x => { this.selectedUsers.add(x.userId); this.selectedPeople.set(x.userId, x); });
        this.notice.set(this.i18n.t('recommendations.botsCreated', { count: String(value.length) }));
      },
      error: err => { this.error.set(errorMessage(err, this.i18n)); this.busy.set(false); },
    });
  }

  simulate(): void {
    if (this.busy()) return;
    const userIds = [...this.selectedUsers];
    const videoIds = [...this.selectedVideos];
    if (!userIds.length || !videoIds.length) {
      this.error.set(this.i18n.t('recommendations.selectRequired')); return;
    }
    if (this.hasRealUsers() && !this.confirmRealUsers) {
      this.error.set(this.i18n.t('recommendations.confirmRequired')); return;
    }
    if (this.hasRealUsers() && !window.confirm(this.i18n.t('recommendations.confirmPrompt', { count: String(userIds.length) }))) return;
    this.busy.set(true); this.error.set(''); this.notice.set('');
    this.http.post<{ jobId: string }>(`${this.base()}/simulation-jobs`, {
      userIds, videoIds, mode: this.mode, actionsPerUser: this.actionsPerUser,
      delayMs: this.delayMs, watchPercent: this.watchPercent,
      viewRate: this.viewRate, likeRate: this.likeRate, dislikeRate: this.dislikeRate,
      ratingRate: this.ratingRate, commentRate: this.commentRate, subscribeRate: this.subscribeRate,
      commentTemplates: this.commentTemplates.split(/\r?\n/).map(x => x.trim()).filter(Boolean),
      confirmRealUsers: this.confirmRealUsers,
    }).subscribe({
      next: value => { this.busy.set(false); this.watch(value.jobId); },
      error: err => { this.error.set(errorMessage(err, this.i18n)); this.busy.set(false); },
    });
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
        link.href = url; link.download = 'interactions_current.csv'; link.click();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      },
      error: err => this.error.set(errorMessage(err, this.i18n)),
    });
  }

  viewMatrix(): void {
    if (this.preview()) { this.preview.set(null); return; }
    this.http.get<MatrixPreview>(`${this.base()}/matrix-preview`).subscribe({
      next: value => this.preview.set(value),
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
        if (['completed', 'failed', 'cancelled'].includes(value.status)) {
          if (this.pollHandle) clearInterval(this.pollHandle);
          this.pollHandle = undefined;
          if (value.status === 'completed') { this.notice.set(this.i18n.t('recommendations.jobCompleted')); this.check(); }
          if (value.error) this.error.set(value.error);
        }
      },
      error: err => this.error.set(errorMessage(err, this.i18n)),
    });
  }
}
