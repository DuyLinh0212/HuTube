import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { map } from 'rxjs';
import { AuthService } from './auth.service';

export const superAdminGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  return auth.restore().pipe(map(allowed => !allowed
    ? router.createUrlTree(['/login'])
    : auth.user()?.role === 'super_admin' ? true : router.createUrlTree(['/forbidden'])));
};
