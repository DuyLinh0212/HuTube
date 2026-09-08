import { inject } from '@angular/core';
import { ActivatedRouteSnapshot, CanActivateFn, Router } from '@angular/router';
import { map } from 'rxjs';
import { AuthService } from './auth.service';

export const permissionGuard: CanActivateFn = (route: ActivatedRouteSnapshot) => {
  const router = inject(Router);
  const auth = inject(AuthService);
  const permission = route.data?.['permission'] as string | undefined;

  return auth.restore().pipe(
    map(allowed => {
      if (!allowed) return router.createUrlTree(['/login']);
      if (permission && !auth.hasPermission(permission)) {
        return router.createUrlTree(['/forbidden']);
      }
      return true;
    })
  );
};
