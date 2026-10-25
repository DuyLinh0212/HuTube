import { TestBed } from '@angular/core/testing';
import { signal } from '@angular/core';
import { of, Subject } from 'rxjs';
import { AdminReportsPage } from './admin-reports-page';
import { AdminModerationService, ReportCaseDetail } from './admin-moderation.service';
import { AuthService } from '../../core/auth.service';

describe('Report case workflow', () => {
  const detail = (): ReportCaseDetail => ({ case: {
    caseId: 'case', targetType: 'video', targetId: 'video', targetTitle: 'Video', targetUrl: null,
    targetThumbnailUrl: null, targetChannelName: 'Channel', targetChannelHandle: 'channel',
    status: 'reviewing', reportCount: 1, reporterCount: 1, unclassifiedCount: 1, violationCounts: [],
    reviewerId: 'reviewer', reviewerName: 'Reviewer', claimId: 'claim', claimExpiresAt: '2099-01-01',
    submittedAt: '2026-10-25', updatedAt: '2026-10-25'
  }, reports: [{ reportId: 'report', userId: 'user', reporterName: 'User', violationTypeId: 'type',
    violationTypeCode: 'harmful', violationTypeName: 'Harmful', description: 'Report description',
    status: 'pending', disposition: null, dispositionReason: null, dispositionByUserId: null,
    dispositionAt: null, abuseFlag: false, createdAt: '2026-10-25', updatedAt: '2026-10-25' }] });
  let current: ReportCaseDetail;
  let api: { getReportCase: jasmine.Spy; getPolicies: jasmine.Spy; getReportCases: jasmine.Spy;
    updateReportDispositions: jasmine.Spy; resolveReportCase: jasmine.Spy };
  let page: AdminReportsPage;
  beforeEach(() => {
    current = detail();
    api = {
      getReportCase: jasmine.createSpy().and.callFake(() => of(current)),
      getPolicies: jasmine.createSpy().and.returnValue(of([])),
      getReportCases: jasmine.createSpy().and.returnValue(of({ items: [], total: 0, page: 1, pageSize: 100 })),
      updateReportDispositions: jasmine.createSpy().and.returnValue(new Subject()),
      resolveReportCase: jasmine.createSpy().and.returnValue(new Subject())
    };
    TestBed.configureTestingModule({ imports: [AdminReportsPage], providers: [
      { provide: AdminModerationService, useValue: api },
      { provide: AuthService, useValue: { user: signal({ userId: 'reviewer' }), hasPermission: () => true } }
    ] });
    page = TestBed.createComponent(AdminReportsPage).componentInstance;
  });
  it('requires classification, an explicit decision, and a rationale before closing', () => {
    page.openCase(current.case);
    expect(page.selectedReportIds()).toEqual(['report']);
    expect(page.policyCode()).toBe(''); expect(page.decision()).toBe('');
    page.decisionReason.set('Reviewed evidence'); expect(page.canCloseCase()).toBeFalse();
    current.reports[0].disposition = 'accepted'; page.activeCase.set({ ...current });
    expect(page.canCloseCase()).toBeFalse();
    page.decision.set('warn'); expect(page.canCloseCase()).toBeTrue();
    page.resolveCase(); page.resolveCase(); expect(api.resolveReportCase).toHaveBeenCalledTimes(1);
  });
  it('selects only unclassified reports and blocks duplicate classification submissions', () => {
    current.reports.push({ ...current.reports[0], reportId: 'classified', disposition: 'rejected' });
    page.openCase(current.case); page.selectUnclassified();
    expect(page.selectedReportIds()).toEqual(['report']);
    page.dispositionReason.set('Evidence reviewed'); page.classify('accepted'); page.classify('accepted');
    expect(api.updateReportDispositions).toHaveBeenCalledTimes(1);
    expect(api.updateReportDispositions.calls.mostRecent().args[1].reportIds).toEqual(['report']);
  });
  it('preserves a draft on refresh and clears it when another case opens', () => {
    page.openCase(current.case); page.internalNote.set('Private note'); page.restrictionDays.set(14); page.decision.set('warn');
    page.openCase(current.case, true); expect(page.internalNote()).toBe('Private note'); expect(page.decision()).toBe('warn');
    page.openCase({ ...current.case, caseId: 'another' });
    expect(page.internalNote()).toBe(''); expect(page.restrictionDays()).toBe(7); expect(page.decision()).toBe('');
  });
  it('ignores late detail responses after closing the dialog', () => {
    const response = new Subject<ReportCaseDetail>(); api.getReportCase.and.returnValue(response);
    page.openCase(current.case); page.closeCase(); response.next(current);
    expect(page.activeCase()).toBeNull(); expect(page.detailLoading()).toBeFalse();
  });
  it('requires whole restriction days within the supported range', () => {
    current.reports[0].disposition = 'accepted'; page.openCase(current.case);
    page.decision.set('upload_restriction'); page.decisionReason.set('Repeat violation');
    for (const days of [0, 31, 1.5]) { page.restrictionDays.set(days); expect(page.canCloseCase()).toBeFalse(); }
    page.restrictionDays.set(7); expect(page.canCloseCase()).toBeTrue();
  });
  it('saves one conclusion at a time and advances to the next unclassified report', () => {
    current.reports.push({ ...current.reports[0], reportId: 'second' });
    api.updateReportDispositions.and.callFake((_id: string, request: { reportIds: string[]; disposition: string; reason: string }) => {
      const report = current.reports.find(item => item.reportId === request.reportIds[0])!;
      report.disposition = request.disposition; report.dispositionReason = request.reason;
      return of(undefined);
    });
    page.openCase(current.case);
    expect(page.focusedReport()?.reportId).toBe('report');
    expect(page.canSaveCurrentReport()).toBeFalse();
    page.reportDisposition.set('accepted'); page.dispositionReason.set('Verified evidence'); page.saveCurrentReport();
    expect(api.updateReportDispositions.calls.mostRecent().args[1].reportIds).toEqual(['report']);
    expect(page.focusedReport()?.reportId).toBe('second'); expect(page.reportDisposition()).toBe('');
    expect(page.reviewStage()).toBe('classification'); expect(page.dispositionReason()).toBe('');
    page.reportDisposition.set('rejected'); page.dispositionReason.set('Insufficient evidence'); page.saveCurrentReport();
    expect(page.reviewStage()).toBe('resolution'); expect(page.allClassified()).toBeTrue();
    expect(page.decision()).toBe(''); expect(page.canCloseCase()).toBeFalse();
    page.showReport('report'); expect(page.reportDisposition()).toBe('accepted');
    expect(page.dispositionReason()).toBe('Verified evidence');
  });
  it('keeps the action step locked while a report is unclassified', () => {
    page.openCase(current.case); page.showResolution(); expect(page.reviewStage()).toBe('classification');
    page.reportDisposition.set('accepted'); page.dispositionReason.set('x'); page.saveCurrentReport();
    expect(api.updateReportDispositions).not.toHaveBeenCalled();
  });
});
