const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const repositoryRoot = path.resolve(__dirname, '../../..');
process.chdir(repositoryRoot);

const userOrigin = process.env.USER_WEB_URL || 'http://localhost:4200';
const adminOrigin = process.env.ADMIN_WEB_URL || 'http://localhost:4201';
const apiBase = (process.env.API_BASE_URL || 'http://localhost:5080/api/v1').replace(/\/$/, '');
const apiOrigin = new URL(apiBase).origin;
const outputDir = process.env.E2E_OUTPUT_DIR || path.resolve('.work/screenshots');
const password = 'E2ePassword123!';
const avatarPath = path.resolve('docs/design/642549382-81cc2b6b-4ad0-45e6-b25b-32cb8e9a5c83.png');
const bannerPath = path.resolve('docs/design/642604009-495d3b88-8876-4443-8157-8ec0e18a0634.png');

fs.mkdirSync(outputDir, { recursive: true });
let activeBrowser;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function sameApiTarget(left, right) {
  const a = new URL(left);
  const b = new URL(right);
  if (a.href.replace(/\/$/, '') === b.href.replace(/\/$/, '')) return true;
  const localAliases = new Set(['localhost', '127.0.0.1', '10.0.2.2']);
  return localAliases.has(a.hostname) && localAliases.has(b.hostname)
    && a.protocol === b.protocol && a.port === b.port
    && a.pathname.replace(/\/$/, '') === b.pathname.replace(/\/$/, '');
}

function parseDotNetConnection(value) {
  const result = {};
  for (const part of (value || '').split(';')) {
    const separator = part.indexOf('=');
    if (separator < 1) continue;
    result[part.slice(0, separator).trim().toLowerCase()] = part.slice(separator + 1).trim();
  }
  return result;
}

function assignSystemRole(email, role) {
  const connection = parseDotNetConnection(process.env.ConnectionStrings__Database || process.env.TEST_DATABASE_CONNECTION);
  const pgEnvironment = {
    ...process.env,
    PGHOST: connection.host || process.env.PGHOST || '127.0.0.1',
    PGPORT: connection.port || process.env.PGPORT || '5432',
    PGDATABASE: connection.database || process.env.PGDATABASE,
    PGUSER: connection.username || connection['user id'] || process.env.PGUSER,
    PGPASSWORD: connection.password || process.env.PGPASSWORD
  };
  const sql = `UPDATE public.users
SET role_id = (SELECT role_id FROM public.roles WHERE code = :'role'), updated_at = now()
WHERE email = :'email'::citext
RETURNING (SELECT code FROM public.roles WHERE role_id = users.role_id);`;
  const result = spawnSync(
    process.env.PSQL_BINARY || 'psql',
    ['-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1', '-v', `email=${email}`, '-v', `role=${role}`],
    { input: sql, encoding: 'utf8', env: pgEnvironment }
  );
  if (result.error || result.status !== 0 || !result.stdout.split(/\r?\n/).includes(role)) {
    throw new Error('Could not assign the E2E system role. Verify psql and the E2E database connection.');
  }
}

function emailLink(email, route) {
  const configuredDirectory = process.env.EMAIL_PICKUP_DIRECTORY || '.work/mail';
  const directories = path.isAbsolute(configuredDirectory)
    ? [configuredDirectory]
    : [path.resolve(configuredDirectory), path.resolve('backend/src/HuTube.Api', configuredDirectory)];
  const files = directories
    .filter(directory => fs.existsSync(directory))
    .flatMap(directory => fs.readdirSync(directory)
      .filter(name => name.endsWith('.eml'))
      .map(name => ({ filePath: path.join(directory, name), modified: fs.statSync(path.join(directory, name)).mtimeMs })))
    .sort((a, b) => b.modified - a.modified);
  for (const { filePath } of files) {
    const message = fs.readFileSync(filePath, 'utf8');
    if (!message.includes(email)) continue;
    const separator = message.match(/\r?\n\r?\n/);
    if (!separator) continue;
    const head = message.slice(0, separator.index);
    const raw = message.slice(separator.index + separator[0].length);
    const body = /Content-Transfer-Encoding:\s*base64/i.test(head)
      ? Buffer.from(raw.replace(/\s/g, ''), 'base64').toString('utf8')
      : /Content-Transfer-Encoding:\s*quoted-printable/i.test(head)
        ? raw.replace(/=\r?\n/g, '').replace(/=([A-F0-9]{2})/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16)))
        : raw;
    const url = body.match(new RegExp(`http[^\\s]+/${route}\\?token=[^\\s]+`))?.[0];
    if (url) return url;
  }
  throw new Error(`No ${route} email found for ${email}.`);
}

async function createVerifiedUser(page, identity, throughUi = false) {
  if (throughUi) {
    await page.goto(`${userOrigin}/register`);
    await page.getByLabel('Tên hiển thị', { exact: true }).fill(identity.displayName);
    await page.getByLabel('Tên người dùng', { exact: true }).fill(identity.username);
    await page.getByLabel('Email', { exact: true }).fill(identity.email);
    await page.getByLabel('Mật khẩu', { exact: true }).fill(password);
    await page.locator('#confirmPassword').fill(password);
    await page.locator('form button[type="submit"]').click();
    await page.getByRole('status').filter({ hasText: 'Tài khoản đã được tạo' }).waitFor();
  } else {
    const response = await page.request.post(`${apiBase}/auth/register`, {
      headers: { 'X-HuTube-Client': 'web', Origin: userOrigin },
      data: { ...identity, password }
    });
    assert(response.status() === 201, `Registration failed for ${identity.email}: ${response.status()}`);
  }
  await page.goto(emailLink(identity.email, 'verify-email'));
  await page.getByRole('status').filter({ hasText: 'Email đã được xác minh' }).waitFor();
}

async function login(page, origin, email, platform = 'web') {
  await page.goto(`${origin}/login`);
  await page.getByLabel('Email', { exact: true }).fill(email);
  await page.getByLabel('Mật khẩu', { exact: true }).fill(password);
  const responsePromise = page.waitForResponse(response =>
    response.url() === `${apiBase}/auth/login` && response.request().method() === 'POST'
  );
  await page.locator('form button[type="submit"]').click();
  const response = await responsePromise;
  assert(response.status() === 200, `${platform} login failed for ${email}: ${response.status()}`);
  const payload = await response.json();
  await page.getByRole('heading', { name: platform === 'admin' ? 'Tài khoản quản trị' : 'Cài đặt tài khoản', exact: true }).waitFor();
  return payload.accessToken;
}

async function api(page, method, route, token, client = 'web', data) {
  const options = {
    headers: { Authorization: `Bearer ${token}`, 'X-HuTube-Client': client }
  };
  if (data !== undefined) options.data = data;
  return page.request.fetch(`${apiBase}${route}`, { method, ...options });
}

async function registerLogin(page, identity) {
  await createVerifiedUser(page, identity);
  await login(page, userOrigin, identity.email);
}

async function mobileLogin(page, email) {
  const response = await page.request.post(`${apiBase}/auth/login`, {
    headers: { 'X-HuTube-Client': 'mobile' },
    data: { email, password, platform: 'mobile', deviceName: 'Sprint 4 E2E Mobile' }
  });
  assert(response.status() === 200, `Mobile API login failed for ${email}: ${response.status()}`);
  return (await response.json()).accessToken;
}

(async () => {
  const browser = activeBrowser = await chromium.launch({
    headless: process.env.HEADED !== '1',
    ...(process.env.PLAYWRIGHT_CHANNEL ? { channel: process.env.PLAYWRIGHT_CHANNEL } : {})
  });
  const contexts = [];
  const newPage = async () => {
    const context = await browser.newContext({ viewport: { width: 1440, height: 960 } });
    contexts.push(context);
    const page = await context.newPage();
    page.setDefaultNavigationTimeout(120000);
    page.setDefaultTimeout(60000);
    return page;
  };
  const ownerPage = await newPage();
  const suffix = Date.now();
  const owner = { email: `s4-owner-${suffix}@example.test`, username: `s4_owner_${suffix}`, displayName: 'Sprint 4 Owner' };
  const editor = { email: `s4-editor-${suffix}@example.test`, username: `s4_editor_${suffix}`, displayName: 'Sprint 4 Editor' };
  const moderator = { email: `s4-mod-${suffix}@example.test`, username: `s4_mod_${suffix}`, displayName: 'Sprint 4 Moderator' };

  // E2E-S4-01: Register -> Verify -> Login -> protected Profile -> refresh restore.
  const googleConfigurationErrors = [];
  ownerPage.on('console', message => {
    const text = message.text();
    if (/GSI_LOGGER|given origin is not allowed|client_id.*(invalid|missing)/i.test(text)) googleConfigurationErrors.push(text);
  });
  await createVerifiedUser(ownerPage, owner, true);
  let ownerToken = await login(ownerPage, userOrigin, owner.email);
  const refreshPromise = ownerPage.waitForResponse(response =>
    response.url() === `${apiBase}/auth/refresh` && response.request().method() === 'POST'
  );
  await ownerPage.reload();
  const refreshResponse = await refreshPromise;
  assert(refreshResponse.status() === 200, `Session refresh returned ${refreshResponse.status()}.`);
  ownerToken = (await refreshResponse.json()).accessToken;
  await ownerPage.getByRole('heading', { name: 'Cài đặt tài khoản', exact: true }).waitFor();
  await ownerPage.screenshot({ path: path.join(outputDir, 'e2e-s4-01-session-restored.png'), fullPage: true });
  console.log('PASS E2E-S4-01 register, verify, login, protected profile and refresh restore.');

  // E2E-S4-02: an ordinary user is denied by both Admin UI and API.
  const deniedPage = await ownerPage.context().newPage();
  await deniedPage.goto(`${adminOrigin}/login`);
  await deniedPage.getByLabel('Email', { exact: true }).fill(owner.email);
  await deniedPage.getByLabel('Mật khẩu', { exact: true }).fill(password);
  await deniedPage.locator('form button[type="submit"]').click();
  await deniedPage.getByRole('alert').filter({ hasText: 'quyền quản trị' }).waitFor();
  assert(deniedPage.url().includes('/login'), 'Ordinary user entered the Admin UI.');
  const deniedApi = await api(deniedPage, 'GET', '/admin/me', ownerToken);
  assert(deniedApi.status() === 403, `Ordinary user Admin API returned ${deniedApi.status()}, expected 403.`);
  await deniedPage.screenshot({ path: path.join(outputDir, 'e2e-s4-02-admin-denied.png'), fullPage: true });
  console.log('PASS E2E-S4-02 ordinary user denied by Admin UI and API.');

  // E2E-S4-03: Moderator sees only seeded menus; forbidden deep-link and approve API remain blocked.
  const moderatorPage = await newPage();
  await createVerifiedUser(moderatorPage, moderator);
  assignSystemRole(moderator.email, 'moderator');
  const moderatorToken = await login(moderatorPage, adminOrigin, moderator.email, 'admin');
  const sidebar = moderatorPage.getByRole('complementary', { name: 'Điều hướng quản trị' });
  await sidebar.getByText('Kiểm duyệt', { exact: true }).waitFor();
  await sidebar.getByTitle('Video', { exact: true }).waitFor();
  assert(await sidebar.getByText('Người dùng', { exact: true }).count() === 0, 'Moderator saw the User menu.');
  assert(await sidebar.getByText('Kinh doanh', { exact: true }).count() === 0, 'Moderator saw the Business menu.');
  assert(await sidebar.getByText('Hệ thống', { exact: true }).count() === 0, 'Moderator saw the System menu.');
  const queue = await api(moderatorPage, 'GET', '/admin/moderation/queue', moderatorToken);
  assert(queue.status() === 200, `Moderator queue API returned ${queue.status()}, expected 200.`);
  const approve = await api(moderatorPage, 'POST', '/admin/moderation/approve', moderatorToken);
  assert(approve.status() === 403, `Moderator approve API returned ${approve.status()}, expected 403.`);
  await moderatorPage.goto(`${adminOrigin}/users`);
  await moderatorPage.getByRole('heading', { name: 'Không có quyền truy cập', exact: true }).waitFor();
  await moderatorPage.screenshot({ path: path.join(outputDir, 'e2e-s4-03-moderator-rbac.png'), fullPage: true });
  console.log('PASS E2E-S4-03 moderator limited menu, allowed queue, forbidden deep-link and approve API.');

  // E2E-S4-04: create, upload, edit and verify one persisted contract for Web and Mobile.
  const handle = `s4-${suffix}`;
  const channelName = `Sprint 4 Channel ${suffix}`;
  const updatedDescription = `Nội dung đã cập nhật bởi smoke Sprint 4 ${suffix}`;
  await ownerPage.goto(`${userOrigin}/channel/create`);
  await ownerPage.getByLabel(/^Tên kênh/).fill(channelName);
  await ownerPage.getByLabel(/^Handle \(Tên định danh\)/).fill(handle);
  await ownerPage.getByLabel(/^Handle \(Tên định danh\)/).dispatchEvent('input');
  await ownerPage.getByText(/Handle khả dụng|có thể sử dụng/i).waitFor();
  await ownerPage.getByLabel('Mô tả kênh', { exact: true }).fill('Mô tả lúc tạo kênh');
  await ownerPage.getByLabel('Email liên hệ công việc', { exact: true }).fill(owner.email);
  const createFiles = ownerPage.locator('form input[type="file"]');
  await createFiles.nth(0).setInputFiles(bannerPath);
  await createFiles.nth(1).setInputFiles(avatarPath);
  await ownerPage.locator('form button[type="submit"]').click();
  await ownerPage.waitForURL(new RegExp(`/channel/${handle}$`));
  await ownerPage.getByRole('heading', { name: channelName, exact: true }).waitFor();
  await ownerPage.getByAltText(`Ảnh đại diện kênh ${channelName}`).waitFor();
  await ownerPage.getByAltText(`Ảnh bìa kênh ${channelName}`).waitFor();
  await ownerPage.goto(`${userOrigin}/channel/${handle}/customize`);
  await ownerPage.getByLabel('Mô tả kênh', { exact: true }).fill(updatedDescription);
  await ownerPage.getByRole('button', { name: 'Lưu thay đổi', exact: true }).click();
  await ownerPage.getByRole('status').filter({ hasText: 'Đã cập nhật thông tin kênh' }).waitFor();
  await ownerPage.getByRole('button', { name: 'Xây dựng thương hiệu', exact: true }).click();
  const brandingFiles = ownerPage.locator('.branding-tab-pane input[type="file"]');
  await brandingFiles.nth(0).setInputFiles(avatarPath);
  await ownerPage.getByRole('status').filter({ hasText: 'Đã cập nhật ảnh đại diện kênh' }).waitFor();
  await ownerPage.getByRole('button', { name: 'Xây dựng thương hiệu', exact: true }).click();
  await ownerPage.locator('.branding-tab-pane input[type="file"]').nth(1).setInputFiles(bannerPath);
  await ownerPage.getByRole('status').filter({ hasText: 'Đã cập nhật ảnh bìa kênh' }).waitFor();
  await ownerPage.reload();
  await ownerPage.getByRole('heading', { name: 'Tùy chỉnh kênh', exact: true }).waitFor();
  const ownerMobileToken = await mobileLogin(ownerPage, owner.email);
  const webChannelResponse = await api(ownerPage, 'GET', `/channels/handle/${handle}`, ownerMobileToken, 'web');
  const mobileChannelResponse = await api(ownerPage, 'GET', `/channels/handle/${handle}`, ownerMobileToken, 'mobile');
  assert(webChannelResponse.status() === 200 && mobileChannelResponse.status() === 200, 'Web or Mobile channel contract request failed.');
  const webChannel = await webChannelResponse.json();
  const mobileChannel = await mobileChannelResponse.json();
  assert(webChannel.channelId === mobileChannel.channelId, 'Web and Mobile returned different channels.');
  assert(webChannel.description === updatedDescription, 'Updated channel description was not persisted.');
  assert(webChannel.avatarUrl && webChannel.bannerUrl, 'Channel branding URLs were not persisted.');
  assert(/^https?:\/\//.test(webChannel.avatarUrl) && /^https?:\/\//.test(webChannel.bannerUrl), 'Channel branding URLs are not absolute.');
  await ownerPage.screenshot({ path: path.join(outputDir, 'e2e-s4-04-channel-branding.png'), fullPage: true });
  console.log('PASS E2E-S4-04 create channel, avatar/banner uploads, customization, refresh persistence and shared Web/Mobile data.');

  // E2E-S4-05: invite Editor, accept, allow member view and deny delete at the backend.
  const editorPage = await newPage();
  await registerLogin(editorPage, editor);
  await ownerPage.goto(`${userOrigin}/channel/${handle}/customize`);
  await ownerPage.getByRole('button', { name: 'Thành viên & quyền', exact: true }).click();
  await ownerPage.getByLabel('Email người dùng', { exact: true }).fill(editor.email);
  await ownerPage.getByLabel('Vai trò', { exact: true }).selectOption('editor');
  await ownerPage.getByRole('button', { name: 'Gửi lời mời', exact: true }).click();
  await ownerPage.getByRole('status').filter({ hasText: 'Đã gửi lời mời' }).waitFor();
  await editorPage.goto(`${userOrigin}/channel-invitations`);
  const invitation = editorPage.locator('.invitation-card').filter({ hasText: channelName });
  await invitation.getByRole('button', { name: 'Chấp nhận', exact: true }).click();
  await editorPage.getByRole('status').filter({ hasText: 'Đã tham gia kênh' }).waitFor();
  await editorPage.goto(`${userOrigin}/channel/${handle}/customize`);
  await editorPage.getByText('vai trò').filter({ hasText: 'Biên tập viên' }).waitFor();
  await editorPage.getByRole('button', { name: 'Thành viên & quyền', exact: true }).waitFor();
  assert(await editorPage.getByRole('button', { name: 'Xóa kênh', exact: true }).count() === 0, 'Editor saw the delete-channel control.');
  const editorToken = await mobileLogin(editorPage, editor.email);
  const members = await api(editorPage, 'GET', `/channels/${webChannel.channelId}/members`, editorToken, 'mobile');
  assert(members.status() === 200, `Editor member-view API returned ${members.status()}, expected 200.`);
  const deleteChannel = await api(editorPage, 'DELETE', `/channels/${webChannel.channelId}`, editorToken, 'mobile');
  assert(deleteChannel.status() === 403, `Editor delete API returned ${deleteChannel.status()}, expected 403.`);
  await editorPage.screenshot({ path: path.join(outputDir, 'e2e-s4-05-editor-rbac.png'), fullPage: true });
  console.log('PASS E2E-S4-05 Editor invitation, acceptance, permitted member view and backend-enforced delete denial.');

  // E2E-S4-06: all clients share runtime host configuration and the published OpenAPI contract.
  const userConfigResponse = await ownerPage.request.get(`${userOrigin}/config.json`);
  const adminConfigResponse = await ownerPage.request.get(`${adminOrigin}/config.json`);
  const userConfig = await userConfigResponse.json();
  const adminConfig = await adminConfigResponse.json();
  assert(userConfig.API_BASE_URL === apiBase, `User Web base URL differs: ${userConfig.API_BASE_URL}`);
  assert(adminConfig.API_BASE_URL === apiBase, `Admin Web base URL differs: ${adminConfig.API_BASE_URL}`);
  if (process.env.MOBILE_API_BASE_URL) {
    assert(sameApiTarget(process.env.MOBILE_API_BASE_URL, apiBase), 'Mobile base URL targets a different API from Web/Admin.');
  }
  const info = await ownerPage.request.get(`${apiBase}/system/info`, { headers: { 'X-HuTube-Client': 'mobile' } });
  assert(info.status() === 200, `Mobile system contract returned ${info.status()}.`);
  const publicSystemConfigResponse = await ownerPage.request.get(`${apiBase}/system/config`);
  assert(publicSystemConfigResponse.status() === 200, `Public system config returned ${publicSystemConfigResponse.status()}.`);
  const publicSystemConfig = await publicSystemConfigResponse.json();
  assert(userConfig.GOOGLE_CLIENT_ID === publicSystemConfig.googleClientId, 'Web and API use different Google client IDs.');
  const openApiResponse = await ownerPage.request.get(`${apiOrigin}/openapi/v1.json`);
  assert(openApiResponse.status() === 200, `OpenAPI returned ${openApiResponse.status()}.`);
  const openApi = await openApiResponse.json();
  const paths = openApi.paths || {};
  assert(paths['/api/v1/auth/login'], 'OpenAPI is missing auth login.');
  assert(paths['/api/v1/channels'], 'OpenAPI is missing channel create.');
  assert(paths['/api/v1/admin/me'], 'OpenAPI is missing Admin identity.');
  if (process.env.VERIFY_GOOGLE_ORIGIN === '1') {
    assert(googleConfigurationErrors.length === 0, `Google Identity configuration errors: ${googleConfigurationErrors.join(' | ')}`);
  } else if (googleConfigurationErrors.length > 0) {
    console.warn('WARN Google Identity origin check depends on external console propagation; run with VERIFY_GOOGLE_ORIGIN=1 from an authorized browser environment.');
  }
  console.log('PASS E2E-S4-06 shared User Web/Admin/Mobile base URL and compatible OpenAPI contract.');

  for (const context of contexts) await context.close();
  await browser.close();
  console.log('PASS all 6 Sprint 4 smoke E2E scenarios.');
})().catch(async error => {
  await activeBrowser?.close();
  console.error(error);
  process.exit(1);
});
