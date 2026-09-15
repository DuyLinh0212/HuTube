import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { catchError, map, of } from 'rxjs';
import { ChannelService } from './channel.service';

/**
 * Keeps direct Studio URLs consistent with the permissions used by the
 * sidebar. The API remains the source of truth; this guard only prevents a
 * user from entering a screen that cannot be used by the selected channel.
 */
export const studioPermissionGuard: CanActivateFn = route => {
  const channels = inject(ChannelService);
  const router = inject(Router);
  const required = route.data?.['studioPermissions'];
  const permissions = Array.isArray(required)
    ? required.filter((value): value is string => typeof value === 'string')
    : typeof required === 'string' ? [required] : [];

  return channels.getAccessibleChannels().pipe(
    map(items => {
      const requestedId = route.queryParamMap.get('channelId') ?? readSelectedChannelId();
      const selected = items.find(item => item.channelId === requestedId)
        ?? items.find(item => item.isOwner)
        ?? items[0];

      if (selected && (permissions.length === 0 || permissions.some(permission => selected.permissions.includes(permission)))) {
        return true;
      }

      return router.createUrlTree(['/studio/overview'], {
        queryParams: selected ? { channelId: selected.channelId } : undefined
      });
    }),
    catchError(() => of(router.createUrlTree(['/studio/setup'])))
  );
};

function readSelectedChannelId(): string | null {
  try {
    return localStorage.getItem('hutube.studio.channel-id');
  } catch {
    return null;
  }
}
