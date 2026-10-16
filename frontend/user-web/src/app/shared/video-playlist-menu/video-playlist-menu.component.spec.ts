import { Component, signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { of } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { PlaylistService, PlaylistSummary } from '../../core/playlist.service';
import { VideoPlaylistMenuComponent } from './video-playlist-menu.component';

@Component({ imports: [VideoPlaylistMenuComponent], template: '<app-video-playlist-menu videoId="video-one" /><app-video-playlist-menu videoId="video-two" />' })
class MenuHost {}

describe('Video playlist popovers', () => {
  const choices: PlaylistSummary[] = [{ playlistId: 'playlist-one', name: 'Danh sách đầu tiên', itemCount: 1 }, { playlistId: 'playlist-two', name: 'Danh sách thứ hai', itemCount: 2 }]
    .map(choice => ({ ...choice, userId: 'user-one', description: null, coverUrl: null, visibility: 'private', updatedAt: '2026-10-16T00:00:00Z' }));
  let playlists: jasmine.SpyObj<PlaylistService>;

  beforeEach(() => {
    playlists = jasmine.createSpyObj('playlists', ['mine', 'addVideo']);
    playlists.mine.and.returnValue(of(choices));
    playlists.addVideo.and.returnValue(of({ ...choices[0], createdAt: '2026-10-16T00:00:00Z', items: [] }));
    TestBed.configureTestingModule({ imports: [MenuHost], providers: [provideRouter([]),
      { provide: AuthService, useValue: { user: signal({ userId: 'user-one' }) } },
      { provide: PlaylistService, useValue: playlists },
    ] });
    TestBed.inject(I18nService).setLang('vi');
  });

  it('keeps only the newly opened menu visible across different cards', async () => {
    const fixture = TestBed.createComponent(MenuHost);
    fixture.detectChanges();
    const buttons: HTMLButtonElement[] = Array.from(fixture.nativeElement.querySelectorAll('.video-playlist-menu__trigger'));
    buttons[0].click(); await fixture.whenStable(); fixture.detectChanges(); await fixture.whenStable();
    expect(document.querySelectorAll('.video-playlist-menu__panel:popover-open').length).toBe(1);
    buttons[1].click(); await fixture.whenStable(); fixture.detectChanges(); await fixture.whenStable();
    const panels = fixture.nativeElement.querySelectorAll('.video-playlist-menu__panel');
    expect(panels[0].matches(':popover-open')).toBeFalse();
    expect(panels[1].matches(':popover-open')).toBeTrue();
    expect(buttons[0].getAttribute('aria-expanded')).toBe('false');
    fixture.destroy();
  });

  it('supports arrow navigation and Escape returning focus to the invoker', async () => {
    const fixture = TestBed.createComponent(MenuHost);
    fixture.detectChanges();
    const trigger: HTMLButtonElement = fixture.nativeElement.querySelector('.video-playlist-menu__trigger');
    trigger.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true }));
    await fixture.whenStable();
    fixture.detectChanges(); await fixture.whenStable();
    const items: HTMLButtonElement[] = Array.from(fixture.nativeElement.querySelectorAll('.video-playlist-menu__panel:popover-open [role="menuitem"]'));
    expect(document.activeElement).toBe(items[0]);
    items[0].dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true }));
    expect(document.activeElement).toBe(items[1]);
    items[1].dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
    await fixture.whenStable();
    expect(document.querySelector('.video-playlist-menu__panel:popover-open')).toBeNull();
    expect(document.activeElement).toBe(trigger);
    fixture.destroy();
  });

  it('adds to the playlist for the correct video and closes on page scroll', async () => {
    const fixture = TestBed.createComponent(MenuHost);
    fixture.detectChanges();
    const triggers: HTMLButtonElement[] = Array.from(fixture.nativeElement.querySelectorAll('.video-playlist-menu__trigger'));
    triggers[1].click(); await fixture.whenStable(); fixture.detectChanges(); await fixture.whenStable();
    fixture.nativeElement.querySelector('.video-playlist-menu__panel:popover-open [role="menuitem"]').click();
    await fixture.whenStable();
    expect(playlists.addVideo).toHaveBeenCalledOnceWith('playlist-one', 'video-two');
    const previous = triggers[1].getBoundingClientRect();
    spyOn(triggers[1], 'getBoundingClientRect').and.returnValue(new DOMRect(previous.x, previous.y - 100, previous.width, previous.height));
    document.dispatchEvent(new Event('scroll'));
    await fixture.whenStable();
    expect(document.querySelector('.video-playlist-menu__panel:popover-open')).toBeNull();
    fixture.destroy();
  });
});
