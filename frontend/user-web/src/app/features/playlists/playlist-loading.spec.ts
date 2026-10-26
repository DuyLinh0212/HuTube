import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, Router } from '@angular/router';
import { EMPTY, Subject, of } from 'rxjs';
import { FeedbackService } from '@dalitu/ui/feedback.service';
import { AuthService } from '../../core/auth.service';
import { ChannelService } from '../../core/channel.service';
import { Playlist, PlaylistService, PlaylistSummary } from '../../core/playlist.service';
import { PlaylistsPage } from './playlists-page';

describe('Progressive playlist previews', () => {
  let service: jasmine.SpyObj<PlaylistService>;
  const list = (id: string) => ({ playlistId: id, itemCount: 1 } as PlaylistSummary);

  beforeEach(() => {
    service = jasmine.createSpyObj('playlists', ['mine', 'get']);
    TestBed.configureTestingModule({ providers: [
      { provide: PlaylistService, useValue: service }, { provide: ChannelService, useValue: {} },
      { provide: FeedbackService, useValue: {} },
      { provide: AuthService, useValue: { user: signal(null) } },
      { provide: ActivatedRoute, useValue: { paramMap: EMPTY, queryParamMap: EMPTY } },
      { provide: Router, useValue: {} },
    ] });
    TestBed.overrideComponent(PlaylistsPage, { set: { template: '', imports: [] } });
  });

  it('renders a fast preview while another is pending, and keeps it when that other request fails', () => {
    const fast = new Subject<Playlist>(), slow = new Subject<Playlist>();
    service.mine.and.returnValue(of([list('fast'), list('slow')]));
    service.get.and.callFake(id => id === 'fast' ? fast : slow);
    const fixture = TestBed.createComponent(PlaylistsPage), page = fixture.componentInstance;
    page.loadMine(); expect(fast.observed && slow.observed).toBeTrue();
    const detail = { playlistId: 'fast', items: [] } as unknown as Playlist;
    fast.next(detail); fast.complete(); expect(page.previewById()['fast']).toBe(detail);
    slow.error(new Error('Unavailable'));
    expect(page.previewById()['fast']).toBe(detail); expect(page.previewById()['slow']).toBeNull();
    fixture.destroy();
  });

  it('cancels obsolete previews on reload and skips already supplied or empty previews', () => {
    const pending = new Subject<Playlist>();
    service.mine.and.returnValue(of([list('old')])); service.get.and.returnValue(pending);
    const fixture = TestBed.createComponent(PlaylistsPage), page = fixture.componentInstance;
    page.loadMine(); expect(pending.observed).toBeTrue();
    service.mine.and.returnValue(of([{ ...list('new'), previewItems: [] }, { ...list('empty'), itemCount: 0 }]));
    page.loadMine(); expect(pending.observed).toBeFalse(); expect(service.get.calls.count()).toBe(1);
    expect(page.previewById()['old']).toBeUndefined(); expect(page.previewById()['new']?.items).toEqual([]);
    fixture.destroy();
  });
});
