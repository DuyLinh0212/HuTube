import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, Router, convertToParamMap } from '@angular/router';
import { EMPTY, NEVER, Subject, of, throwError } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { ChannelService } from '../../core/channel.service';
import { ContentService, PageResult, VideoCard, VideoDetail } from '../../core/content.service';
import { LoginPromptService } from '../../core/login-prompt.service';
import { PictureInPictureService } from '../../core/picture-in-picture.service';
import { PlanService } from '../../core/plan.service';
import { PlayerPreferencesService } from '../../core/player-preferences.service';
import { PlaylistService } from '../../core/playlist.service';
import { VideoDownloadService } from '../../core/video-download.service';
import { FeedbackService } from '@dalitu/ui/feedback.service';
import { WatchPage } from './watch-page';

describe('Watch recommendations', () => {
  let page: WatchPage;
  let content: jasmine.SpyObj<ContentService>;
  let channels: jasmine.SpyObj<ChannelService>;
  let feedback: jasmine.SpyObj<FeedbackService>;
  beforeEach(() => {
    content = jasmine.createSpyObj('ContentService', ['feed', 'search']);
    channels = jasmine.createSpyObj('ChannelService', ['subscribe', 'unsubscribe']);
    channels.unsubscribe.and.returnValue(of(undefined));
    feedback = jasmine.createSpyObj('FeedbackService', ['confirm']);
    feedback.confirm.and.resolveTo(true);
    TestBed.configureTestingModule({ providers: [
      { provide: ContentService, useValue: content },
      { provide: AuthService, useValue: { user: signal({ userId: 'viewer' }), restore: () => NEVER } },
      { provide: ActivatedRoute, useValue: { snapshot: { paramMap: convertToParamMap({ id: 'video' }) }, paramMap: EMPTY, queryParamMap: EMPTY } },
      { provide: Router, useValue: { url: '/watch/video' } },
      { provide: LoginPromptService, useValue: { require: () => true } },
      { provide: PlayerPreferencesService, useValue: { preferences: () => ({ muted: false, volume: 1 }) } },
      { provide: PictureInPictureService, useValue: { active: signal(false), entering: signal(false) } },
      { provide: ChannelService, useValue: channels }, { provide: PlaylistService, useValue: {} },
      { provide: PlanService, useValue: {} }, { provide: VideoDownloadService, useValue: {} },
      { provide: FeedbackService, useValue: feedback },
    ] });
    TestBed.overrideComponent(WatchPage, { set: { template: '', imports: [] } });
    page = TestBed.createComponent(WatchPage).componentInstance;
    page.video.set({ videoId: 'video', channelId: 'creator', categoryId: 'music', tags: ['-xh', 'music'] } as VideoDetail);
    content.feed.and.returnValue(of(result([card('feed')])));
    content.search.and.returnValue(of(result([card('video')])));
  });

  const card = (videoId: string): VideoCard => ({ videoId, channelId: 'creator', channelName: 'Creator', channelHandle: 'creator', title: videoId, thumbnailUrl: null, duration: 30, visibility: 'public', publishedAt: null, views: 0 });
  const result = (items: VideoCard[]): PageResult<VideoCard> => ({ items, total: items.length, page: 1, pageSize: 20 });

  it('keeps the subscription and count when unsubscribe confirmation is cancelled', async () => {
    page.channel.set({ channelId: 'creator' } as any);
    page.subscribed.set(true); page.subscriberCount.set(5);
    feedback.confirm.and.resolveTo(false);
    await page.toggleSubscribe();
    expect(feedback.confirm).toHaveBeenCalled();
    expect(channels.unsubscribe).not.toHaveBeenCalled();
    expect(page.subscribed()).toBeTrue(); expect(page.subscriberCount()).toBe(5);
    expect(page.subscriptionBusy()).toBeFalse();
  });

  it('waits for confirmation and prevents duplicate unsubscribe requests', async () => {
    page.channel.set({ channelId: 'creator' } as any);
    page.subscribed.set(true); page.subscriberCount.set(5);
    let resolve!: (confirmed: boolean) => void;
    feedback.confirm.and.returnValue(new Promise<boolean>(done => resolve = done));
    const pending = page.toggleSubscribe();
    await page.toggleSubscribe();
    expect(feedback.confirm).toHaveBeenCalledTimes(1);
    expect(channels.unsubscribe).not.toHaveBeenCalled();
    resolve(true); await pending;
    expect(channels.unsubscribe).toHaveBeenCalledOnceWith('creator');
    expect(page.subscribed()).toBeFalse(); expect(page.subscriberCount()).toBe(4);
  });

  it('does not unsubscribe an old channel if the page changes during confirmation', async () => {
    page.channel.set({ channelId: 'creator' } as any); page.subscribed.set(true);
    let resolve!: (confirmed: boolean) => void;
    feedback.confirm.and.returnValue(new Promise<boolean>(done => resolve = done));
    const pending = page.toggleSubscribe();
    page.channel.set({ channelId: 'another-channel' } as any);
    resolve(true); await pending;
    expect(channels.unsubscribe).not.toHaveBeenCalled();
    expect(page.subscriptionBusy()).toBeFalse();
  });

  it('fills a rare-tag result containing only the current video from its category', () => {
    content.search.and.returnValues(of(result([card('video')])), of(result([card('video'), card('related')])));
    page.setRecommendationFilter('related');
    expect(content.search.calls.allArgs()).toEqual([
      [{ categoryId: 'music', tag: '-xh', sort: 'popular', page: 1, pageSize: 20 }],
      [{ categoryId: 'music', tag: undefined, sort: 'popular', page: 1, pageSize: 20 }]
    ]);
    expect(page.relatedVideos().map(x => x.videoId)).toEqual(['related']);
    expect(page.recommendationsError()).toBeFalse();
    expect(page.recommendationsLoading()).toBeFalse();
    expect(content.feed).not.toHaveBeenCalled();
  });

  it('keeps tag matches first, deduplicates and caps the combined result at ten', () => {
    content.search.and.returnValues(of(result([card('tagged'), card('tagged')])),
      of(result([card('video'), card('tagged'), ...Array.from({ length: 12 }, (_, n) => card(`category-${n}`))])));
    page.setRecommendationFilter('related');
    expect(page.relatedVideos().map(x => x.videoId)).toEqual(['tagged', ...Array.from({ length: 9 }, (_, n) => `category-${n}`)]);
  });

  it('does not broaden a full tag result', () => {
    content.search.and.returnValue(of(result(Array.from({ length: 10 }, (_, n) => card(`tagged-${n}`)))));
    page.setRecommendationFilter('related');
    expect(content.search.calls.count()).toBe(1);
  });

  it('searches only once when there is no tag and stays within the category', () => {
    page.video.update(v => ({ ...v!, tags: [] }));
    page.setRecommendationFilter('related');
    expect(content.search.calls.count()).toBe(1);
    expect(content.search.calls.mostRecent().args[0].categoryId).toBe('music');
    expect(content.feed).not.toHaveBeenCalled();
  });

  it('uses the normal feed when the video has no category or tags', () => {
    page.video.update(v => ({ ...v!, categoryId: null, tags: [] }));
    page.setRecommendationFilter('related');
    expect(content.feed).toHaveBeenCalledOnceWith('home', 1, 20);
    expect(content.search).not.toHaveBeenCalled();
    expect(page.relatedVideos()[0].videoId).toBe('feed');
  });

  it('keeps an empty channel result empty without unrelated feed fallback', () => {
    page.setRecommendationFilter('channel');
    expect(content.search).toHaveBeenCalledOnceWith({ channelId: 'creator', sort: 'newest', page: 1, pageSize: 20 });
    expect(page.relatedVideos()).toEqual([]);
    expect(page.recommendationsError()).toBeFalse();
    expect(content.feed).not.toHaveBeenCalled();
  });

  it('cancels stale requests when switching tabs, including a pending category fill', () => {
    const category = new Subject<PageResult<VideoCard>>();
    content.search.and.returnValues(of(result([card('video')])), category, of(result([card('channel')])));
    page.setRecommendationFilter('related');
    expect(page.recommendationsLoading()).toBeTrue();
    page.setRecommendationFilter('channel');
    expect(category.observed).toBeFalse();
    category.next(result([card('stale')]));
    expect(page.relatedVideos().map(x => x.videoId)).toEqual(['channel']);
    expect(page.recommendationsLoading()).toBeFalse();
  });

  it('clears the previous tab while loading and offers retry on network failure', () => {
    page.setRecommendationFilter('all');
    const pending = new Subject<PageResult<VideoCard>>();
    content.search.and.returnValue(pending);
    page.setRecommendationFilter('channel');
    expect(page.relatedVideos()).toEqual([]);
    expect(page.recommendationsLoading()).toBeTrue();
    pending.error(new Error('offline'));
    expect(page.recommendationsLoading()).toBeFalse();
    expect(page.recommendationsError()).toBeTrue();
    content.search.and.returnValue(of(result([card('recovered')])));
    page.setRecommendationFilter('channel');
    expect(page.recommendationsError()).toBeFalse();
    expect(page.relatedVideos()[0].videoId).toBe('recovered');
  });

  it('preserves valid tag matches if the category fill fails', () => {
    content.search.and.returnValues(of(result([card('tagged')])), throwError(() => new Error('unavailable')));
    page.setRecommendationFilter('related');
    expect(page.relatedVideos().map(x => x.videoId)).toEqual(['tagged']);
    expect(page.recommendationsError()).toBeFalse();
  });

  it('distinguishes a failed category fill from a genuinely empty result', () => {
    content.search.and.returnValues(of(result([card('video')])), throwError(() => new Error('unavailable')));
    page.setRecommendationFilter('related');
    expect(page.recommendationsError()).toBeTrue();
    content.search.and.returnValue(of(result([])));
    page.setRecommendationFilter('related');
    expect(page.recommendationsError()).toBeFalse();
    expect(page.relatedVideos()).toEqual([]);
  });
});
