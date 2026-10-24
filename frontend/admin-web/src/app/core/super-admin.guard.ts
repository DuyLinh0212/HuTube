import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { catchError, map, of } from 'rxjs';
import { AuthService } from './auth.service';
import { restoreFailureRedirect } from './auth.guard';

export const superAdminGuard: CanActivateFn = (_route, state) => {
  const auth = inject(AuthService);
  const router = inject(Router);
  return auth.restore().pipe(map(allowed => !allowed
    ? router.createUrlTree(['/login'])
    : auth.user()?.role === 'super_admin' ? true : router.createUrlTree(['/forbidden'])),
    catchError(error => of(restoreFailureRedirect(router, state.url, error))));
};
