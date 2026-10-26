import { TestBed } from '@angular/core/testing';
import { signal } from '@angular/core';
import { ActivatedRoute, Router, convertToParamMap } from '@angular/router';
import { BehaviorSubject, Subject, of, throwError } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { ChannelService } from '../../core/channel.service';
import { Category, ContentService, ExploreHub, PageResult, VideoCard } from '../../core/content.service';
import { ExplorePage } from './explore-page';

describe('Explore search filters', () => {
  const card = { videoId: 'video-one', channelId: 'channel-one', channelName: 'Kênh một', channelHandle: 'kenh-mot', title: 'Video', thumbnailUrl: null, duration: 100, visibility: 'public', publishedAt: null, views: 1 };
  const page = { items: [card], total: 1, page: 1, pageSize: 20 };
  let params: BehaviorSubject<ReturnType<typeof convertToParamMap>>;
  let content: jasmine.SpyObj<ContentService>;
  let navigate: jasmine.Spy;
  let snapshot: { routeConfig: { path: string } };

  beforeEach(() => {
    params = new BehaviorSubject(convertToParamMap({ q: 'nhạc', page: '3' }));
    snapshot = { routeConfig: { path: 'search' } };
    navigate = jasmine.createSpy('navigate').and.returnValue(Promise.resolve(true));
    content = jasmine.createSpyObj('content', ['search', 'searchChannels', 'exploreHub', 'categories']);
    content.search.and.returnValue(of(page));
    content.searchChannels.and.returnValue(of({ items: [{ channelId: 'channel-one', name: 'Kênh một', handle: 'kenh-mot', description: null, avatarUrl: null, subscriberCount: 5, videoCount: 2 }], total: 1, page: 1, pageSize: 20 }));
    content.categories.and.returnValue(of([]));
    content.exploreHub.and.returnValue(of({ rankings: [], creators: [], trending: [], topVideos: [card] }));
    TestBed.configureTestingModule({ imports: [ExplorePage], providers: [
      { provide: ContentService, useValue: content },
      { provide: ChannelService, useValue: {} },
      { provide: AuthService, useValue: { user: signal(null), restore: () => of(false) } },
      { provide: ActivatedRoute, useValue: { queryParamMap: params, snapshot } },
      { provide: Router, useValue: { navigate, events: new Subject() } },
    ] });
    TestBed.overrideComponent(ExplorePage, { set: { template: '', imports: [] } });
  });

  function render() {
    const fixture = TestBed.createComponent(ExplorePage);
    fixture.detectChanges();
    return fixture;
  }

  it('renders hub videos while optional categories are still pending and updates tabs when they arrive', () => {
    const categories = new Subject<Category[]>(), hub = new Subject<ExploreHub>();
    content.categories.and.returnValue(categories); content.exploreHub.and.returnValue(hub);
    const fixture = TestBed.createComponent(ExplorePage), component = fixture.componentInstance;
    component.loadHub(); expect(categories.observed && hub.observed).toBeTrue();
    hub.next({ rankings: [], creators: [], trending: [], topVideos: [card] }); hub.complete();
    expect(component.overallRankingVideos()).toEqual([card]); expect(component.hubLoading()).toBeFalse();
    categories.next([{ categoryId: 'music', name: 'Music', slug: 'music', description: null }]); categories.complete();
    expect(component.categoryTabs().some(tab => tab.id === 'music')).toBeTrue();
    expect(content.exploreHub.calls.count()).toBe(1); expect(content.search).not.toHaveBeenCalled();
    fixture.destroy();
  });

  it('keeps category ranking tabs and successful hub data if optional categories fail', () => {
    const categories = new Subject<Category[]>(); content.categories.and.returnValue(categories);
    content.exploreHub.and.returnValue(of({ rankings: [{ categoryId: 'music', categoryName: 'Music', slug: 'music', videos: [card] }],
      creators: [], trending: [], topVideos: [card] }));
    const fixture = TestBed.createComponent(ExplorePage), component = fixture.componentInstance;
    component.loadHub(); categories.error(new Error('Unavailable'));
    expect(component.overallRankingVideos()).toEqual([card]); expect(component.hubError()).toBe('');
    expect(component.categoryTabs().some(tab => tab.id === 'music')).toBeTrue(); fixture.destroy();
  });

  it('cancels both previous hub requests when retrying', () => {
    const categories = new Subject<Category[]>(), hub = new Subject<ExploreHub>();
    content.categories.and.returnValue(categories); content.exploreHub.and.returnValue(hub);
    const fixture = TestBed.createComponent(ExplorePage), component = fixture.componentInstance;
    component.loadHub();
    content.categories.and.returnValue(of([])); content.exploreHub.and.returnValue(of({ rankings: [], creators: [], trending: [], topVideos: [card] }));
    component.loadHub(); expect(categories.observed || hub.observed).toBeFalse();
    expect(component.overallRankingVideos()).toEqual([card]); fixture.destroy();
  });

  it('restores channel result mode from the URL and searches channels instead of videos', () => {
    params.next(convertToParamMap({ q: 'nhạc', type: 'channels', page: '3', duration: 'short' }));
    const fixture = render();
    expect(content.search).not.toHaveBeenCalled();
    expect(content.searchChannels).toHaveBeenCalledWith({ q: 'nhạc', page: 3, pageSize: 20 });
    expect(fixture.componentInstance.searchChannels().length).toBe(1);
    expect(fixture.componentInstance.videos()).toEqual([]);
    expect(fixture.componentInstance.selectedDuration()).toBe('');
    fixture.componentInstance.changeResultType('videos');
    expect(navigate).toHaveBeenCalledWith([], jasmine.objectContaining({ queryParams: jasmine.objectContaining({ q: 'nhạc', type: null, page: null }) }));
    fixture.destroy();
  });

  it('clears filters while retaining the search keyword', () => {
    const fixture = render();
    fixture.componentInstance.clearAllFilters();
    expect(fixture.componentInstance.searchQuery()).toBe('nhạc');
    expect(navigate).toHaveBeenCalledWith([], jasmine.objectContaining({ queryParams: { q: 'nhạc', sort: null, categoryId: null, duration: null, dateRange: null, type: null, page: null } }));
    fixture.destroy();
  });

  it('cancels obsolete requests so a slower earlier search cannot replace the new results', () => {
    const old = new Subject<PageResult<VideoCard>>();
    const latest = new Subject<PageResult<VideoCard>>();
    content.search.and.returnValues(old, latest);
    const fixture = render();
    params.next(convertToParamMap({ q: 'mới' }));
    expect(old.observed).toBeFalse();
    latest.next({ ...page, items: [{ ...card, title: 'Mới' }] }); latest.complete();
    old.next({ ...page, items: [{ ...card, title: 'Cũ' }] }); old.complete();
    expect(fixture.componentInstance.videos()[0].title).toBe('Mới');
    fixture.destroy();
  });

  it('shows a channel error without mixing video results into channel mode', () => {
    params.next(convertToParamMap({ q: 'nhạc', type: 'channels' }));
    content.searchChannels.and.returnValue(throwError(() => new Error('offline')));
    const fixture = render();
    expect(content.search).not.toHaveBeenCalled();
    expect(fixture.componentInstance.videos()).toEqual([]);
    expect(fixture.componentInstance.searchChannels()).toEqual([]);
    expect(fixture.componentInstance.error()).not.toBe('');
    fixture.destroy();
  });

  it('treats a sort-only link as results rather than the featured rankings', () => {
    snapshot.routeConfig.path = 'explore';
    params.next(convertToParamMap({ sort: 'views' }));
    const fixture = render();
    expect(fixture.componentInstance.isSearchMode).toBeTrue();
    expect(content.search).toHaveBeenCalledWith(jasmine.objectContaining({ sort: 'views' }));
    fixture.destroy();
  });

  it('drags the category rail without accidentally selecting a category', () => {
    const fixture = render();
    const component = fixture.componentInstance;
    const track = document.createElement('div');
    track.style.cssText = 'width: 100px; overflow-x: auto';
    const content = document.createElement('div');
    content.style.cssText = 'width: 1000px; height: 1px';
    track.appendChild(content);
    fixture.nativeElement.appendChild(track);
    document.body.appendChild(fixture.nativeElement);
    spyOn(track, 'setPointerCapture');
    spyOn(track, 'hasPointerCapture').and.returnValue(true);
    spyOn(track, 'releasePointerCapture');
    const pointer = (x: number) => ({
      pointerType: 'mouse', button: 0, pointerId: 1, clientX: x,
      currentTarget: track, preventDefault: jasmine.createSpy('preventDefault'),
    }) as unknown as PointerEvent;
    component.startCategoryDrag(pointer(300));
    component.moveCategoryDrag(pointer(100));
    expect(track.scrollLeft).toBe(200);
    expect(component.categoryDragging()).toBeTrue();
    component.endCategoryDrag(pointer(100));
    component.selectCategoryTab('category-one', new MouseEvent('click', { detail: 1 }));
    expect(component.activeCategoryTab()).toBe(component.overallTabId);
    expect(component.categoryDragging()).toBeFalse();

    component.startCategoryDrag(pointer(100));
    component.endCategoryDrag(pointer(100));
    component.selectCategoryTab('category-one', new MouseEvent('click', { detail: 1 }));
    expect(component.activeCategoryTab()).toBe('category-one');
    fixture.destroy();
  });
});
