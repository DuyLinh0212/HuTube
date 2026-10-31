# API performance integration test

Run the opt-in xUnit API benchmark from the repository root:

```powershell
$env:HUTUBE_PERFORMANCE_API_BASE_URL = 'https://api.dalitu.app/api/v1'
dotnet test backend/tests/HuTube.IntegrationTests --filter FullyQualifiedName~ApiPerformanceIntegrationTests
```

The test sends GET requests to the explicitly configured API base URL. It measures four representative read endpoints, 100 requests per endpoint, and at most five simultaneous requests. Requests run in five-request waves spaced 5.5 seconds apart to stay under the public search rate limit. It records mean, nearest-rank P95, elapsed time, HTTP status errors, status counts, and `X-Data-Cache` counts. It has no hard latency threshold because no SLO has been agreed.

The cache comparison uses the video-detail endpoint and 100 unique query keys. It measures a miss for each key, waits six seconds (past the configured five-second L1 lifetime), and repeats the same 100 keys. The test requires the first phase to report misses and the second to report hits, which verifies that the API served the requested cache branch after L1 expired.

The test is skipped in ordinary CI unless `HUTUBE_PERFORMANCE_API_BASE_URL` is set. It performs GET-only calls, does not save response bodies or video IDs, and performs no writes. To verify Redis specifically, run it against an environment with the distributed Redis cache configured; the response header confirms a cache hit but does not identify the L2 provider.

The JSON report is written to `backend/tests/HuTube.IntegrationTests/TestResults/performance/` and is included with the backend test-results artifact when the test is enabled in CI.
