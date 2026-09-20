const { chromium } = require('playwright');
const assert = require('node:assert/strict');

const origin = process.env.USER_WEB_URL || 'http://localhost:4200';
const planId = '00000000-0000-0000-0000-000000000100';
const categoryId = '44444444-4444-4444-4444-444444444444';
const videoId = '33333333-3333-3333-3333-333333333333';

function json(route, body, status = 200) {
  return route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });
}

(async () => {
  const browser = await chromium.launch({
    headless: process.env.HEADED !== '1',
    ...(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {})
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 960 } });
  page.setDefaultTimeout(30000);
  const video = {
    videoId,
    channelId: '11111111-1111-1111-1111-111111111111',
    channelName: 'Kênh công khai',
    channelHandle: 'kenh-cong-khai',
    categoryId,
    title: 'Video công khai Sprint 5',
    description: 'Video dùng để kiểm tra luồng Guest.',
    videoUrl: 'https://example.test/source.mp4',
    thumbnailUrl: null,
    duration: 120,
    fileSize: 1024,
    visibility: 'public',
    status: 'ready',
    moderationStatus: 'approved',
    languageCode: 'vi',
    ageRestricted: false,
    publishedAt: new Date().toISOString(),
    createdAt: new Date().toISOString(),
    tags: ['sprint5'],
    chapters: [],
    stats: { views: 12, likes: 2, dislikes: 0, comments: 0, averageRating: null, ratingCount: 0, shares: 0 },
    viewerState: null
  };
  const plans = [{
    planId,
    code: 'free',
    name: 'Free',
    description: 'Gói miễn phí cho người mới bắt đầu.',
    price: 0,
    durationDays: 3650,
    storageLimit: 10737418240,
    maxUploadSize: 1073741824,
    maxVideoDuration: 43200,
    maxVideoQuality: '720p',
    maxDownloadQuality: '720p',
    maxMembers: 1,
    status: 'active',
    displayOrder: 1,
    features: { download: false, background_play: false, pip: false }
  }];
  let latestExploreRequest;
  await page.route('**/api/v1/**', async route => {
    const requestUrl = new URL(route.request().url());
    const requestPath = requestUrl.pathname;
    if (requestPath.endsWith('/system/config')) return json(route, { googleClientId: '' });
    // A 401 refresh response keeps this browser context genuinely Guest.
    if (requestPath.endsWith('/auth/refresh')) return json(route, { code: 'UNAUTHORIZED', detail: 'Guest' }, 401);
    if (requestPath.endsWith('/auth/me')) return json(route, { code: 'UNAUTHORIZED', detail: 'Guest' }, 401);
    if (requestPath === '/api/v1/plans') return json(route, plans);
    if (requestPath === `/api/v1/plans/${planId}`) return json(route, plans[0]);
    if (requestPath === `/api/v1/plans/${planId}/share`) {
      return json(route, { planId, code: 'free', name: 'Free', description: plans[0].description, shareUrl: `${origin}/plans/${planId}`, status: 'active', features: plans[0].features });
    }
    if (requestPath.endsWith('/categories')) return json(route, [{ categoryId, name: 'Giáo dục', slug: 'giao-duc', description: null }]);
    if (requestPath.endsWith('/videos/search')) {
      latestExploreRequest = requestUrl;
      return json(route, { items: [video], page: 1, pageSize: 20, total: 1 });
    }
    if (requestPath.endsWith('/feed/home')) return json(route, { items: [video], page: 1, pageSize: 20, total: 1 });
    if (requestPath.endsWith('/channels/me') || requestPath.endsWith('/violation-types')) return json(route, {}, 401);
    if (requestPath.endsWith(`/videos/${videoId}/playback`)) {
      return json(route, { videoId, title: video.title, visibility: 'public', duration: 120, renditions: [{ quality: '720p', width: 1280, height: 720, fileSize: 1024, url: video.videoUrl }], resumeAtSeconds: 0, progress: 0 });
    }
    if (requestPath.endsWith(`/videos/${videoId}/comments`)) return json(route, { items: [], page: 1, pageSize: 20, total: 0 });
    if (requestPath.endsWith(`/videos/${videoId}`)) return json(route, video);
    if (requestPath.endsWith('/channels/kenh-cong-khai')) return json(route, { channelId: video.channelId, ownerUserId: '22222222-2222-2222-2222-222222222222', name: video.channelName, handle: video.channelHandle, description: 'Mô tả', avatarUrl: null, bannerUrl: null, contactEmail: null, watermarkUrl: null, settings: '{}', status: 'active', subscriberCount: 3, videoCount: 1, isOwner: false, myRole: null, permissions: [], createdAt: new Date().toISOString() });
    return json(route, {});
  });

  await page.goto(`${origin}/home`);
  await page.locator('main.feed .card').filter({ hasText: video.title }).waitFor();
  assert.equal(await page.getByText(video.title, { exact: true }).count(), 1, 'Guest Home should show public fallback video');

  await page.goto(`${origin}/explore`);
  await page.locator('main.feed .filter-bar').waitFor();
  await page.locator('main.feed .card').filter({ hasText: video.title }).waitFor();
  await page.locator('.filter-bar select').nth(1).selectOption(categoryId);
  await page.getByText(video.title, { exact: true }).waitFor();
  assert.equal(latestExploreRequest.searchParams.get('categoryId'), categoryId, 'Explore category filter must reach API');

  await page.goto(`${origin}/plans/${planId}`);
  await page.getByRole('heading', { name: 'Free' }).waitFor();
  assert.equal(await page.getByText('12 giờ', { exact: true }).count(), 1, 'Plan duration must be rendered in seconds-to-minutes correctly');
  assert.equal(await page.getByText('✕ Không hỗ trợ', { exact: true }).count(), 3, 'Free entitlements must not be hard-coded as enabled');
  const planShareInput = page.locator('input[aria-label="Liên kết chia sẻ gói"]');
  assert.equal(await planShareInput.count(), 1, 'Plan share input must be rendered');
  assert.equal(await planShareInput.inputValue(), `${origin}/plans/${planId}`, 'Plan share URL must be public and token-free');

  await page.goto(`${origin}/watch/${videoId}`);
  await page.getByRole('heading', { name: video.title }).waitFor();
  assert.equal(await page.locator('[aria-label="Thích video"]').count(), 0, 'Guest must not receive the like control');
  assert.equal(await page.getByText('Đăng nhập để tương tác', { exact: true }).count() >= 1, true, 'Guest must get a clear login affordance');
  assert.equal(await page.getByText('Đăng nhập để tải xuống', { exact: true }).count(), 1, 'Guest must not receive download access');
  await page.getByRole('button', { name: 'Chia sẻ' }).click();
  const shareLinkInput = page.locator('.share-link-field input[aria-label="Liên kết video"]');
  await shareLinkInput.waitFor({ state: 'visible' });
  assert.equal(await shareLinkInput.count(), 1, 'Guest may open the public share flow');

  await browser.close();
  console.log('Sprint 5 Tú browser checks passed.');
})().catch(error => {
  console.error(error);
  process.exit(1);
});
