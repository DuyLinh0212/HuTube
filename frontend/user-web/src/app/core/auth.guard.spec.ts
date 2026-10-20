import { TestBed } from '@angular/core/testing';
import { provideRouter, Router, UrlTree } from '@angular/router';
import { firstValueFrom, Observable, of, throwError } from 'rxjs';
import { HttpErrorResponse } from '@angular/common/http';
import { authGuard } from './auth.guard';
import { AuthService } from './auth.service';
import { ActivatedRouteSnapshot, RouterStateSnapshot } from '@angular/router';

describe('Protected route guard', () => {
  const auth = { restore: () => of(false) };
  beforeEach(() => TestBed.configureTestingModule({providers:[provideRouter([]), {provide:AuthService,useValue:auth}]}));
  async function guard(url: string) {
    return firstValueFrom(TestBed.runInInjectionContext(() => authGuard({} as ActivatedRouteSnapshot, {url} as RouterStateSnapshot)) as Observable<boolean | UrlTree>);
  }
  it('preserves the requested internal route when no session can be restored', async () => {
    spyOn(auth,'restore').and.returnValue(of(false));
    expect(TestBed.inject(Router).serializeUrl(await guard('/account?tab=sessions') as UrlTree)).toBe('/login?returnUrl=%2Faccount%3Ftab%3Dsessions');
  });
  it('allows a validated restored session', async () => { spyOn(auth,'restore').and.returnValue(of(true)); expect(await guard('/account')).toBeTrue(); });
  it('renders a retryable login destination when restoration is rate limited', async () => {
    spyOn(auth, 'restore').and.returnValue(throwError(() => new HttpErrorResponse({ status: 429 })));
    const result = await guard('/studio/upload') as UrlTree;
    expect(result.queryParams).toEqual({ reason: 'rate-limited', returnUrl: '/studio/upload' });
  });
});
