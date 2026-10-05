import { HttpErrorResponse, HttpInterceptorFn, HttpResponse } from '@angular/common/http';
import { inject } from '@angular/core';
import { TimeoutError, catchError, tap, throwError, timeout } from 'rxjs';
import { RuntimeConfig } from '../runtime-config';
import { NetworkStatusService } from './network-status.service';

const RESPONSE_TIMEOUT_MS = 15_000;

export const networkInterceptor: HttpInterceptorFn = (request, next) => {
  const config = inject(RuntimeConfig);
  if (!config.owns(request.url)) return next(request);

  const networkStatus = inject(NetworkStatusService);
  const isFormData = typeof FormData !== 'undefined' && request.body instanceof FormData;
  const isLongTransfer = isFormData
    || request.reportProgress
    || request.responseType === 'blob'
    || request.responseType === 'arraybuffer';
  const response = next(request);

  return (isLongTransfer ? response : response.pipe(timeout({ each: RESPONSE_TIMEOUT_MS }))).pipe(
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
