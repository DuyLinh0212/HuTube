import { TestBed } from '@angular/core/testing';
import { signal } from '@angular/core';
import { provideRouter } from '@angular/router';
import { of, Subject, throwError } from 'rxjs';
import { FeedbackService } from '@dalitu/ui/feedback.service';
import { AuthService } from '../../core/auth.service';
import { AdminModerationService, ModerationQueueItem, ReportCaseSummary, AppealItem } from './admin-moderation.service';
import { AdminModerationPage } from './admin-moderation-page';
import { AdminReportsPage } from './admin-reports-page';
import { AdminAppealsPage } from './admin-appeals-page';

describe('Open a case directly for review', () => {
  const lease = { claimId: 'lease', claimExpiresAt: '2099-01-01' };
  let api: Record<string, jasmine.Spy>;
  beforeEach(() => {
    api = Object.fromEntries(['claim', 'claimReportCase', 'claimAppeal', 'getReportCase', 'getReportCases', 'getPolicies'].map(key => [key, jasmine.createSpy(key)]));
    api['claim'].and.returnValue(of(lease)); api['claimAppeal'].and.returnValue(of(lease));
    api['claimReportCase'].and.returnValue(of(lease)); api['getPolicies'].and.returnValue(of([]));
    api['getReportCases'].and.returnValue(of({ items: [], total: 0, page: 1, pageSize: 100 }));
    TestBed.configureTestingModule({ providers: [
      provideRouter([]),
      { provide: AdminModerationService, useValue: api },
      { provide: AuthService, useValue: { user: signal({ userId: 'me', displayName: 'Reviewer' }), hasPermission: () => true } },
      { provide: FeedbackService, useValue: { confirm: () => Promise.resolve(true) } }
    ] });
  });
  const video = (id = 'video'): ModerationQueueItem => ({ moderationCaseId: id, status: 'pending', reviewerId: null } as ModerationQueueItem);
  it('acquires the video lease and opens review in one action', () => {
    const page = TestBed.createComponent(AdminModerationPage).componentInstance;
    const item = video(); page.queue.set([item]); page.loading.set(false); page.openReviewModal(item);
    expect(api['claim']).toHaveBeenCalledOnceWith(item.moderationCaseId);
    expect(page.isReviewModalOpen()).toBeTrue(); expect(page.activeCase()?.claimId).toBe('lease');
    expect(page.isClaimedByMe(page.activeCase()!)).toBeTrue();
  });
  it('prevents duplicate video requests and leaves the modal closed on a conflict', () => {
    const page = TestBed.createComponent(AdminModerationPage).componentInstance;
    const response = new Subject(); api['claim'].and.returnValue(response);
    const item = video(); page.loading.set(false); page.openReviewModal(item); page.openReviewModal(item);
    expect(api['claim']).toHaveBeenCalledTimes(1);
    response.error({ error: { detail: 'Already being reviewed' } });
    expect(page.isReviewModalOpen()).toBeFalse(); expect(page.error()).toBe('Already being reviewed');
  });
  it('opens another reviewer’s video read-only without acquiring it', () => {
    const page = TestBed.createComponent(AdminModerationPage).componentInstance;
    const item = { ...video(), ...lease, status: 'reviewing' as const, reviewerId: 'someone-else' };
    page.loading.set(false); page.openReviewModal(item);
    expect(api['claim']).not.toHaveBeenCalled(); expect(page.canDecideActive()).toBeFalse();
  });
  it('opens only successfully acquired videos in a batch with a partial conflict', () => {
    const page = TestBed.createComponent(AdminModerationPage).componentInstance;
    const items = [video('one'), video('two')]; page.queue.set(items); page.loading.set(false);
    page.selectedCaseIds.set(['one', 'two']);
    api['claim'].and.callFake((id: string) => id === 'one' ? of(lease) : throwError(() => ({ error: { detail: 'Busy' } })));
    page.openQuickReview();
    expect(page.reviewTabs().map(item => item.moderationCaseId)).toEqual(['one']);
    expect(page.bulkResult()?.failed.length).toBe(1); expect(page.quickReview()).toBeTrue();
  });
  it('acquires a report case before loading its editable details', () => {
    const page = TestBed.createComponent(AdminReportsPage).componentInstance;
    const item = { caseId: 'report', status: 'pending' } as ReportCaseSummary;
    api['getReportCase'].and.returnValue(of({ case: { ...item, ...lease, status: 'reviewing', reviewerId: 'me' }, reports: [] }));
    page.startCase(item);
    expect(api['claimReportCase']).toHaveBeenCalledOnceWith('report');
    expect(page.canEditCase()).toBeTrue(); expect(page.activeCase()?.case.claimId).toBe('lease');
  });
  it('does not open a report case for editing after a claim conflict', () => {
    const page = TestBed.createComponent(AdminReportsPage).componentInstance;
    api['claimReportCase'].and.returnValue(throwError(() => ({ error: { message: 'Busy' } })));
    page.startCase({ caseId: 'report', status: 'pending' } as ReportCaseSummary);
    expect(api['getReportCase']).not.toHaveBeenCalled(); expect(page.activeCase()).toBeNull();
  });
  it('opens appeal resolution immediately with the acquired lease', () => {
    const page = TestBed.createComponent(AdminAppealsPage).componentInstance;
    const item = { appealId: 'appeal', status: 'pending' } as AppealItem; page.appeals.set([item]);
    page.startAppeal(item); expect(api['claimAppeal']).toHaveBeenCalledOnceWith('appeal');
    expect(page.isResolveModalOpen()).toBeTrue(); expect(page.activeAppeal()?.claimId).toBe('lease');
  });
});
