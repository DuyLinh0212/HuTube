import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { map } from 'rxjs';
import { AuthService, safeReturnUrl } from './auth.service';

export const authGuard: CanActivateFn = (_route, state) => {
  const router = inject(Router);
  return inject(AuthService).restore().pipe(map(allowed => allowed || router.createUrlTree(['/login'], { queryParams: { returnUrl: safeReturnUrl(state.url) } })));
};
