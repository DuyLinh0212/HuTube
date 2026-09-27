import { CommonModule } from '@angular/common';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { forkJoin } from 'rxjs';
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
  imports: [CommonModule, FormsModule, TranslatePipe],
  templateUrl: './admin-topics-page.html',
  styleUrl: './admin-topics-page.scss',
})
export class AdminTopicsPage implements OnInit {
  private readonly service = inject(AdminTopicsService);
  readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);

  readonly topics = signal<AdminTopic[]>([]);
  readonly tags = signal<AdminTag[]>([]);
  readonly loading = signal(true);
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

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.loading.set(true);
    this.error.set('');
    forkJoin({
      topics: this.service.getTopics('all'),
      tags: this.service.getTags(),
    }).subscribe({
      next: result => {
        this.topics.set(result.topics);
        this.tags.set(result.tags);
        this.loading.set(false);
      },
      error: err => {
        this.error.set(errorMessage(err, this.i18n));
        this.loading.set(false);
      },
    });
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

  archiveTopic(topic: AdminTopic): void {
    if (!this.canEdit() || topic.status === 'inactive') return;
    if (!confirm(this.i18n.format('topics.archiveConfirm', { name: topic.name }))) return;
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

  deleteTag(tag: AdminTag): void {
    if (!this.canEdit() || tag.videoCount > 0) return;
    if (!confirm(this.i18n.format('topics.deleteConfirm', { name: tag.name }))) return;
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
