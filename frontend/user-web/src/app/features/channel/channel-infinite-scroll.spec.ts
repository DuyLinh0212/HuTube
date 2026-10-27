import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, Router, convertToParamMap } from '@angular/router';
import { EMPTY, Subject, of, throwError } from 'rxjs';
import { FeedbackService } from '@dalitu/ui/feedback.service';
import { AuthService } from '../../core/auth.service';
import { ChannelDetail, ChannelService } from '../../core/channel.service';
import { ContentService, PageResult, VideoCard } from '../../core/content.service';
import { LoginPromptService } from '../../core/login-prompt.service';
import { NetworkStatusService } from '../../core/network/network-status.service';
import { PlaylistService } from '../../core/playlist.service';
import { ChannelPage } from './channel-page';

describe('Channel video infinite scroll', () => {
  let content: jasmine.SpyObj<ContentService>;
  let page: ChannelPage;
  const card = (videoId: string) => ({ videoId, title: videoId } as VideoCard);
  const batch = (number: number, total = 45): PageResult<VideoCard> => ({
    items: Array.from({ length: number === 3 ? 5 : 20 }, (_, i) => card(`${number}-${i}`)), page: number, pageSize: 20, total,
  });

  beforeEach(() => {
    content = jasmine.createSpyObj('content', ['search']);
    TestBed.configureTestingModule({ providers: [
      { provide: ContentService, useValue: content }, { provide: ChannelService, useValue: {} },
      { provide: PlaylistService, useValue: {} }, { provide: FeedbackService, useValue: {} },
      { provide: AuthService, useValue: { user: signal(null), restore: () => EMPTY } },
      { provide: NetworkStatusService, useValue: { unavailable: signal(false) } },
      { provide: LoginPromptService, useValue: {} },
      { provide: ActivatedRoute, useValue: { paramMap: EMPTY, queryParamMap: EMPTY, snapshot: { queryParamMap: convertToParamMap({}) } } },
      { provide: Router, useValue: {} },
    ] });
    TestBed.overrideComponent(ChannelPage, { set: { template: '', imports: [] } });
    page = TestBed.createComponent(ChannelPage).componentInstance;
    page.channel.set({ channelId: 'channel' } as ChannelDetail);
  });

  it('appends each page until the total is exhausted', () => {
    content.search.and.callFake(options => of(batch(options.page!)));
    page.loadVideos(); page.loadMoreTabVideos(); page.loadMoreTabVideos(); page.loadMoreTabVideos();
    expect(page.videoResults().length).toBe(45);
    expect(content.search.calls.allArgs().map(([options]) => options.page)).toEqual([1, 2, 3]);
    expect(page.hasMoreTabVideos()).toBeFalse();
  });

  it('preserves prior videos and retries the failed page', () => {
    content.search.and.returnValues(of(batch(1)), throwError(() => new Error('offline')), of(batch(2)), of(batch(3)));
    page.loadVideos(); page.loadMoreTabVideos();
    expect(page.videoResults().length).toBe(20); expect(page.videoResultsError()).toBeTrue();
    page.loadMoreTabVideos(); page.loadMoreTabVideos();
    expect(page.videoResults().length).toBe(45); expect(page.videoResultsError()).toBeFalse();
    expect(content.search.calls.allArgs().map(([options]) => options.page)).toEqual([1, 2, 2, 3]);
  });

  it('cancels a pending page and restarts when the sort changes', () => {
    const pending = new Subject<PageResult<VideoCard>>();
    content.search.and.returnValues(of(batch(1)), pending, of({ ...batch(1), items: [card('oldest')], total: 1 }));
    page.loadVideos(); page.loadMoreTabVideos();
    page.videoSort.set('oldest'); page.loadVideos();
    expect(pending.observed).toBeFalse(); pending.next(batch(2));
    expect(page.videoResults().map(item => item.videoId)).toEqual(['oldest']);
    expect(content.search.calls.mostRecent().args[0]).toEqual({ channelId: 'channel', sort: 'oldest', page: 1, pageSize: 20 });
  });

  it('deduplicates overlapping results without stopping before later pages', () => {
    const first = batch(1), second = batch(2);
    second.items[0] = first.items[0];
    content.search.and.returnValues(of(first), of(second), of(batch(3)));
    page.loadVideos(); page.loadMoreTabVideos(); page.loadMoreTabVideos();
    expect(page.videoResults().length).toBe(44);
    expect(page.hasMoreTabVideos()).toBeFalse();
  });
});
