import { TestBed, fakeAsync, flushMicrotasks } from '@angular/core/testing';
import { Subject } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { FeedbackService } from '@dalitu/ui/feedback.service';
import { AdminTopicsPage } from './admin-topics-page';
import { AdminTag, AdminTopic, AdminTopicsService } from './admin-topics.service';

describe('Independent taxonomy requests', () => {
  let topics: Subject<AdminTopic[]>;
  let tags: Subject<AdminTag[]>;
  let service: jasmine.SpyObj<AdminTopicsService>;
  const topic = { categoryId: 'music', name: 'Music', status: 'active', videoCount: 2 } as AdminTopic;
  const tag = { tagId: 'chill', name: 'Chill' } as AdminTag;

  beforeEach(() => {
    topics = new Subject(); tags = new Subject();
    service = jasmine.createSpyObj('topics', ['getTopics', 'getTags']);
    service.getTopics.and.returnValue(topics); service.getTags.and.returnValue(tags);
    TestBed.configureTestingModule({ providers: [
      { provide: AdminTopicsService, useValue: service },
      { provide: AuthService, useValue: { hasPermission: () => true } },
      { provide: FeedbackService, useValue: {} },
    ] });
    TestBed.overrideComponent(AdminTopicsPage, { set: { template: '', imports: [] } });
  });

  it('starts both requests together and displays topics before slow tags finish', fakeAsync(() => {
    const fixture = TestBed.createComponent(AdminTopicsPage), page = fixture.componentInstance;
    void page.load();
    expect(topics.observed && tags.observed).toBeTrue();
    topics.next([topic]); flushMicrotasks();
    expect(page.topics()).toEqual([topic]); expect(page.topicsLoading()).toBeFalse();
    expect(page.tagsLoading()).toBeTrue();
    tags.error(new Error('Unavailable')); flushMicrotasks();
    expect(page.topics()).toEqual([topic]); expect(page.loading()).toBeFalse();
    expect(page.error()).not.toBe('');
    fixture.destroy();
  }));

  it('keeps loading tags after the independent topics request fails', fakeAsync(() => {
    const fixture = TestBed.createComponent(AdminTopicsPage), page = fixture.componentInstance;
    void page.load(); topics.error(new Error('Unavailable')); flushMicrotasks();
    expect(tags.observed).toBeTrue();
    tags.next([tag]); flushMicrotasks();
    expect(page.tags()).toEqual([tag]); expect(page.loading()).toBeFalse();
    fixture.destroy();
  }));

  it('ignores older responses and cancels pending requests when leaving the page', fakeAsync(() => {
    const fixture = TestBed.createComponent(AdminTopicsPage), page = fixture.componentInstance;
    void page.load();
    const currentTopics = new Subject<AdminTopic[]>(), currentTags = new Subject<AdminTag[]>();
    service.getTopics.and.returnValue(currentTopics); service.getTags.and.returnValue(currentTags);
    void page.load();
    expect(topics.observed || tags.observed).toBeFalse();
    currentTopics.next([topic]); currentTags.next([tag]); flushMicrotasks();
    topics.next([]); tags.error(new Error('Old request')); flushMicrotasks();
    expect(page.topics()).toEqual([topic]); expect(page.tags()).toEqual([tag]);
    expect(page.error()).toBe('');
    service.getTopics.and.returnValue(topics = new Subject());
    service.getTags.and.returnValue(tags = new Subject());
    void page.load(); fixture.destroy(); flushMicrotasks();
    expect(topics.observed || tags.observed).toBeFalse();
    expect(page.error()).toBe('');
  }));
});
