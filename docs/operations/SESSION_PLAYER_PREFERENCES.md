# Web session player preferences

The web player remembers volume and mute within the current login session. For
example, 20% volume is stored as `volume = 0.2`, with `muted = false`.

## Redis configuration

Configure the API with `UPSTASH_REDIS_REST_URL` and a read/write
`UPSTASH_REDIS_REST_TOKEN`. The existing `SystemMonitoring:RedisRestUrl` and
`SystemMonitoring:RedisRestToken` configuration keys are also supported. These
credentials must stay on the backend.

Preferences are fields on the hash `hutube:auth:session:<sessionId>`; the session
ID uses 32 hexadecimal characters without hyphens. Only `volume` and `muted` are
written. Existing authentication fields are preserved. The hash expires at the
current session's expiration time.

This branch still validates authentication sessions against PostgreSQL. Adding
these fields does not turn Redis into the authentication session store, and does
not require a database migration. If the hash does not exist, saving preferences
creates it with the two audio fields.

## Request flow

- `GET /api/v1/auth/session/player-preferences` reads the current web session's
  preferences, returning `{ "volume": 1, "muted": false }` when none exist.
- `PUT /api/v1/auth/session/player-preferences` accepts the same JSON shape.
  Volume must be between 0 and 1, inclusive. Both endpoints require the active
  web session's bearer token, derive user/session IDs from its claims, and disable
  response caching.
- The browser updates its in-memory copy immediately and saves after 400 ms
  without further slider changes. Saves run in order and survive navigation
  between watch pages. Video creation and metadata loading restore the saved
  audio level; native and picture-in-picture controls also update preferences.
- Automatic muting by the browser's autoplay fallback does not change the user's
  saved mute preference.
- Refreshing the access token copies preferences to the replacement session ID.
  It then removes only the audio fields from the old hash. A new login starts
  with default preferences; sessions on other devices have independent values.

When Redis is unconfigured or unavailable, the API uses an in-memory copy scoped
to the session. Redis failures are logged and do not interrupt playback. This
fallback is limited to that API instance and does not survive its restart; Redis
must be configured and reachable for persistent storage. Guests retain their
audio level in browser memory during navigation without writing a Redis session.
