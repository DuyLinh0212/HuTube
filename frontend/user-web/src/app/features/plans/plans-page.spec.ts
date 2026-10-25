import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { of } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { MyPlan, PlanMember } from '../../core/plan.service';
import { RuntimeConfig } from '../../core/runtime-config';
import { PlansPage } from './plans-page';

describe('Family storage display', () => {
  const gb = 1024 ** 3;
  const base = 'http://localhost:5080/api/v1/plans';
  let http: HttpTestingController;
  function member(id: string, status = 'accepted'): PlanMember {
    return { planMemberId: id, planId: 'family', ownerUserId: 'owner', memberEmail: `${id}@example.test`,
      memberUserId: status === 'pending' ? null : id, status, invitedAt: '2026-10-25T00:00:00Z',
      acceptedAt: null, revokedAt: null, allocatedStorage: 8 * gb, storageUsed: id === 'alice' ? 3 * gb : 0 };
  }
  function plan(overrides: Partial<MyPlan> = {}): MyPlan {
    return { planId: 'family', code: 'family', name: 'Family', description: null, price: 99000, durationDays: 30,
      storageLimit: 30 * gb, usedStorage: 5 * gb, remainingStorage: 25 * gb, maxUploadSize: gb,
      maxVideoDuration: 3600, maxVideoQuality: '1080p', maxMembers: 4, status: 'active',
      members: [member('alice'), member('bob')], ownerAllocatedStorage: 10 * gb, ownerOwnStorageUsed: 2 * gb,
      storageUsageBreakdown: [
        { userId: 'owner', displayName: 'Owner', storageUsed: 2 * gb, isOwner: true },
        { userId: 'alice', displayName: 'Alice', storageUsed: 3 * gb, isOwner: false },
        { userId: 'bob', displayName: 'Bob', storageUsed: 0, isOwner: false },
      ], ...overrides };
  }
  beforeEach(() => {
    TestBed.configureTestingModule({ imports: [PlansPage], providers: [provideHttpClient(), provideHttpClientTesting(), provideRouter([]),
      { provide: AuthService, useValue: { user: signal({ userId: 'owner', displayName: 'Owner' }), restore: () => of(true) } }] });
    TestBed.inject(RuntimeConfig).apiBaseUrl = base.slice(0, -6);
    TestBed.inject(I18nService).currentLang.set('vi');
    http = TestBed.inject(HttpTestingController);
  });
  afterEach(() => http.verify());
  function setup(data = plan()) {
    const fixture = TestBed.createComponent(PlansPage);
    http.expectOne(base).flush([]);
    http.expectOne(base + '/my-plan').flush(data);
    fixture.detectChanges();
    return fixture;
  }

  it('hides allocation before inviting anyone, for both personal and family plans', () => {
    for (const maxMembers of [1, 4]) {
      const fixture = setup(plan({ maxMembers, members: [], storageUsageBreakdown: [
        { userId: 'owner', displayName: 'Owner', storageUsed: 5 * gb, isOwner: true }
      ] }));
      expect(fixture.nativeElement.querySelector('.quota-allocation-bar')).toBeNull();
      expect(fixture.nativeElement.querySelector('.family-storage-bar')).toBeNull();
      fixture.componentInstance.startEditOwnerStorage();
      expect(fixture.componentInstance.editingOwnerStorage()).toBeFalse();
      fixture.destroy();
    }
  });

  it('shows allocation after inviting, with a pending invitation contributing no used storage', () => {
    const fixture = setup(plan({ members: [member('alice', 'pending')], storageUsageBreakdown: [
      { userId: 'owner', displayName: 'Owner', storageUsed: 5 * gb, isOwner: true }
    ] }));
    expect(fixture.nativeElement.querySelector('.quota-allocation-bar')).not.toBeNull();
    expect(fixture.nativeElement.querySelector('.family-storage-bar')).toBeNull();
    fixture.componentInstance.startEditOwnerStorage();
    expect(fixture.componentInstance.editingOwnerStorage()).toBeTrue();
  });

  it('shows actual usage for every accepted member, including zero usage, and free space', () => {
    const fixture = setup();
    const page = fixture.componentInstance;
    const rows = page.storageSlices(page.myPlan()!);
    expect(rows.map(row => [row.label, row.bytes])).toEqual([
      ['Bạn (chủ gói)', 2 * gb], ['Alice', 3 * gb], ['Bob', 0], ['Còn trống', 25 * gb]
    ]);
    expect(rows.reduce((sum, row) => sum + row.percent, 0)).toBeCloseTo(100, 8);
    expect(new Set(rows.map(row => row.color)).size).toBe(4);
    const bar = fixture.nativeElement.querySelector('.family-storage-bar') as HTMLElement;
    expect(bar.getAttribute('role')).toBe('img');
    expect(bar.getAttribute('aria-label')).toContain('Alice: 3 GB');
    expect(bar.querySelectorAll('.storage-segment').length).toBe(3);
    expect(fixture.nativeElement.querySelectorAll('.storage-legend li').length).toBe(4);
    expect(fixture.nativeElement.querySelector('.storage-legend').textContent).toContain('25 GB');
  });

  it('does not expose family usage or allocation controls to shared members', () => {
    const fixture = setup(plan({ isSharedMember: true }));
    expect(fixture.nativeElement.querySelector('.quota-allocation-bar')).toBeNull();
    expect(fixture.nativeElement.querySelector('.family-storage-bar')).toBeNull();
    expect(fixture.nativeElement.querySelector('.shared-member-quota-note')).not.toBeNull();
  });

  it('keeps the basic progress display when an older API has no breakdown', () => {
    const fixture = setup(plan({ storageUsageBreakdown: undefined }));
    expect(fixture.nativeElement.querySelector('.family-storage-bar')).toBeNull();
    expect(fixture.nativeElement.querySelector('[role=progressbar]')).not.toBeNull();
  });

  it('keeps over-capacity slices bounded and reports zero free space', () => {
    const fixture = setup(plan({ storageLimit: 4 * gb, remainingStorage: 0 }));
    const page = fixture.componentInstance;
    const slices = page.storageSlices(page.myPlan()!);
    expect(slices.find(row => row.free)?.bytes).toBe(0);
    expect(slices.reduce((sum, row) => sum + row.percent, 0)).toBeCloseTo(100, 8);
    expect(slices.every(row => row.percent >= 0 && row.percent <= 100)).toBeTrue();
  });

  it('hides allocation after the last revocation and labels still-billed media as a former member', () => {
    const fixture = setup(plan({ members: [member('alice')], storageUsageBreakdown: [
      { userId: 'owner', displayName: 'Owner', storageUsed: 2 * gb, isOwner: true },
      { userId: 'alice', displayName: 'Alice', storageUsed: 3 * gb, isOwner: false },
    ] }));
    const page = fixture.componentInstance;
    page.startEditOwnerStorage();
    page.revoke('alice');
    http.expectOne(base + '/members/alice').flush(null);
    fixture.detectChanges();
    expect(page.editingOwnerStorage()).toBeFalse();
    expect(fixture.nativeElement.querySelector('.quota-allocation-bar')).toBeNull();
    expect(fixture.nativeElement.querySelector('.storage-legend').textContent).toContain('Alice (đã rời nhóm)');
  });

  it('localizes the breakdown for English', () => {
    const fixture = setup();
    TestBed.inject(I18nService).currentLang.set('en');
    fixture.detectChanges();
    const legend = fixture.nativeElement.querySelector('.storage-legend').textContent;
    expect(legend).toContain('You (plan owner)');
    expect(legend).toContain('Free space');
  });
});
