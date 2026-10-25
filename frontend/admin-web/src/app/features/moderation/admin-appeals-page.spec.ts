import { registerLocaleData } from '@angular/common';
import localeVi from '@angular/common/locales/vi';
import { TestBed } from '@angular/core/testing';
import { signal } from '@angular/core';
import { of } from 'rxjs';
import { AdminAppealsPage } from './admin-appeals-page';
import { AdminModerationService, AppealItem } from './admin-moderation.service';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';

const appeal: AppealItem = { appealId: 'appeal-uuid', userId: 'owner', userName: 'Danh', targetType: 'channel',
  targetId: '1d6700df-6586-41bc-a6eb-2c6f02e349a5', targetTitle: 'Kênh của Danh (@danh)', appealNumber: 3,
  reviewerId: 'reviewer', reviewerName: 'Quản trị viên', reason: 'Tôi không vi phạm. Xin kiểm tra toàn bộ nội dung.',
  status: 'approved', reviewNote: 'Đã kiểm tra lại và gỡ hạn chế.', evidenceUrl: '/api/evidence', evidenceNote: 'Tệp chứng minh quyền sở hữu',
  moderationCaseId: 'moderation-id', strikeId: null, createdAt: '2026-10-24T00:00:00Z', resolvedAt: '2026-10-25T00:00:00Z' };
describe('Appeal readability and case details', () => {
  beforeAll(() => registerLocaleData(localeVi));
  const viewer = signal({ userId: 'viewer' });
  beforeEach(() => {
    TestBed.configureTestingModule({ imports: [AdminAppealsPage], providers: [
      { provide: AdminModerationService, useValue: { getAppeals: () => of([appeal]) } },
      { provide: AuthService, useValue: { user: viewer, hasPermission: () => false } }
    ] });
    TestBed.inject(I18nService).setLang('vi');
  });
  it('opens processed cases read-only with full reasons, evidence notes, outcome and reference IDs', () => {
    const fixture = TestBed.createComponent(AdminAppealsPage); fixture.detectChanges();
    const page = fixture.componentInstance; page.setStatus('ALL'); fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('.appeal-title-button').textContent).toContain('@danh');
    expect(fixture.nativeElement.querySelector('tbody').textContent).not.toContain(appeal.targetId);
    page.openDetails(appeal); fixture.detectChanges(); TestBed.tick();
    const dialog: HTMLDialogElement = fixture.nativeElement.querySelector('.appeal-detail-dialog');
    expect(dialog.open).toBeTrue(); expect(dialog.textContent).toContain(appeal.reason);
    expect(dialog.textContent).toContain(appeal.evidenceNote); expect(dialog.textContent).toContain(appeal.reviewNote);
    expect(dialog.querySelector('.appeal-references')?.textContent).toContain(appeal.targetId);
    expect(dialog.querySelector('.btn-primary')).toBeNull(); page.openResolveModal(appeal); expect(page.isResolveModalOpen()).toBeFalse();
    page.closeDetails(); fixture.detectChanges(); expect(fixture.nativeElement.querySelector('.appeal-detail-dialog')).toBeNull();
  });
  it('handles legacy CHANNEL(UUID) responses without displaying an identifier as the title', () => {
    const fixture = TestBed.createComponent(AdminAppealsPage); const page = fixture.componentInstance;
    expect(page.targetTitle({ ...appeal, targetTitle: `CHANNEL (${appeal.targetId})` })).toBe('Kênh');
    expect(page.targetTitle({ ...appeal, targetTitle: appeal.targetId })).toBe('Kênh');
    expect(page.targetTitle(appeal)).toBe(appeal.targetTitle!);
  });
  it('searches by case references and clears date/type filters without changing the status tab', () => {
    const fixture = TestBed.createComponent(AdminAppealsPage); fixture.detectChanges(); const page = fixture.componentInstance;
    page.setStatus('ALL'); page.setSearchQuery('#3'); expect(page.filteredAppeals()).toEqual([appeal]);
    page.setSubmittedFrom('2026-10-25'); page.setSubmittedTo('2026-10-24'); expect(page.invalidDateRange()).toBeTrue();
    page.resetFilters(); expect(page.invalidDateRange()).toBeFalse(); expect(page.filteredAppeals()).toEqual([appeal]); expect(page.selectedStatus()).toBe('ALL');
  });
});
