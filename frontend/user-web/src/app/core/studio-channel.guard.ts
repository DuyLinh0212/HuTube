import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { catchError, forkJoin, map, of } from 'rxjs';
import { ChannelService } from './channel.service';

export const studioChannelGuard: CanActivateFn = () => {
  const channels = inject(ChannelService); const router = inject(Router);
  return forkJoin({
    channels: channels.getAccessibleChannels(),
    invitations: channels.getMyInvitations()
  }).pipe(
    map(({ channels: items, invitations }) => items.length > 0
      ? true
      : invitations.length > 0
        ? router.createUrlTree(['/studio/invitations'])
        : router.createUrlTree(['/studio/setup'])),
    catchError(() => of(router.createUrlTree(['/studio/setup'])))
  );
};
