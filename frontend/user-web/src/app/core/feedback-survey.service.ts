import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { RuntimeConfig } from './runtime-config';

export interface FeedbackSurveyStatus {
  enabled: boolean;
  hasCompleted: boolean;
  completedAt: string | null;
  formUrl: string | null;
}

@Injectable({ providedIn: 'root' })
export class FeedbackSurveyService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);

  getStatus(): Observable<FeedbackSurveyStatus> {
    return this.http.get<FeedbackSurveyStatus>(this.config.apiBaseUrl + '/feedback-survey');
  }
}
