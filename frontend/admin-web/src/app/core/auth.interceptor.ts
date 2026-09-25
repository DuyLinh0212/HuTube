import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, of, switchMap, throwError } from 'rxjs';
import { AuthService, safeReturnUrl } from './auth.service';
import { ADMIN_APP, RuntimeConfig } from './runtime-config';

export const authInterceptor: HttpInterceptorFn = (request, next) => {
  const config = inject(RuntimeConfig);
  if (!config.owns(request.url)) return next(request);
  const auth = inject(AuthService);
  const router = inject(Router);
  const token = auth.accessToken();
  const wasAuthenticated = !!auth.user();
  const sessionVersion = auth.sessionVersion;
  const isAuthEndpoint = /\/auth\/(login|google|refresh|register|verify-email|resend-verification|forgot-password|reset-password|logout)(?:[/?]|$)/.test(request.url);
  const withAuth = (accessToken: string | null) => request.clone({ withCredentials: true, setHeaders: {
    'X-HuTube-Client': 'web', ...(ADMIN_APP ? { 'X-HuTube-App': 'admin' } : {}), ...(accessToken ? { Authorization: 'Bearer ' + accessToken } : {})
  } });
  return next(withAuth(token)).pipe(catchError(error => {
    if (!(error instanceof HttpErrorResponse) || error.status !== 401 || isAuthEndpoint) return throwError(() => error);
    if (sessionVersion !== auth.sessionVersion) return throwError(() => error);
    const expire = (refreshError: unknown) => {
      if (sessionVersion !== auth.sessionVersion && auth.accessToken()) return throwError(() => refreshError);
      auth.clear();
      void router.navigate(['/login'], { queryParams: { reason: 'expired', returnUrl: safeReturnUrl(router.url) } });
      return throwError(() => refreshError);
    };
    if (!token) {
      // A route can start loading before the cookie-backed session has been
      // restored into memory. Share that restore flight, then replay the
      // request once instead of surfacing a misleading generic 401 error.
      return auth.restore().pipe(
        switchMap(restored => {
          const restoredToken = auth.accessToken();
          if (!restored || !restoredToken) return throwError(() => error);
          return next(withAuth(restoredToken));
        }),
        catchError(restoreError => wasAuthenticated || !!auth.user() || !!auth.accessToken()
          ? expire(restoreError) : throwError(() => restoreError))
      );
    }
    // A parallel request may already have rotated the token before this 401 arrived.
    const refresh = auth.accessToken() && auth.accessToken() !== token
      ? of({ accessToken: auth.accessToken()! }) : auth.refresh();
    return refresh.pipe(catchError(expire), switchMap(response => next(withAuth(response.accessToken)).pipe(
      catchError(retryError => retryError instanceof HttpErrorResponse && retryError.status === 401 ? expire(retryError) : throwError(() => retryError))
    )));
  }));
};
