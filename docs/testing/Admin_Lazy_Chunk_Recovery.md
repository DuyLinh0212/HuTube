# Admin lazy-page recovery

A tab opened before a deployment can request a lazy-module hash that no longer exists on the current deployment. Previously that URL could fall through to index.html with HTTP 200/text/html, and navigating to the moderation queue failed.

- Vercel resolves real static files first, returns 404/no-store for missing assets, and serves SPA routes from index.html without caching the HTML.
- The Angular navigation error handler recognizes module-load failures and requests a fresh document at the intended internal URL, preserving its query and fragment.
- A session marker limits automatic recovery to one document reload within 60 seconds. Offline or storage-blocked browsers show the eagerly bundled retry screen; persistent failures do not loop. Other application errors retain the existing error handling.
- Recovery does not bypass authentication or permission guards. The manual return URL is independently constrained to the same origin.
- A tab already running the pre-fix JavaScript needs one manual refresh to load this handler.

Validation: 88 Admin Web tests, production build, three real Chromium scenarios (single failure, persistent failure, blocked storage with English/narrow/dark layout), zero uncaught browser errors. The browser regression now runs in CI after the existing Web/RBAC suites. Vercel configuration was checked against the official Vercel schema; deployed preview headers/404s must also be checked after publication.

The deployment controller also makes the tracked public RabbitMQ config readable by the broker after checkout under umask 0077, while keeping credential env files private. Its preparation regression asserts the public/private permissions on Linux and broker-before-migration ordering.
