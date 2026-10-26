import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, Router, convertToParamMap } from '@angular/router';
import { EMPTY, Subject, of } from 'rxjs';
import { FeedbackService } from '@dalitu/ui/feedback.service';
import { AuthService } from '../../core/auth.service';
import { ChannelDetail, ChannelService } from '../../core/channel.service';
import { ContentService, PageResult, VideoCard, VideoDetail } from '../../core/content.service';
import { Playlist, PlaylistItem, PlaylistService, PlaylistSummary } from '../../core/playlist.service';
import { NetworkStatusService } from '../../core/network/network-status.service';
import { LoginPromptService } from '../../core/login-prompt.service';
import { ChannelPage } from './channel-page';

describe('Channel request dependencies', () => {
  let channels: jasmine.SpyObj<ChannelService>;
  let content: jasmine.SpyObj<ContentService>;
  let playlists: jasmine.SpyObj<PlaylistService>;
  let latest: Subject<PageResult<VideoCard>>;
  let popular: Subject<PageResult<VideoCard>>;
  const channel = { channelId: 'channel', settings: '{}', isOwner: false } as ChannelDetail;
  const card = (id: string) => ({ videoId: id, title: id } as VideoCard);
  const result = (id: string): PageResult<VideoCard> => ({ items: [card(id)], total: 1, page: 1, pageSize: 50 });

  beforeEach(() => {
    latest = new Subject(); popular = new Subject();
    channels = jasmine.createSpyObj('channels', ['getChannel']);
    content = jasmine.createSpyObj('content', ['search', 'detail']);
    playlists = jasmine.createSpyObj('playlists', ['publicByChannel', 'get']);
    channels.getChannel.and.returnValue(of(channel));
    content.search.and.callFake(options => options.sort === 'views' ? popular : latest);
    content.detail.and.returnValue(of({ description: 'Featured description' } as VideoDetail));
    playlists.publicByChannel.and.returnValue(of([]));
    TestBed.configureTestingModule({ providers: [
      { provide: ChannelService, useValue: channels }, { provide: ContentService, useValue: content },
      { provide: PlaylistService, useValue: playlists }, { provide: FeedbackService, useValue: {} },
      { provide: AuthService, useValue: { user: signal(null), restore: () => EMPTY } },
      { provide: NetworkStatusService, useValue: { unavailable: signal(false) } },
      { provide: LoginPromptService, useValue: {} },
      { provide: ActivatedRoute, useValue: { paramMap: EMPTY, queryParamMap: EMPTY,
        snapshot: { queryParamMap: convertToParamMap({}) } } },
      { provide: Router, useValue: {} },
    ] });
    TestBed.overrideComponent(ChannelPage, { set: { template: '', imports: [] } });
  });

  it('waits for the channel ID, then starts both shelves without waiting on one another', () => {
    const response = new Subject<ChannelDetail>(); channels.getChannel.and.returnValue(response);
    const fixture = TestBed.createComponent(ChannelPage), page = fixture.componentInstance;
    page.loadChannel('music'); expect(content.search).not.toHaveBeenCalled();
    response.next(channel); response.complete();
    expect(latest.observed && popular.observed).toBeTrue();
    latest.next(result('latest')); latest.complete();
    expect(page.latestVideos()[0].videoId).toBe('latest'); expect(page.videosLoading()).toBeFalse();
    expect(page.popularLoading()).toBeTrue();
    popular.error(new Error('Unavailable'));
    expect(page.latestVideos()[0].videoId).toBe('latest'); expect(page.popularError()).toBeTrue();
    fixture.destroy();
  });

  it('starts featured details as soon as popular videos arrive, even while latest videos are pending', () => {
    const fixture = TestBed.createComponent(ChannelPage), page = fixture.componentInstance;
    page.loadChannel('music'); popular.next(result('popular')); popular.complete();
    expect(content.detail).toHaveBeenCalledWith('popular');
    expect(page.featuredDescription()).toBe('Featured description'); expect(page.videosLoading()).toBeTrue();
    latest.error(new Error('Unavailable'));
    expect(page.featuredVideo()?.videoId).toBe('popular'); fixture.destroy();
  });

  it('streams playlist previews with bounded concurrency and preserves embedded previews', () => {
    const pending = Array.from({ length: 5 }, () => new Subject<Playlist>());
    const lists = pending.map((_, index) => ({ playlistId: String(index), itemCount: 1 } as PlaylistSummary));
    const image = { thumbnailUrl: 'preview.jpg' } as PlaylistItem;
    lists.push({ playlistId: 'embedded', itemCount: 1, previewItems: [image] } as PlaylistSummary);
    lists.push({ playlistId: 'empty', itemCount: 0 } as PlaylistSummary);
    playlists.publicByChannel.and.returnValue(of(lists));
    playlists.get.and.callFake(id => pending[Number(id)]);
    const fixture = TestBed.createComponent(ChannelPage), page = fixture.componentInstance;
    page.loadChannel('music');
    expect(playlists.get.calls.count()).toBe(4); expect(page.playlistPreviewById()['embedded']).toEqual([image]);
    pending[0].next({ items: [image] } as Playlist); pending[0].complete();
    expect(page.playlistPreviewById()['0']).toEqual([image]); expect(playlists.get.calls.count()).toBe(5);
    pending[1].error(new Error('Unavailable'));
    expect(page.playlistPreviewById()['0']).toEqual([image]); expect(page.playlistPreviewById()['1']).toEqual([]);
    fixture.destroy(); expect(pending[2].observed).toBeFalse();
  });
});
