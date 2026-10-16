import { HttpErrorResponse, HttpInterceptorFn, HttpResponse } from '@angular/common/http';
import { inject } from '@angular/core';
import { TimeoutError, catchError, tap, throwError, timeout } from 'rxjs';
import { RuntimeConfig } from '../runtime-config';
import { NetworkStatusService } from './network-status.service';

const RESPONSE_TIMEOUT_MS = 15_000;
// These API routes call Recommendation Service and may need to wait for its
// cold-start retry window (currently 90 seconds) to finish.
const RECOMMENDATION_RESPONSE_TIMEOUT_MS = 105_000;

export const networkInterceptor: HttpInterceptorFn = (request, next) => {
  const config = inject(RuntimeConfig);
  if (!config.owns(request.url)) return next(request);

  const networkStatus = inject(NetworkStatusService);
  const isFormData = typeof FormData !== 'undefined' && request.body instanceof FormData;
  const isLongTransfer = isFormData
    || request.reportProgress
    || request.responseType === 'blob'
    || request.responseType === 'arraybuffer';
  const callsRecommendationService = request.method === 'GET' && (
    /\/api\/v1\/feed\/(?:home|recommended)\/?(?:[?#]|$)/.test(request.url)
    || /\/api\/v1\/admin\/users\/[^/?#]+\/statistics\/?(?:[?#]|$)/.test(request.url)
    || /\/api\/v1\/admin\/recommendations\/models\/?(?:[?#]|$)/.test(request.url)
  );
  const responseTimeoutMs = callsRecommendationService
    ? RECOMMENDATION_RESPONSE_TIMEOUT_MS
    : RESPONSE_TIMEOUT_MS;
  const response = next(request);

  return (isLongTransfer ? response : response.pipe(timeout({ each: responseTimeoutMs }))).pipe(
    tap(event => {
      if (event instanceof HttpResponse) networkStatus.markAvailable();
    }),
    catchError((error: unknown) => {
      if (error instanceof TimeoutError || (error instanceof HttpErrorResponse && error.status === 0)) {
        void networkStatus.checkConnection();
      } else if (error instanceof HttpErrorResponse && error.status > 0) {
        networkStatus.markAvailable();
      }
      return throwError(() => error);
    }),
  );
};
