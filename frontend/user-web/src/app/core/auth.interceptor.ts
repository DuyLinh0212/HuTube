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
  const sessionVersion = auth.sessionVersion;
  const withAuth = (accessToken: string | null) => request.clone({ withCredentials: true, setHeaders: {
    'X-HuTube-Client': 'web', ...(ADMIN_APP ? { 'X-HuTube-App': 'admin' } : {}), ...(accessToken ? { Authorization: 'Bearer ' + accessToken } : {})
  } });
  return next(withAuth(token)).pipe(catchError(error => {
    if (!(error instanceof HttpErrorResponse) || error.status !== 401 || !token) return throwError(() => error);
    if (sessionVersion !== auth.sessionVersion) return throwError(() => error);
    const expire = (refreshError: unknown) => {
      if (sessionVersion !== auth.sessionVersion && auth.accessToken()) return throwError(() => refreshError);
      auth.clear();
      void router.navigate(['/login'], { queryParams: { reason: 'expired', returnUrl: safeReturnUrl(router.url) } });
      return throwError(() => refreshError);
    };
    // A parallel request may already have rotated the token before this 401 arrived.
    const refresh = auth.accessToken() && auth.accessToken() !== token
      ? of({ accessToken: auth.accessToken()! }) : auth.refresh();
    return refresh.pipe(catchError(expire), switchMap(response => next(withAuth(response.accessToken)).pipe(
      catchError(retryError => retryError instanceof HttpErrorResponse && retryError.status === 401 ? expire(retryError) : throwError(() => retryError))
    )));
  }));
};
