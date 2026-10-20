import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { HttpErrorResponse } from '@angular/common/http';
import { catchError, map, of } from 'rxjs';
import { AuthService, safeReturnUrl } from './auth.service';

export function restoreFailureRedirect(router: Router, url: string, error: unknown) {
  return router.createUrlTree(['/login'], { queryParams: {
    reason: error instanceof HttpErrorResponse && error.status === 429 ? 'rate-limited' : 'unavailable',
    returnUrl: safeReturnUrl(url),
  } });
}

export const authGuard: CanActivateFn = (_route, state) => {
  const router = inject(Router);
  return inject(AuthService).restore().pipe(
    map(allowed => allowed || router.createUrlTree(['/login'], { queryParams: { returnUrl: safeReturnUrl(state.url) } })),
    catchError(error => of(restoreFailureRedirect(router, state.url, error))),
  );
};
