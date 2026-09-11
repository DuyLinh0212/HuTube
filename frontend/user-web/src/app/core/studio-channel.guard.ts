import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { catchError, map, of } from 'rxjs';
import { ChannelService } from './channel.service';

export const studioChannelGuard: CanActivateFn = () => {
  const channels = inject(ChannelService); const router = inject(Router);
  return channels.getMyChannel().pipe(map(() => true), catchError(() => of(router.createUrlTree(['/studio/setup']))));
};
