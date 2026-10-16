import { TestBed } from '@angular/core/testing';
import { signal } from '@angular/core';
import { ActivatedRoute, Router, convertToParamMap } from '@angular/router';
import { BehaviorSubject, Subject, of, throwError } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { ChannelService } from '../../core/channel.service';
import { ContentService, PageResult, VideoCard } from '../../core/content.service';
import { ExplorePage } from './explore-page';

describe('Explore search filters', () => {
  const card = { videoId: 'video-one', channelId: 'channel-one', channelName: 'Kênh một', channelHandle: 'kenh-mot', title: 'Video', thumbnailUrl: null, duration: 100, visibility: 'public', publishedAt: null, views: 1 };
  const page = { items: [card], total: 1, page: 1, pageSize: 20 };
  let params: BehaviorSubject<ReturnType<typeof convertToParamMap>>;
  let content: jasmine.SpyObj<ContentService>;
  let navigate: jasmine.Spy;
  let snapshot: { routeConfig: { path: string } };

  beforeEach(() => {
    params = new BehaviorSubject(convertToParamMap({ q: 'nhạc', page: '3', channelId: 'channel-one' }));
    snapshot = { routeConfig: { path: 'search' } };
    navigate = jasmine.createSpy('navigate').and.returnValue(Promise.resolve(true));
    content = jasmine.createSpyObj('content', ['search', 'searchChannels', 'exploreHub', 'categories']);
    content.search.and.returnValue(of(page));
    content.searchChannels.and.returnValue(of([{ channelId: 'channel-one', name: 'Kênh một', handle: 'kenh-mot', videoCount: 2 }, { channelId: 'channel-two', name: 'Kênh hai', handle: 'kenh-hai', videoCount: 1 }]));
    content.categories.and.returnValue(of([]));
    content.exploreHub.and.returnValue(of({ rankings: [], creators: [], trending: [], topVideos: [card] }));
    TestBed.configureTestingModule({ imports: [ExplorePage], providers: [
      { provide: ContentService, useValue: content },
      { provide: ChannelService, useValue: {} },
      { provide: AuthService, useValue: { user: signal(null), restore: () => of(false) } },
      { provide: ActivatedRoute, useValue: { queryParamMap: params, snapshot } },
      { provide: Router, useValue: { navigate } },
    ] });
    TestBed.overrideComponent(ExplorePage, { set: { template: '', imports: [] } });
  });

  function render() {
    const fixture = TestBed.createComponent(ExplorePage);
    fixture.detectChanges();
    return fixture;
  }

  it('restores channel selection from the URL and keeps options outside the current result page', () => {
    const fixture = render();
    expect(content.search).toHaveBeenCalledWith(jasmine.objectContaining({ q: 'nhạc', channelId: 'channel-one', page: 3 }));
    expect(content.searchChannels).toHaveBeenCalledWith({ q: 'nhạc', categoryId: undefined, duration: undefined, dateRange: undefined });
    expect(fixture.componentInstance.searchChannels().length).toBe(2);
    fixture.componentInstance.changeChannel('channel-two');
    expect(navigate).toHaveBeenCalledWith([], jasmine.objectContaining({ queryParams: jasmine.objectContaining({ q: 'nhạc', channelId: 'channel-two', page: null }) }));
    fixture.destroy();
  });

  it('clears filters while retaining the search keyword', () => {
    const fixture = render();
    fixture.componentInstance.clearAllFilters();
    expect(fixture.componentInstance.searchQuery()).toBe('nhạc');
    expect(navigate).toHaveBeenCalledWith([], jasmine.objectContaining({ queryParams: { q: 'nhạc', sort: null, categoryId: null, duration: null, dateRange: null, channelId: null, page: null } }));
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

  it('keeps video results available when the channel option endpoint fails', () => {
    content.searchChannels.and.returnValue(throwError(() => new Error('offline')));
    const fixture = render();
    expect(fixture.componentInstance.videos()).toEqual(page.items);
    expect(fixture.componentInstance.channelFilterError()).toBeTrue();
    expect(fixture.componentInstance.error()).toBe('');
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
});
