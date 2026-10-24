import { ComponentFixture, TestBed, fakeAsync, tick } from '@angular/core/testing';
import { signal } from '@angular/core';
import { of, Subject } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { FeedbackSurveyService, FeedbackSurveyStatus } from '../../core/feedback-survey.service';
import { FeedbackSurveyComponent, SURVEY_DELAY_MS } from './feedback-survey.component';

describe('Feedback survey invitation', () => {
  const pending: FeedbackSurveyStatus = {
    enabled: true, hasCompleted: false, completedAt: null,
    formUrl: 'https://docs.google.com/forms/d/e/test/viewform?entry.123=account-token',
  };
  let fixture: ComponentFixture<FeedbackSurveyComponent>;
  let component: FeedbackSurveyComponent;
  let user: ReturnType<typeof signal<{ userId: string } | null>>;
  let surveys: jasmine.SpyObj<FeedbackSurveyService>;

  beforeEach(() => {
    user = signal<{ userId: string } | null>({ userId: 'user-one' });
    surveys = jasmine.createSpyObj<FeedbackSurveyService>('surveys', ['getStatus']);
    surveys.getStatus.and.returnValue(of(pending));
    TestBed.configureTestingModule({
      imports: [FeedbackSurveyComponent],
      providers: [
        { provide: AuthService, useValue: { user } },
        { provide: FeedbackSurveyService, useValue: surveys },
      ],
    });
    spyOnProperty(document, 'visibilityState', 'get').and.returnValue('visible');
  });
  afterEach(() => fixture.destroy());

  function render(): void {
    fixture = TestBed.createComponent(FeedbackSurveyComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  }

  it('waits two minutes and does not restart on same-user session refresh', fakeAsync(() => {
    render();
    tick(60_000);
    user.set({ userId: 'user-one' });
    fixture.detectChanges();
    tick(59_999);
    expect(surveys.getStatus).not.toHaveBeenCalled();
    tick(1);
    fixture.detectChanges();
    expect(component.phase()).toBe('invitation');
    expect(fixture.nativeElement.querySelector('dialog').open).toBeTrue();
    component.requestClose();
    component.requestClose();
    tick(SURVEY_DELAY_MS * 2);
    expect(component.phase()).toBe('closed');
    expect(surveys.getStatus).toHaveBeenCalledTimes(1);
  }));

  it('shows the plea on backdrop or Escape, then allows a final dismissal', fakeAsync(() => {
    render();
    tick(SURVEY_DELAY_MS);
    fixture.detectChanges();
    const dialog: HTMLDialogElement = fixture.nativeElement.querySelector('dialog');
    dialog.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    fixture.detectChanges();
    expect(component.phase()).toBe('plea');
    expect(fixture.nativeElement.querySelector('img').src).toContain('/assets/feedback/pleading-cat.webp');
    const cancel = new Event('cancel', { cancelable: true });
    dialog.dispatchEvent(cancel);
    fixture.detectChanges();
    expect(cancel.defaultPrevented).toBeTrue();
    expect(component.phase()).toBe('closed');
    expect(dialog.open).toBeFalse();
  }));

  it('does not prompt completed users or when sync is not configured', fakeAsync(() => {
    render();
    surveys.getStatus.and.returnValue(of({ ...pending, hasCompleted: true, formUrl: null }));
    tick(SURVEY_DELAY_MS);
    expect(component.phase()).toBe('closed');
    user.set({ userId: 'user-two' });
    fixture.detectChanges();
    surveys.getStatus.and.returnValue(of({ ...pending, enabled: false, formUrl: null }));
    tick(SURVEY_DELAY_MS);
    expect(component.phase()).toBe('closed');
  }));

  it('waits for server completion after opening the form and checks again on return', fakeAsync(() => {
    render();
    tick(SURVEY_DELAY_MS);
    component.formOpened();
    expect(component.phase()).toBe('waiting');
    tick(10_000);
    expect(component.phase()).toBe('waiting');
    surveys.getStatus.and.returnValue(of({ ...pending, hasCompleted: true, formUrl: null }));
    window.dispatchEvent(new Event('focus'));
    expect(component.phase()).toBe('thanks');
    expect(component.formUrl()).toBeNull();
    tick(60_000);
    expect(surveys.getStatus).toHaveBeenCalledTimes(3);
  }));

  it('cancels an in-flight status request on logout and gives another account a fresh timer', fakeAsync(() => {
    render();
    const response = new Subject<FeedbackSurveyStatus>();
    surveys.getStatus.and.returnValue(response);
    tick(SURVEY_DELAY_MS);
    user.set(null);
    fixture.detectChanges();
    response.next(pending);
    expect(component.phase()).toBe('closed');
    user.set({ userId: 'user-two' });
    surveys.getStatus.and.returnValue(of(pending));
    fixture.detectChanges();
    tick(SURVEY_DELAY_MS - 1);
    expect(component.phase()).toBe('closed');
    tick(1);
    expect(component.phase()).toBe('invitation');
  }));

  it('does not prompt guests or users on auth screens', fakeAsync(() => {
    render();
    fixture.componentRef.setInput('enabled', false);
    fixture.detectChanges();
    tick(SURVEY_DELAY_MS);
    expect(surveys.getStatus).not.toHaveBeenCalled();
    user.set(null);
    fixture.componentRef.setInput('enabled', true);
    fixture.detectChanges();
    tick(SURVEY_DELAY_MS);
    expect(surveys.getStatus).not.toHaveBeenCalled();
  }));
});
