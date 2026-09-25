import { inject } from '@angular/core';
import { ActivatedRouteSnapshot, CanActivateFn, Router } from '@angular/router';
import { map } from 'rxjs';
import { AuthService } from './auth.service';

export const permissionGuard: CanActivateFn = (route: ActivatedRouteSnapshot) => {
  const router = inject(Router);
  const auth = inject(AuthService);
  const permission = route.data?.['permission'] as string | undefined;
  const permissionsAny = route.data?.['permissionsAny'] as readonly string[] | undefined;

  return auth.restore().pipe(
    map(allowed => {
      if (!allowed) return router.createUrlTree(['/login']);
      const granted = permission ? auth.hasPermission(permission)
        : !!permissionsAny?.length && permissionsAny.some(candidate => auth.hasPermission(candidate));
      if ((permission || permissionsAny?.length) && !granted) {
        return router.createUrlTree(['/forbidden']);
      }
      return true;
    })
  );
};
