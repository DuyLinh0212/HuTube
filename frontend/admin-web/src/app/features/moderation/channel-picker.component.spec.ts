import { TestBed, fakeAsync, tick } from '@angular/core/testing';
import { NEVER, Subject, of, throwError } from 'rxjs';
import { ChannelPickerComponent } from './channel-picker.component';
import { AdminModerationService, ModerationChannelOption } from './admin-moderation.service';
import { AdminStrikesPage } from './admin-strikes-page';
import { AuthService } from '../../core/auth.service';

const channel: ModerationChannelOption = { channelId: 'channel-uuid', name: 'Tên kênh', handle: 'creator', status: 'active' };
describe('Channel handle lookup and selection', () => {
  let service: jasmine.SpyObj<AdminModerationService>;
  beforeEach(() => {
    service = jasmine.createSpyObj('AdminModerationService', ['lookupChannels', 'createStrike']);
    service.lookupChannels.and.returnValue(of([channel]));
    TestBed.configureTestingModule({ imports: [ChannelPickerComponent], providers: [
      { provide: AdminModerationService, useValue: service }, { provide: AuthService, useValue: { hasPermission: () => true } }
    ] });
  });
  it('ignores a previous response as soon as the user types another handle', fakeAsync(() => {
    const first = new Subject<ModerationChannelOption[]>(), second = new Subject<ModerationChannelOption[]>();
    service.lookupChannels.and.returnValues(first, second);
    const fixture = TestBed.createComponent(ChannelPickerComponent), picker = fixture.componentInstance;
    fixture.detectChanges(); picker.search('@old'); tick(250); picker.search('@new');
    first.next([channel]); expect(picker.results()).toEqual([]);
    tick(250); const newer = { ...channel, handle: 'new', channelId: 'new-id' }; second.next([newer]);
    expect(picker.results()).toEqual([newer]); expect(service.lookupChannels.calls.allArgs()).toEqual([['old'], ['new']]);
    fixture.destroy();
  }));
  it('supports retrying the same handle after a failed request', fakeAsync(() => {
    service.lookupChannels.and.returnValues(throwError(() => new Error('offline')), of([channel]));
    const fixture = TestBed.createComponent(ChannelPickerComponent), picker = fixture.componentInstance;
    fixture.detectChanges(); picker.search('@creator'); tick(250); expect(picker.failed()).toBeTrue();
    picker.search('@creator'); tick(250); expect(picker.failed()).toBeFalse(); expect(picker.results()).toEqual([channel]);
    fixture.destroy();
  }));
  it('selects a result with Enter and prevents form submission for an unknown handle', fakeAsync(() => {
    const fixture = TestBed.createComponent(ChannelPickerComponent), picker = fixture.componentInstance;
    const picked: Array<ModerationChannelOption | null> = []; picker.picked.subscribe(value => picked.push(value));
    fixture.detectChanges(); picker.search('@creator'); tick(250);
    const enter = new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }); picker.onKeydown(enter);
    expect(enter.defaultPrevented).toBeTrue(); expect(picked.at(-1)).toEqual(channel);
    picker.search('@missing'); const unknown = new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }); picker.onKeydown(unknown);
    expect(unknown.defaultPrevented).toBeTrue(); expect(picked.at(-1)).toBeNull(); fixture.destroy();
  }));
  it('clears the saved ID when the selection is edited and sends the selected UUID rather than its handle', () => {
    service.createStrike.and.returnValue(NEVER);
    const page = TestBed.runInInjectionContext(() => new AdminStrikesPage());
    page.selectCreateChannel(channel); page.createReason.set(' Lý do xử lý '); page.selectCreateChannel(null); page.submitCreateStrike();
    expect(page.createChannelId()).toBe(''); expect(service.createStrike).not.toHaveBeenCalled();
    page.selectCreateChannel(channel); page.submitCreateStrike();
    expect(service.createStrike).toHaveBeenCalledWith(jasmine.objectContaining({ channelId: 'channel-uuid', reason: 'Lý do xử lý' }));
  });
  it('prefills a suspended channel for unlock and clears its ID when another handle is typed', () => {
    const page = TestBed.runInInjectionContext(() => new AdminStrikesPage());
    page.selectLockChannel({ ...channel, status: 'suspended' }); expect(page.lockAction()).toBe('unlock');
    expect(page.lockChannelId()).toBe(channel.channelId); page.selectLockChannel(null); expect(page.lockChannelId()).toBe('');
  });
});
