import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { authInterceptor } from '../../core/auth.interceptor';
import { RuntimeConfig } from '../../core/runtime-config';
import {
  AdminModerationService,
  ModerationDecisionResponse,
  ModerationQueueItem
} from './admin-moderation.service';

describe('Admin moderation API contract', () => {
  const base = 'http://localhost:5080/api/v1';
  let http: HttpTestingController;
  let service: AdminModerationService;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([authInterceptor])),
        provideHttpClientTesting()
      ]
    });
    TestBed.inject(RuntimeConfig).apiBaseUrl = base;
    http = TestBed.inject(HttpTestingController);
    service = TestBed.inject(AdminModerationService);
  });

  afterEach(() => http.verify());

  it('uses the backend queue field names', () => {
    let queue: ModerationQueueItem[] | undefined;
    service.getQueue().subscribe(value => queue = value);

    const request = http.expectOne(`${base}/admin/moderation/queue?page=1&pageSize=50`);
    expect(request.request.method).toBe('GET');
    request.flush([{
      moderationCaseId: 'case-1',
      videoId: 'video-1',
      title: 'Video cần duyệt',
      description: 'Mô tả',
      videoUrl: 'https://storage.test/video.mp4',
      thumbnailUrl: null,
      duration: 125,
      channelId: 'channel-1',
      channelName: 'Kênh kiểm thử',
      channelHandle: 'kiem-thu',
      channelAvatarUrl: null,
      caseType: 'upload_review',
      status: 'pending',
      riskLevel: 'high',
      reviewerId: null,
      reviewerName: null,
      submittedAt: '2026-09-14T00:00:00Z',
      claimedAt: null,
      note: null
    }]);

    expect(queue?.[0].title).toBe('Video cần duyệt');
    expect(queue?.[0].description).toBe('Mô tả');
    expect(queue?.[0].duration).toBe(125);
    expect(queue?.[0].note).toBeNull();
  });

  it('sends the backend decision values and reads the response contract', () => {
    let response: ModerationDecisionResponse | undefined;
    service.resolve('case-1', {
      decision: 'age_restricted',
      policyCode: 'SEXUAL_CONTENT',
      reason: 'Giới hạn độ tuổi',
      internalNote: 'Đã review'
    }).subscribe(value => response = value);

    const request = http.expectOne(`${base}/admin/moderation/case-1/resolve`);
    expect(request.request.method).toBe('POST');
    expect(request.request.body).toEqual({
      decision: 'age_restricted',
      policyCode: 'SEXUAL_CONTENT',
      reason: 'Giới hạn độ tuổi',
      internalNote: 'Đã review'
    });
    request.flush({
      moderationCaseId: 'case-1',
      videoId: 'video-1',
      status: 'approved',
      decision: 'age_restricted',
      policyCode: 'SEXUAL_CONTENT',
      message: 'Đã phê duyệt video với giới hạn độ tuổi.'
    });

    expect(response?.moderationCaseId).toBe('case-1');
    expect(response?.decision).toBe('age_restricted');
    expect(response?.policyCode).toBe('SEXUAL_CONTENT');
  });
});
