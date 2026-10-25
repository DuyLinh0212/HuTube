import { TestBed } from '@angular/core/testing';
import { AuthService } from '../../core/auth.service';
import { AdminModerationService, PolicyItem, StrikeItem } from './admin-moderation.service';
import { AdminStrikesPage } from './admin-strikes-page';

describe('Strike overview counts and channel shortcuts', () => {
  let page: AdminStrikesPage;
  const strike = (id: string, channelId: string, userId: string, number = 1, status = 'active'): StrikeItem => ({
    strikeId: id, channelId, userId, strikeNumber: number, status, channelName: channelId,
    channelHandle: channelId, channelStatus: 'active', reason: 'Reason', expiresAt: '2099-01-01'
  } as StrikeItem);
  beforeEach(() => {
    TestBed.configureTestingModule({ providers: [
      { provide: AdminModerationService, useValue: {} },
      { provide: AuthService, useValue: { hasPermission: () => true } }
    ] });
    page = TestBed.runInInjectionContext(() => new AdminStrikesPage());
    page.strikes.set([strike('1', 'first', 'owner'), strike('2', 'first', 'owner', 2),
      strike('3', 'second', 'owner'), strike('4', 'revoked', 'other', 1, 'revoked'),
      { ...strike('5', 'warned', 'other', 0), channelStatus: 'suspended' }]);
  });
  it('deduplicates owners and channels, excludes revoked records and counts warnings separately', () => {
    expect(page.affectedUserCount()).toBe(1); expect(page.affectedChannels().length).toBe(2);
    expect(page.affectedChannels()[0].count).toBe(2); expect(page.activeWarningCount()).toBe(1);
    expect(page.lockedChannelCount()).toBe(1);
  });
  it('filters by channel ID and active status without changing global overview counts', () => {
    page.searchQuery.set('unrelated'); page.selectedStatus.set('revoked'); page.focusChannel('first');
    expect(page.searchQuery()).toBe(''); expect(page.selectedStatus()).toBe('active');
    expect(page.filteredStrikes().map(item => item.strikeId)).toEqual(['1', '2']);
    expect(page.affectedChannels().length).toBe(2);
    page.focusChannel('first'); expect(page.selectedChannelId()).toBe('');
  });
  it('shows no affected owners or channels when only expired or revoked strikes remain', () => {
    page.strikes.set([strike('1', 'first', 'owner', 1, 'expired'), strike('2', 'second', 'other', 1, 'revoked')]);
    expect(page.affectedUserCount()).toBe(0); expect(page.affectedChannels()).toEqual([]);
  });
  it('displays a policy name and searches it without requiring its internal code', () => {
    page.policies.set([{ code: 'DANGEROUS_ACTIVITIES', name: 'Hoạt động nguy hiểm hoặc có hại' } as PolicyItem]);
    page.strikes.set([{ ...strike('1', 'first', 'owner'), policyCode: 'DANGEROUS_ACTIVITIES' }]);
    expect(page.policyName('DANGEROUS_ACTIVITIES')).toBe('Hoạt động nguy hiểm hoặc có hại');
    page.searchQuery.set('nguy hiểm'); expect(page.filteredStrikes().length).toBe(1);
    expect(page.policyName('REMOVED_POLICY')).not.toContain('REMOVED_POLICY');
  });
});
