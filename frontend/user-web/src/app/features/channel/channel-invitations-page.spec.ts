import { TestBed, fakeAsync, flushMicrotasks } from '@angular/core/testing';
import { signal } from '@angular/core';
import { Subject } from 'rxjs';
import { ChannelDetail, ChannelInvitation, ChannelService } from '../../core/channel.service';
import { NotificationService } from '../../core/notification.service';
import { ChannelInvitationsPage } from './channel-invitations-page';

describe('Independent invitation and channel requests', () => {
  let invitations: Subject<ChannelInvitation[]>;
  let channels: Subject<ChannelDetail[]>;
  const invitation = { channelInvitationId: 'invite', channelName: 'Music' } as ChannelInvitation;
  const channel = { channelId: 'channel', isOwner: false } as ChannelDetail;

  beforeEach(() => {
    invitations = new Subject(); channels = new Subject();
    TestBed.configureTestingModule({ providers: [
      { provide: ChannelService, useValue: { getMyInvitations: () => invitations, getAccessibleChannels: () => channels } },
      { provide: NotificationService, useValue: { invitationVersion: signal(0) } },
    ] });
    TestBed.overrideComponent(ChannelInvitationsPage, { set: { template: '', imports: [] } });
  });

  it('renders invitations without waiting for channel permissions and isolates a channel error', fakeAsync(() => {
    const fixture = TestBed.createComponent(ChannelInvitationsPage), page = fixture.componentInstance;
    void page.load(); expect(invitations.observed && channels.observed).toBeTrue();
    invitations.next([invitation]); flushMicrotasks();
    expect(page.invitations()).toEqual([invitation]); expect(page.invitationsLoading()).toBeFalse();
    expect(page.channelsLoading()).toBeTrue();
    channels.error(new Error('Unavailable')); flushMicrotasks();
    expect(page.invitations()).toEqual([invitation]); expect(page.loading()).toBeFalse();
    expect(page.error()).not.toBe(''); fixture.destroy();
  }));

  it('retains accessible channels even when invitations fail', fakeAsync(() => {
    const fixture = TestBed.createComponent(ChannelInvitationsPage), page = fixture.componentInstance;
    void page.load(); invitations.error(new Error('Unavailable')); flushMicrotasks();
    expect(channels.observed).toBeTrue(); channels.next([channel]); flushMicrotasks();
    expect(page.collaboratingChannels()).toEqual([channel]); expect(page.loading()).toBeFalse();
    fixture.destroy();
  }));

  it('cancels both in-flight requests when the page is destroyed', fakeAsync(() => {
    const fixture = TestBed.createComponent(ChannelInvitationsPage), page = fixture.componentInstance;
    void page.load(); fixture.destroy(); flushMicrotasks();
    expect(invitations.observed || channels.observed).toBeFalse(); expect(page.error()).toBe('');
  }));

  it('cancels stale loads before starting the replacement requests', fakeAsync(() => {
    const fixture = TestBed.createComponent(ChannelInvitationsPage), page = fixture.componentInstance;
    void page.load();
    const oldInvitations = invitations, oldChannels = channels;
    invitations = new Subject(); channels = new Subject();
    void page.load(); expect(oldInvitations.observed || oldChannels.observed).toBeFalse();
    invitations.next([invitation]); channels.next([channel]); flushMicrotasks();
    oldInvitations.next([]); oldChannels.error(new Error('Old request')); flushMicrotasks();
    expect(page.invitations()).toEqual([invitation]); expect(page.accessibleChannels()).toEqual([channel]);
    expect(page.error()).toBe(''); fixture.destroy();
  }));
});
