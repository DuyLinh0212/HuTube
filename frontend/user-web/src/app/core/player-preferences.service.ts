import { HttpClient } from '@angular/common/http';
import { DestroyRef, Injectable, effect, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { EMPTY, Observable, Subject, catchError, concatMap, debounceTime, finalize, map, of, shareReplay, tap } from 'rxjs';
import { AuthService } from './auth.service';
import { RuntimeConfig } from './runtime-config';

export interface PlayerPreferences { volume: number; muted: boolean; }
const defaults = (): PlayerPreferences => ({ volume: 1, muted: false });

@Injectable({ providedIn: 'root' })
export class PlayerPreferencesService {
  private readonly http = inject(HttpClient);
  private readonly auth = inject(AuthService);
  private readonly config = inject(RuntimeConfig);
  private readonly destroyRef = inject(DestroyRef);
  private readonly state = signal<PlayerPreferences>(defaults());
  readonly preferences = this.state.asReadonly();
  private owner: string | null = null;
  private revision = 0;
  private loaded = false;
  private loadFlight?: Observable<PlayerPreferences>;
  private readonly changes = new Subject<{ owner: string; revision: number; value: PlayerPreferences }>();
  private get url() { return this.config.apiBaseUrl + '/auth/session/player-preferences'; }

  constructor() {
    effect(() => {
      this.auth.accessToken();
      this.syncOwner();
    });
    // Keep the latest slider value, and serialize writes so a slow older request
    // cannot overwrite a newer value. This service survives watch-page navigation.
    this.changes.pipe(
      debounceTime(400),
      concatMap(change => {
        this.syncOwner();
        return change.owner === this.owner && change.revision === this.revision
          ? this.http.put<PlayerPreferences>(this.url, change.value).pipe(catchError(() => EMPTY))
          : EMPTY;
      }),
      takeUntilDestroyed(this.destroyRef),
    ).subscribe();
  }

  private syncOwner() {
    const user = this.auth.user();
    // Access-token refresh rotates sid but keeps sessionVersion. The backend
    // transfers preferences to that new sid; a new login/logout resets this copy.
    const owner = user ? `${this.auth.sessionVersion}:${user.userId}` : null;
    if (owner === this.owner) return;
    this.owner = owner;
    this.revision++;
    this.loaded = false;
    this.loadFlight = undefined;
    this.state.set(defaults());
  }

  load(): Observable<PlayerPreferences> {
    this.syncOwner();
    if (!this.owner || this.loaded) return of(this.state());
    if (this.loadFlight) return this.loadFlight;
    const owner = this.owner;
    const revision = this.revision;
    const request = this.http.get<PlayerPreferences>(this.url).pipe(
      tap(value => {
        this.syncOwner();
        if (owner !== this.owner || revision !== this.revision) return;
        if (Number.isFinite(value.volume) && value.volume >= 0 && value.volume <= 1 && typeof value.muted === 'boolean') {
          this.state.set(value);
          this.loaded = true;
        }
      }),
      map(() => this.state()),
      catchError(() => of(this.state())),
      finalize(() => { if (this.loadFlight === request) this.loadFlight = undefined; }),
      shareReplay({ bufferSize: 1, refCount: false }),
    );
    this.loadFlight = request;
    return request;
  }

  update(volume: number, muted: boolean): void {
    if (!Number.isFinite(volume)) return;
    this.syncOwner();
    const value = { volume: Math.max(0, Math.min(1, volume)), muted };
    const current = this.state();
    if (current.volume === value.volume && current.muted === value.muted) return;
    this.state.set(value);
    this.loaded = true;
    this.revision++;
    if (this.owner) this.changes.next({ owner: this.owner, revision: this.revision, value });
  }
}
