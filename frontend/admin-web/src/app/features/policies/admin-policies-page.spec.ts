import { TestBed } from '@angular/core/testing';
import { of } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { FeedbackService } from '@dalitu/ui/feedback.service';
import { AdminPoliciesService } from './admin-policies.service';
import { AdminPoliciesPage } from './admin-policies-page';
import { PolicyItem } from '../moderation/admin-moderation.service';

describe('Policy administration preserves published revisions', () => {
  let page: AdminPoliciesPage;
  const policy: PolicyItem = { policyId: 'policy-1', code: 'CHILD_SAFETY', name: 'Updated title',
    content: 'The administrator published this updated content.', group: 'guidelines',
    severity: 'critical', status: 'published', version: '2.1', effectiveAt: '2026-10-24T00:00:00Z' };
  beforeEach(() => {
    TestBed.configureTestingModule({ providers: [
      { provide: AuthService, useValue: { hasPermission: () => true } },
      { provide: FeedbackService, useValue: {} },
      { provide: AdminPoliciesService, useValue: { getAdminPolicies: () => of([policy]) } }
    ] });
    TestBed.inject(I18nService).setLang('vi');
    page = TestBed.runInInjectionContext(() => new AdminPoliciesPage());
  });
  it('uses API text rather than a seed translation when opening the editor', () => {
    page.openDetailModal(policy);
    expect(page.getPolicyName(policy)).toBe('Updated title');
    expect(page.getPolicyContent(policy)).toBe(policy.content);
    expect(page.editContent()).toBe(policy.content);
    expect(page.editVersion()).toBe('2.2');
  });
  it('finds published text and restores all categories when filters are cleared', () => {
    page.ngOnInit(); page.searchQuery.set('administrator published');
    expect(page.filteredPolicies()).toEqual([policy]);
    page.selectedGroup.set('privacy'); expect(page.filteredPolicies()).toEqual([]);
    page.resetFilters(); expect(page.filteredPolicies()).toEqual([policy]);
    expect(page.criticalCount()).toBe(1);
  });
});
