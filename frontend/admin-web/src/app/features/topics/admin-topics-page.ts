import { ResultNoticeComponent } from '@dalitu/ui/result-notice.component';
import { FeedbackService } from '@dalitu/ui/feedback.service';
import { CommonModule } from '@angular/common';
import { Component, DestroyRef, OnInit, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';
import { Subject, firstValueFrom, takeUntil } from 'rxjs';
import { AuthService, errorMessage } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';
import {
  AdminTag,
  AdminTopic,
  AdminTopicsService,
  TopicRequest,
  TopicStatus,
} from './admin-topics.service';

type TaxonomyTab = 'topics' | 'tags';

const emptyTopicDraft = (): TopicRequest => ({
  name: '',
  slug: null,
  description: null,
  status: 'active',
});

@Component({
  selector: 'app-admin-topics-page',
  standalone: true,
  imports: [ResultNoticeComponent, CommonModule, FormsModule, TranslatePipe],
  templateUrl: './admin-topics-page.html',
  styleUrl: './admin-topics-page.scss',
})
export class AdminTopicsPage implements OnInit {
  private readonly feedback = inject(FeedbackService);
  private readonly service = inject(AdminTopicsService);
  private readonly destroyRef = inject(DestroyRef);
  private loadVersion = 0;
  private readonly loadCancelled$ = new Subject<void>();
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);

  readonly topics = signal<AdminTopic[]>([]);
  readonly tags = signal<AdminTag[]>([]);
  readonly topicsLoading = signal(true);
  readonly tagsLoading = signal(true);
  readonly loading = computed(() => this.topicsLoading() || this.tagsLoading());
  readonly saving = signal(false);
  readonly error = signal('');
  readonly success = signal('');
  readonly activeTab = signal<TaxonomyTab>('topics');
  readonly topicSearch = signal('');
  readonly tagSearch = signal('');
  readonly topicStatus = signal<'all' | TopicStatus>('all');

  readonly editingTopic = signal<AdminTopic | null>(null);
  readonly topicEditorOpen = signal(false);
  readonly tagEditorOpen = signal(false);
  readonly editingTag = signal<AdminTag | null>(null);

  topicDraft: TopicRequest = emptyTopicDraft();
  tagDraft = '';

  readonly canEdit = computed(() => this.auth.hasPermission('taxonomy.manage'));
  readonly filteredTopics = computed(() => {
    const query = this.topicSearch().trim().toLowerCase();
    const status = this.topicStatus();
    return this.topics().filter(topic => {
      const matchesStatus = status === 'all' || topic.status === status;
      const matchesQuery = !query || [topic.name, topic.slug, topic.description ?? '']
        .some(value => value.toLowerCase().includes(query));
      return matchesStatus && matchesQuery;
    });
  });
  readonly filteredTags = computed(() => {
    const query = this.tagSearch().trim().toLowerCase();
    return this.tags().filter(tag => !query || tag.name.toLowerCase().includes(query));
  });
  readonly activeTopicCount = computed(() => this.topics().filter(topic => topic.status === 'active').length);
  readonly categorizedVideoCount = computed(() => this.topics().reduce((total, topic) => total + topic.videoCount, 0));
  readonly usedTagCount = computed(() => this.tags().filter(tag => tag.videoCount > 0).length);

  constructor() {
    this.destroyRef.onDestroy(() => { ++this.loadVersion; this.loadCancelled$.complete(); });
  }

  ngOnInit(): void { void this.load(); }

  async load(): Promise<void> {
    const version = ++this.loadVersion;
    this.loadCancelled$.next();
    this.topicsLoading.set(true);
    this.tagsLoading.set(true);
    this.error.set('');
    const failed = (error: unknown): never => {
      if (version === this.loadVersion) this.error.set(errorMessage(error, this.i18n));
      throw error;
    };
    // Independent panels paint as each request finishes. A failure must not
    // cancel the other panel, unlike an all-or-nothing forkJoin/Promise.all.
    await Promise.allSettled([
      firstValueFrom(this.service.getTopics('all').pipe(takeUntil(this.loadCancelled$), takeUntilDestroyed(this.destroyRef)))
        .then(topics => { if (version === this.loadVersion) this.topics.set(topics); })
        .catch(failed)
        .finally(() => { if (version === this.loadVersion) this.topicsLoading.set(false); }),
      firstValueFrom(this.service.getTags().pipe(takeUntil(this.loadCancelled$), takeUntilDestroyed(this.destroyRef)))
        .then(tags => { if (version === this.loadVersion) this.tags.set(tags); })
        .catch(failed)
        .finally(() => { if (version === this.loadVersion) this.tagsLoading.set(false); }),
    ]);
  }

  openCreateTopic(): void {
    this.editingTopic.set(null);
    this.topicDraft = emptyTopicDraft();
    this.error.set('');
    this.topicEditorOpen.set(true);
  }

  openEditTopic(topic: AdminTopic): void {
    this.editingTopic.set(topic);
    this.topicDraft = {
      name: topic.name,
      slug: topic.slug,
      description: topic.description,
      status: topic.status,
    };
    this.error.set('');
    this.topicEditorOpen.set(true);
  }

  closeTopicEditor(): void {
    if (!this.saving()) this.topicEditorOpen.set(false);
  }

  saveTopic(): void {
    if (this.saving()) return;
    const request: TopicRequest = {
      name: this.topicDraft.name.trim(),
      slug: this.topicDraft.slug?.trim() || null,
      description: this.topicDraft.description?.trim() || null,
      status: this.topicDraft.status,
    };
    if (!request.name) {
      this.error.set(this.i18n.t('topics.nameRequired'));
      return;
    }

    this.saving.set(true);
    this.error.set('');
    const topic = this.editingTopic();
    const request$ = topic
      ? this.service.updateTopic(topic.categoryId, request)
      : this.service.createTopic(request);
    request$.subscribe({
      next: () => {
        this.saving.set(false);
        this.topicEditorOpen.set(false);
        this.showSuccess(this.i18n.t(topic ? 'topics.updatedCategory' : 'topics.createdCategory'));
        this.load();
      },
      error: err => {
        this.saving.set(false);
        this.error.set(errorMessage(err, this.i18n));
      },
    });
  }

  async archiveTopic(topic: AdminTopic): Promise<void> {
    if (!this.canEdit() || topic.status === 'inactive') return;
    if (!(await this.feedback.confirm(this.i18n.format('topics.archiveConfirm', { name: topic.name }), { tone: 'danger' }))) return;
    this.service.archiveTopic(topic.categoryId).subscribe({
      next: () => {
        this.showSuccess(this.i18n.t('topics.archivedCategory'));
        this.load();
      },
      error: err => this.error.set(errorMessage(err, this.i18n)),
    });
  }

  openCreateTag(): void {
    this.editingTag.set(null);
    this.tagDraft = '';
    this.error.set('');
    this.tagEditorOpen.set(true);
  }

  openEditTag(tag: AdminTag): void {
    this.editingTag.set(tag);
    this.tagDraft = tag.name;
    this.error.set('');
    this.tagEditorOpen.set(true);
  }

  closeTagEditor(): void {
    if (!this.saving()) this.tagEditorOpen.set(false);
  }

  saveTag(): void {
    if (this.saving()) return;
    const name = this.tagDraft.trim();
    if (!name) {
      this.error.set(this.i18n.t('topics.tagNameRequired'));
      return;
    }

    this.saving.set(true);
    this.error.set('');
    const tag = this.editingTag();
    const request$ = tag
      ? this.service.updateTag(tag.tagId, name)
      : this.service.createTag(name);
    request$.subscribe({
      next: () => {
        this.saving.set(false);
        this.tagEditorOpen.set(false);
        this.showSuccess(this.i18n.t(tag ? 'topics.updatedTag' : 'topics.createdTag'));
        this.load();
      },
      error: err => {
        this.saving.set(false);
        this.error.set(errorMessage(err, this.i18n));
      },
    });
  }

  async deleteTag(tag: AdminTag): Promise<void> {
    if (!this.canEdit() || tag.videoCount > 0) return;
    if (!(await this.feedback.confirm(this.i18n.format('topics.deleteConfirm', { name: tag.name }), { tone: 'danger' }))) return;
    this.service.deleteTag(tag.tagId).subscribe({
      next: () => {
        this.showSuccess(this.i18n.t('topics.deletedTag'));
        this.load();
      },
      error: err => this.error.set(errorMessage(err, this.i18n)),
    });
  }

  private showSuccess(message: string): void {
    this.success.set(message);
    window.setTimeout(() => this.success.set(''), 3500);
  }

  dateLocale(): string {
    return this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US';
  }
}
