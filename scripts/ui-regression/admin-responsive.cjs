const { chromium } = require(process.env.PLAYWRIGHT_MODULE_PATH || '../../recommendation-service/.venv/Lib/site-packages/playwright/driver/package');
const fs = require('node:fs');
const path = require('node:path');
const base = process.env.ADMIN_TEST_URL || 'http://127.0.0.1:4211';
const output = path.resolve(__dirname, '../../.work/admin-responsive');
fs.mkdirSync(output, { recursive: true });
const uid = '11111111-1111-4111-8111-111111111111';
const cid = '22222222-2222-4222-8222-222222222222';
const vid = '33333333-3333-4333-8333-333333333333';
const now = '2026-10-13T00:00:00Z';
const longName = 'Người quản trị kiểm tra nội dung và hệ thống HuTube';
const user = { userId: uid, username: 'responsive', email: 'responsive@example.test', displayName: longName,
  emailVerified: true, isAdmin: true, role: 'super_admin', permissions: [] };
const adminUser = { ...user, avatarUrl: null, roleCode: 'super_admin', roleName: 'Quản trị viên', planCode: 'pro', planName: 'Creator Pro',
  channelCount: 1, warningCount: 0, lastLoginAt: now, createdAt: now, status: 'active', lockedUntil: null,
  auditHistory: [], channels: [], permissions: [] };
const channel = { channelId: cid, ownerUserId: uid, name: longName, handle: 'responsive-channel', description: 'Thông tin kênh thử nghiệm',
  avatarUrl: null, status: 'active', createdAt: now, subscriberCount: 10, videoCount: 1, ownerName: longName, ownerEmail: user.email, activeStrikeCount: 0 };
const video = { videoId: vid, channelId: cid, channelName: longName, channelHandle: 'responsive-channel', title: longName,
  description: 'Thông tin video', thumbnailUrl: null, duration: 120, visibility: 'public', status: 'published', moderationStatus: 'approved',
  views: 8, ageRestricted: false, createdAt: now, publishedAt: now, uploadedByUserId: uid, videoUrl: '', fileSize: 20, reportCount: 0, categoryName: 'Giáo dục' };
const plan = { planId: cid, code: 'pro', name: 'Creator Pro', description: 'Gói đăng ký thử nghiệm', price: 99000, durationDays: 30,
  storageLimit: 100000000, maxUploadSize: 10000000, maxVideoDuration: 720, maxVideoQuality: '720p', maxDownloadQuality: '720p',
  maxMembers: 1, status: 'active', features: {}, displayOrder: 1, isDefaultForNewUsers: false };
const roles = [{ roleId: uid, code: 'reviewer', name: 'Nhân viên kiểm duyệt', description: 'Vai trò thử nghiệm',
  permissions: ['channel.view'], status: 'active', isSystemRole: false, assignedUserCount: 1 }];
const topics = [{ categoryId: cid, name: 'Giáo dục', slug: 'giao-duc', description: '', status: 'active', videoCount: 1, createdAt: now, updatedAt: now }];
const policy = { policyId: cid, code: 'TEST_POLICY', name: 'Chính sách nội dung thử nghiệm', group: 'guidelines', content: 'Nội dung chính sách',
  severity: 'medium', version: '1', status: 'active', createdAt: now, updatedAt: now, effectiveAt: now };
const paged = (items, extra = {}) => ({ items, total: items.length, page: 1, pageSize: 20, hasMore: false, ...extra });
const report = { generatedAt: now, days: 30, revenue: { total: 99000, inPeriod: 99000, transactionsTotal: 1, transactionsInPeriod: 1 },
  daily: [{ date: now, newUsers: 2, newVideos: 1, views: 8, comments: 1, revenue: 99000 }], videoStatuses: [], reportStatuses: [], paymentMethods: [] };
for (const name of ['users','verifiedUsers','videos','publishedVideos','channels','views','comments','likes','subscribers','reports','pendingReports','pendingReviews','pendingAppeals','activeSessions','shares'])
  report[name] = { total: 5, inPeriod: 2 };
const matrix = { state: 'ready', modelVersion: 'responsive-test-model', csvKey: 'collaborative_cf/' + 'sample_'.repeat(16) + '.csv',
  csvSha256: 'a'.repeat(64), updatedAt: now, active: { pairs: 4, users: 2, videos: 3 }, current: { pairs: 5, users: 2, videos: 3 },
  added: 1, changed: 0, removed: 0, changeRate: .25, modelAlgorithm: 'batch_incremental_partial_topk' };

function fixture(p) {
  if (p === '/auth/refresh') return { accessToken: 'e30.' + Buffer.from(JSON.stringify({ sub: uid, sid: uid, exp: 2000000000 })).toString('base64url') + '.test', expiresAt: '2030-01-01T00:00:00Z', user };
  if (['/auth/me','/admin/me'].includes(p)) return user;
  if (p === '/auth/sessions') return { items: [{ sessionId: uid, deviceName: longName, platform: 'admin', issuedAt: now, lastActiveAt: now, expiresAt: now, isCurrent: true }] };
  if (p === '/auth/login-history') return paged([]);
  if (p === '/admin/users') return paged([adminUser], { stats: { total: 1, active: 1, blocked: 0, creatorPro: 1 } });
  if (p === '/admin/users/' + uid) return adminUser;
  if (p === '/admin/users/' + uid + '/statistics') return { userId: uid, from: now, to: now,
    summary: { totalWatchSeconds: 120, videosWatched: 1, completionRate: .5, likes: 1, dislikes: 0, comments: 0, averageRating: 4, ratings: 1 },
    categories: [], recommendations: [], recommendationsAvailable: true, recommendationModelVersion: 'test-model' };
  if (p === '/admin/channels') return paged([channel]);
  if (p === '/admin/channels/' + cid) return { channel, videos: [], history: [], description: channel.description };
  if (p === '/admin/videos') return paged([video]);
  if (p === '/admin/videos/' + vid) return { video, description: video.description, categoryId: cid, categoryName: 'Giáo dục', videoUrl: '', fileSize: 20, duration: 120, history: [], reports: [] };
  if (p === '/admin/roles') return roles;
  if (p === '/admin/permissions') return [{ permissionId: cid, code: 'channel.view', name: 'Xem danh sách kênh', description: '', status: 'active' }];
  if (['/admin/plans','/plans'].includes(p)) return [plan];
  if (['/admin/policies','/policies'].includes(p)) return [policy];
  if (['/admin/topics','/categories','/admin/recommendations/categories'].includes(p)) return topics;
  if (['/admin/tags','/tags'].includes(p)) return [];
  if (p === '/admin/payments') return paged([], { stats: { revenueInRange: 99000, revenueThisMonth: 99000, successfulTransactions: 1, refundTransactions: 0, pendingTransactions: 0, failedTransactions: 0 }, daily: [], methods: [], availableMethods: ['sepay'] });
  if (p === '/admin/subscriptions') return paged([], { stats: { totalSubscriptions: 1, activeSubscriptions: 1, expiringSubscriptions: 0, expiredSubscriptions: 0, autoRenewSubscriptions: 0, pendingPayments: 0, paidRevenueThisMonth: 99000, paidTransactionsThisMonth: 1, failedPayments: 0, newSubscriptionsThisMonth: 1 } });
  if (p === '/admin/operations/system') return { sampledAt: now, activeAlertCount: 1, criticalAlertCount: 0, signals: [{ key: 'test', category: 'runtime', severity: 'warning', title: longName, description: longName, currentValue: 1, unit: 'lần', threshold: 1, actionUrl: '/users', isTriggered: true }], runtimeSettings: [] };
  if (p === '/admin/operations/reports') return report;
  if (p === '/admin/operations/audit-logs') return paged([], { eventsLast24Hours: 1, activeAdministratorsLast24Hours: 1, loginsLast24Hours: 1, actions: [], runtimeSettings: [] });
  if (p === '/admin/recommendations/status') return matrix;
  if (p === '/admin/recommendations/users') return [{ ...user, isBot: true }];
  if (p === '/admin/recommendations/videos') return paged([video]);
  if (p === '/admin/recommendations/matrix-preview') return { columns: ['user_id','video_id','score'], rows: [[uid,vid,'.5']], total: 1 };
  if (p === '/admin/reports/cases') return paged([]);
  if (p === '/admin/strikes/policy') return { enabled: true, warningThreshold: 1, suspendThreshold: 3, banThreshold: 5, expiryDays: 90, suspensionDays: 7, strikeExpiryDays: 90, thresholds: [], rules: [] };
  return [];
}

async function mock(route) {
  const url = new URL(route.request().url());
  if (url.pathname.endsWith('/config.json')) return route.fulfill({ json: { API_BASE_URL: base + '/api/v1', USER_WEB_BASE_URL: base } });
  if (url.pathname.startsWith('/api/v1/')) return route.fulfill({ json: fixture(url.pathname.slice(7)) });
  if (url.origin !== base) return route.abort();
  return route.continue();
}

function measure() {
  const stage = document.querySelector('.shell-stage');
  const overflow = [];
  for (const el of document.querySelectorAll('.content-frame *')) {
    const r = el.getBoundingClientRect(), style = getComputedStyle(el);
    if (!r.width || !r.height || style.visibility === 'hidden' || el.closest('svg')) continue;
    let scrollable = false, hidden = false;
    for (let parent = el.parentElement; parent && parent !== stage; parent = parent.parentElement) {
      if (getComputedStyle(parent).clip !== 'auto') { hidden = true; break; }
      if (['auto','scroll'].includes(getComputedStyle(parent).overflowX)) { scrollable = true; break; }
    }
    if (!scrollable && !hidden && (r.right > innerWidth + 2 || r.left < -2)) overflow.push(el.tagName + '.' + el.className);
  }
  return { width: innerWidth, documentWidth: document.documentElement.scrollWidth,
    stageWidth: stage?.clientWidth, stageScrollWidth: stage?.scrollWidth, overflow: [...new Set(overflow)].slice(0, 12) };
}

let activeBrowser;
async function run() {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  activeBrowser = browser;
  const context = await browser.newContext({ reducedMotion: 'reduce' });
  await context.route('**/*', mock);
  const page = await context.newPage();
  page.setDefaultTimeout(8000);
  const errors = [], results = [];
  page.on('pageerror', e => errors.push(e.message));
  const routes = ['users','channels','videos','roles','plans','subscriptions','payments','system/notifications','system/reports','system/logs',
    'moderation/videos','moderation/reports','moderation/appeals','moderation/strikes','topics','cf-seeder','recommendations','policies','account'];
  const viewports = process.env.ADMIN_TEST_COMPACT ? [[320,740],[390,844],[844,390]] : [[320,740],[390,844],[768,1024],[1024,768],[1440,900],[1920,1080],[844,390]];
  for (const [width, height] of viewports) {
    await page.setViewportSize({ width, height });
    for (const route of routes) {
      await page.goto(base + '/' + route);
      await page.waitForLoadState('networkidle');
      await page.locator('.content-frame > router-outlet + *').waitFor({ state: 'visible' });
      results.push({ route, height, ...await page.evaluate(measure) });
      if (route === 'recommendations') {
        await page.locator('.score-config select').selectOption('weighted');
        await page.locator('.score-weight').first().waitFor({ state: 'visible' });
        results.push({ route: route + '/weighted', height, ...await page.evaluate(measure) });
        await page.locator('#recommendations-simulation-tab').click();
        await page.waitForFunction(() => document.querySelector('#recommendations-simulation-tab')?.getAttribute('aria-selected') === 'true');
        results.push({ route: route + '/simulation', height, ...await page.evaluate(measure) });
        for (const [index, name] of [[1,'cluster'],[2,'comments']]) {
          await page.locator('.scenario-tabs button').nth(index).click();
          await page.waitForFunction(i => document.querySelectorAll('.scenario-tabs button')[i]?.getAttribute('aria-pressed') === 'true', index);
          results.push({ route: route + '/' + name, height, ...await page.evaluate(measure) });
        }
      }
      if ([390,1440].includes(width) && ['users','roles','recommendations'].includes(route))
        await page.screenshot({ path: path.join(output, route + '-' + width + '.png') });
    }
    console.log('Checked ' + width + 'x' + height);
  }
  await page.setViewportSize({ width: 390, height: 844 });
  fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify({ results, errors }, null, 2));
  await page.goto(base + '/users');
  await page.waitForLoadState('networkidle');
  await page.locator('.user-row').first().waitFor({ state: 'visible' });
  await page.locator('.menu-button').click();
  if (!await page.locator('.side-nav').evaluate(el => el.classList.contains('is-open'))) throw Error('Mobile menu failed to open');
  await page.waitForFunction(() => document.activeElement?.classList.contains('nav-close'));
  await page.keyboard.press('Shift+Tab');
  if (!await page.locator('.side-nav a[href], .side-nav button:not([disabled])').last().evaluate(el => el === document.activeElement)) throw Error('Drawer focus escaped');
  await page.keyboard.press('Escape');
  await page.waitForFunction(() => !document.querySelector('.side-nav')?.classList.contains('is-open'));
  await page.locator('.menu-button').click();
  await page.locator('.side-nav a[href="/roles"]').click();
  await page.waitForFunction(() => !document.querySelector('.side-nav')?.classList.contains('is-open'));
  for (const [width, height] of [[320,740],[844,390]]) {
    await page.setViewportSize({ width, height });
    for (const [route, trigger, dialog] of [
      ['roles','.heading-actions .primary-action','.role-dialog'],
      ['plans','.heading-actions .primary-action','.editor-dialog'],
      ['topics','.heading-actions .btn-primary','.modal-dialog'],
      ['videos','.video-title','.modal-dialog'],
      ['users','.user-row','.statistics-modal'],
    ]) {
      await page.goto(base + '/' + route); await page.waitForLoadState('networkidle');
      await page.locator(trigger).first().click();
      if (route === 'users') await page.locator('.statistics-action').click();
      await page.locator(dialog).waitFor({ state: 'visible' });
      if (route === 'plans' && width === 320) {
        const formHeight = await page.locator('.editor-scroll').evaluate(el => el.getBoundingClientRect().height);
        if (formHeight < 100) throw Error('Plan form collapsed behind its preview');
      }
      const bounds = await page.locator(dialog).evaluate(el => {
        const r = el.getBoundingClientRect();
        return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: innerWidth, height: innerHeight,
          scrollable: el.scrollHeight <= el.clientHeight + 2 || getComputedStyle(el).overflowY === 'auto' || !!el.querySelector('.editor-scroll,.modal-body,.statistics-body') };
      });
      if (bounds.left < -2 || bounds.right > width + 2 || bounds.top < -2 || bounds.bottom > height + 2 || !bounds.scrollable)
        throw Error('Dialog does not fit: ' + route + ' ' + JSON.stringify(bounds));
      await page.screenshot({ path: path.join(output, route + '-dialog-' + width + '.png') });
      console.log('Dialog fits: ' + route + ' ' + width + 'x' + height);
    }
  }
  await page.setViewportSize({ width: 390, height: 844 });
  for (const route of ['login','forgot-password','reset-password','verify-email','forbidden']) {
    await page.goto(base + '/' + route);
    await page.waitForLoadState('networkidle');
    results.push({ route, height: 844, ...await page.evaluate(measure) });
  }
  const failures = results.filter(r => r.documentWidth > r.width + 2 || r.stageScrollWidth > r.stageWidth + 2 || r.overflow.length);
  fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify({ results, errors, failures }, null, 2));
  console.log(JSON.stringify({ checks: results.length, failures, errors }, null, 2));
  await browser.close();
  if (failures.length || errors.length) process.exitCode = 1;
}
module.exports = { mock, base, fixture, measure };
if (require.main === module) run().catch(async error => { console.error(error); await activeBrowser?.close(); process.exitCode = 1; });
