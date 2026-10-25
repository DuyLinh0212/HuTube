# Admin lazy-page recovery

A tab opened before a deployment can request a lazy-module hash that no longer exists on the current deployment. Previously that URL could fall through to index.html with HTTP 200/text/html, and navigating to the moderation queue failed.

- Vercel resolves real static files first, returns 404/no-store for missing assets, and serves SPA routes from index.html without caching the HTML.
- The Angular navigation error handler recognizes module-load failures and requests a fresh document at the intended internal URL, preserving its query and fragment.
- Direct links that already match the current path/query use `history.replaceState` followed by `location.reload`. Calling only `location.replace` with a fragment at that URL can perform a same-document navigation and retain the failed import cache.
- A session marker limits automatic recovery to one document reload within 60 seconds. Offline or storage-blocked browsers show the eagerly bundled retry screen; persistent failures do not loop. Other application errors retain the existing error handling.
- Recovery does not bypass authentication or permission guards. The manual return URL is independently constrained to the same origin.
- A tab already running the pre-fix JavaScript needs one manual refresh to load this handler.

Validation after the policy/moderation merge: 117 Admin Web tests, production build, three real Chromium scenarios (single failure, persistent failure, blocked storage with English/narrow/dark layout) and recovery across the 20 lazy-page routes below, with zero uncaught browser errors. The browser regression runs in CI after the existing Web/RBAC suites. Vercel configuration was checked against the official Vercel schema; deployed preview headers/404s must also be checked after publication.

The browser regression also discovers every page with a direct lazy import in `app.routes.ts` (20 routes, including account and forbidden). It independently serves HTML instead of each page's actual JavaScript module once, then requires recovery at the intended route with exactly one document reload. Sidebar links exercise router navigation; pages without a visible sidebar link exercise direct navigation, preserving query strings and fragments. Independent browser contexts prevent an earlier successful import from masking a missing module. Destination APIs outside the small entry-page fixture deliberately return 503, verifying that a business API outage does not get mistaken for a chunk error or trigger another reload.

The deployment controller also makes the tracked public RabbitMQ config readable by the broker after checkout under umask 0077, while keeping credential env files private. Its preparation regression asserts the public/private permissions on Linux and broker-before-migration ordering.
