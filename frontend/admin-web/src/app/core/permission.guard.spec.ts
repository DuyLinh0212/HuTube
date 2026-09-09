import { TestBed } from '@angular/core/testing';
import { provideRouter, Router, UrlTree } from '@angular/router';
import { firstValueFrom, Observable, of } from 'rxjs';
import { permissionGuard } from './permission.guard';
import { AuthService } from './auth.service';
import { ActivatedRouteSnapshot, RouterStateSnapshot } from '@angular/router';

describe('Permission route guard', () => {
  const auth = {
    restore: () => of(true),
    hasPermission: (_p: string) => true
  };

  beforeEach(() => TestBed.configureTestingModule({
    providers: [provideRouter([]), { provide: AuthService, useValue: auth }]
  }));

  async function checkPermission(permission?: string) {
    const route = { data: permission ? { permission } : {} } as ActivatedRouteSnapshot;
    return firstValueFrom(TestBed.runInInjectionContext(() => permissionGuard(route, {} as RouterStateSnapshot)) as Observable<boolean | UrlTree>);
  }

  it('redirects to login when unauthenticated', async () => {
    spyOn(auth, 'restore').and.returnValue(of(false));
    const result = await checkPermission('user.view');
    expect(TestBed.inject(Router).serializeUrl(result as UrlTree)).toBe('/login');
  });

  it('redirects to /forbidden when lacking required permission', async () => {
    spyOn(auth, 'restore').and.returnValue(of(true));
    spyOn(auth, 'hasPermission').and.returnValue(false);
    const result = await checkPermission('user.view');
    expect(TestBed.inject(Router).serializeUrl(result as UrlTree)).toBe('/forbidden');
  });

  it('allows access when user possesses required permission', async () => {
    spyOn(auth, 'restore').and.returnValue(of(true));
    spyOn(auth, 'hasPermission').and.returnValue(true);
    const result = await checkPermission('user.view');
    expect(result).toBeTrue();
  });
});
