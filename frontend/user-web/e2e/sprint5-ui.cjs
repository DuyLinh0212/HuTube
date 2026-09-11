const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const path = require('node:path');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.setDefaultTimeout(10000);
  page.on('pageerror', error => console.error('pageerror:', error.message));
  let hasChannel = false;
  const channel = { channelId:'11111111-1111-1111-1111-111111111111',ownerUserId:'22222222-2222-2222-2222-222222222222',name:'Kênh kiểm thử',handle:'kenh-test',description:'Mô tả',avatarUrl:null,bannerUrl:null,contactEmail:null,watermarkUrl:null,settings:'{}',status:'active',subscriberCount:3,videoCount:1,isOwner:true,myRole:'owner',permissions:['video.view'],createdAt:new Date().toISOString() };
  const video = { videoId:'33333333-3333-3333-3333-333333333333',channelId:channel.channelId,channelName:channel.name,channelHandle:channel.handle,categoryId:null,title:'Video dữ liệu thật',description:'Mô tả video',videoUrl:'https://example.test/source.mp4',thumbnailUrl:null,duration:120,fileSize:1000,visibility:'private',status:'processing',moderationStatus:'not_submitted',languageCode:'vi',ageRestricted:false,publishedAt:null,createdAt:new Date().toISOString(),tags:['test'],chapters:[],stats:{views:12,likes:2,dislikes:0,comments:0,averageRating:null,ratingCount:0,shares:0},viewerState:{reaction:null,rating:null,resumeAtSeconds:12,progress:10} };
  await page.route('**/api/v1/**', async route => {
    const url = new URL(route.request().url()); const path = url.pathname;
    const json = (body, status = 200) => route.fulfill({ status, contentType:'application/json', body:JSON.stringify(body) });
    if (path.endsWith('/system/config')) return json({googleClientId:''});
    if (path.endsWith('/feed/home') || path.endsWith('/feed/explore')) return json({items:[video],page:1,pageSize:20,total:1});
    if (path.endsWith('/auth/refresh')) return json({accessToken:'fake.jwt.token',expiresAt:new Date(Date.now()+60000).toISOString(),user:{userId:channel.ownerUserId,username:'test',email:'test@example.com',displayName:'Người Test',emailVerified:true,isAdmin:false}});
    if (path.endsWith('/auth/me')) return json({userId:channel.ownerUserId,username:'test',email:'test@example.com',displayName:'Người Test',emailVerified:true,isAdmin:false});
    if (path.endsWith('/account/profile')) return json({userId:channel.ownerUserId,username:'test',email:'test@example.com',displayName:'Người Test',avatarUrl:'/assets/logo-mark.png',bio:null,emailVerified:true,createdAt:new Date().toISOString()});
    if (path.endsWith('/channels/me')) return hasChannel ? json(channel) : route.fulfill({status:404,contentType:'application/problem+json',body:'{}'});
    if (path.endsWith('/videos/upload-preflight')) return json({allowed:true,maxUploadSize:2147483648,maxDuration:43200,maxQuality:'2160p',storageLimit:10737418240,storageUsed:1048576,storageRemaining:10736373760});
    if (path === '/api/v1/videos' && route.request().method() === 'POST') {
      await new Promise(resolve => setTimeout(resolve, 1200));
      return json(video, 201);
    }
    if (path.endsWith('/videos/manage')) return json({items:[video],page:1,pageSize:50,total:1});
    if (path.endsWith('/categories')) return json([{categoryId:'44444444-4444-4444-4444-444444444444',name:'Giáo dục',slug:'giao-duc',description:null}]);
    if (path.endsWith('/notifications')) return json({items:Array.from({length:5},(_,i)=>({notificationId:`55555555-5555-5555-5555-55555555555${i}`,type:'test',title:`Thông báo ${i+1}`,content:'Nội dung',actionUrl:null,isRead:false,createdAt:new Date().toISOString()})),page:1,pageSize:5,total:5,unreadCount:5,hasMore:false});
    if (path.endsWith(`/videos/${video.videoId}/playback`)) return json({videoId:video.videoId,title:video.title,visibility:'private',duration:120,renditions:[{quality:'360p',width:640,height:360,fileSize:500,url:'https://example.test/360.mp4'},{quality:'720p',width:1280,height:720,fileSize:1000,url:'https://example.test/720.mp4'}],resumeAtSeconds:12,progress:10});
    if (path.endsWith(`/videos/${video.videoId}/comments`)) return json({items:[],page:1,pageSize:20,total:0});
    if (path.endsWith(`/videos/${video.videoId}`)) return json(video);
    return json({});
  });

  await page.goto('http://localhost:4200/home');
  await page.getByRole('heading', { name: 'Video dành cho bạn' }).waitFor();
  assert.equal(await page.getByText('Video dữ liệu thật').count(), 1);
  if (!await page.locator('.side-nav').evaluate(node => node.classList.contains('is-collapsed'))) await page.locator('.sidebar-toggle').click();
  await page.locator('.side-nav.is-collapsed').waitFor();
  assert.ok(await page.locator('.side-nav.is-collapsed .nav-item img').count() >= 6);
  assert.equal(await page.locator('.side-nav.is-collapsed .sidebar-toggle').isVisible(), true);

  await page.goto('http://localhost:4200/studio');
  await page.getByRole('heading', { name: 'Thiết lập kênh trước khi bắt đầu' }).waitFor();
  hasChannel = true;
  await page.goto('http://localhost:4200/studio/upload');
  await page.locator('#videoFile').setInputFiles(path.resolve(__dirname, '../../../.work/upload-test.mp4'));
  await page.waitForTimeout(1000);
  await page.getByRole('button', { name: /Tiếp tục/ }).click();
  await page.locator('.thumb-card').first().waitFor();
  assert.equal(await page.locator('.thumb-card img[src^="blob:"]').count(), 3);
  assert.match(await page.locator('.specs-card').innerText(), /320×180/);
  assert.equal(await page.locator('video.player-video').count(), 1);
  await page.locator('.stepper-item').nth(2).click();
  await page.locator('.timeline-scrubber-card').waitFor();
  await page.locator('.add-chapter-row input').nth(0).fill('Mở đầu');
  await page.locator('.add-chapter-row input').nth(1).fill('0:01');
  await page.getByRole('button', { name: '+ Thêm chương', exact: true }).click();
  await page.locator('.scrubber-chapter-marker').waitFor();
  assert.equal(await page.locator('.scrubber-chapter-marker').count(), 1);
  await page.locator('.stepper-item').nth(4).click();
  await page.locator('input[value="public"]').waitFor();
  assert.equal(await page.locator('input[value="public"]').isDisabled(), true);
  assert.equal(await page.getByText('Share your story with the HuTube community').count(), 0);
  await page.getByRole('button', { name: 'Lưu video' }).click();
  await page.locator('.upload-tray').waitFor();
  assert.match(await page.locator('.upload-tray').innerText(), /Đang tải video lên|Đang tạo các chất lượng video/);
  await page.locator('.studio-nav-item', { hasText: 'Nội dung' }).click();
  await page.getByRole('heading', { name: 'Nội dung' }).waitFor();
  assert.equal(await page.locator('.upload-tray').isVisible(), true);
  await page.waitForTimeout(1400);
  await page.locator('.tray-close').click();

  await page.goto(`http://localhost:4200/watch/${video.videoId}`);
  await page.getByRole('heading', { name: video.title }).waitFor();
  assert.equal(await page.locator('.player-tools select').first().locator('option').count(), 2);
  await page.goto('http://localhost:4200/studio/overview');
  await page.getByRole('heading', { name: 'Tổng quan' }).waitFor();
  assert.equal(await page.getByText('12').count() > 0, true);
  await browser.close();
  console.log('Sprint 5 browser checks passed.');
})().catch(error => { console.error(error); process.exit(1); });
