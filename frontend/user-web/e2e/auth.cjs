const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const repositoryRoot=path.resolve(__dirname, '../../..');
process.chdir(repositoryRoot);
const userOrigin=process.env.USER_WEB_URL || 'http://localhost:4200';
const adminOrigin=process.env.ADMIN_WEB_URL || 'http://localhost:4201';
const apiBase=process.env.API_BASE_URL || 'http://localhost:5080/api/v1';
const outputDir=process.env.E2E_OUTPUT_DIR || path.resolve('.work/screenshots');
fs.mkdirSync(outputDir,{recursive:true});
let activeBrowser;
function adminSql(email, input) {
 const result=spawnSync(process.env.PSQL_BINARY || 'psql', ['-X','-q','-v','ON_ERROR_STOP=1','-v','email='+email], {input,encoding:'utf8',env:process.env});
 if(result.error || result.status !== 0) throw Error('Admin E2E database operation failed. Verify PSQL_BINARY and PG environment configuration.');
}
function emailLink(email, route) {
 const dir=process.env.EMAIL_PICKUP_DIRECTORY || path.resolve('.work/mail');
 const files=fs.readdirSync(dir).filter(name=>name.endsWith('.eml')).map(name=>({name,mtime:fs.statSync(path.join(dir,name)).mtimeMs})).sort((a,b)=>b.mtime-a.mtime);
 for(const {name} of files) {
  const message=fs.readFileSync(path.join(dir,name),'utf8'); if(!message.includes(email)) continue;
  const separator=message.match(/\r?\n\r?\n/); if(!separator) continue;
  const head=message.slice(0,separator.index), raw=message.slice(separator.index+separator[0].length);
  const body=/Content-Transfer-Encoding:\s*base64/i.test(head)?Buffer.from(raw.replace(/\s/g,''),'base64').toString('utf8')
   :/Content-Transfer-Encoding:\s*quoted-printable/i.test(head)?raw.replace(/=\r?\n/g,'').replace(/=([A-F0-9]{2})/gi,(_,hex)=>String.fromCharCode(parseInt(hex,16))) : raw;
  const url=body.match(new RegExp('http[^\\s]+/'+route+'\\?token=[^\\s]+'))?.[0]; if(url) return url;
 }
 throw Error('No '+route+' email found for test recipient');
}
(async()=>{
 const browser=activeBrowser=await chromium.launch({headless:true, ...(process.env.PLAYWRIGHT_CHANNEL ? {channel:process.env.PLAYWRIGHT_CHANNEL} : {})});
 const first=await browser.newContext({viewport:{width:1440,height:960}}), second=await browser.newContext();
 const page=await first.newPage(), other=await second.newPage();
 page.setDefaultNavigationTimeout(120000); other.setDefaultNavigationTimeout(120000);
 page.setDefaultTimeout(60000); other.setDefaultTimeout(60000);
 const suffix=Date.now(), email='web-e2e-'+suffix+'@example.test', password='E2ePassword123!', newPassword='NewE2ePassword123!';
 const exceptions=[]; page.on('pageerror',e=>exceptions.push(e.message));
 const login=async(target,origin,pw)=>{await target.goto(origin+'/login'); await target.getByLabel('Email',{exact:true}).fill(email); await target.getByLabel('Mật khẩu',{exact:true}).fill(pw); await target.getByRole('button',{name:'Đăng nhập',exact:true}).click();};
 await page.goto(userOrigin+'/register');
 await page.getByLabel('Tên hiển thị',{exact:true}).fill('Người dùng kiểm thử'); await page.getByLabel('Tên người dùng',{exact:true}).fill('web_e2e_'+suffix); await page.getByLabel('Email',{exact:true}).fill(email); await page.getByLabel('Mật khẩu',{exact:true}).fill(password); await page.getByLabel('Nhập lại mật khẩu',{exact:true}).fill(password); await page.getByRole('button',{name:'Tạo tài khoản',exact:true}).click();
 await page.getByRole('status').filter({hasText:'Tài khoản đã được tạo'}).waitFor();
 await page.goto(emailLink(email,'verify-email')); await page.getByRole('status').filter({hasText:'Email đã được xác minh'}).waitFor();
 await login(page,userOrigin,password); await page.getByRole('heading',{name:'Thiết bị đang đăng nhập'}).waitFor();
 const cookies=await first.cookies(apiBase+'/auth/refresh'); if(!cookies.some(cookie=>cookie.httpOnly)) throw Error('Missing HttpOnly refresh cookie');
 const storage=await page.evaluate(()=>({local:Object.keys(localStorage),session:Object.keys(sessionStorage)})); if(storage.local.length||storage.session.length) throw Error('Unexpected browser storage');
 await page.reload(); await page.getByRole('heading',{name:'Thiết bị đang đăng nhập'}).waitFor();
 await page.screenshot({path:path.join(outputDir,'user-account-desktop.png'),fullPage:true}); await page.setViewportSize({width:390,height:844}); await page.screenshot({path:path.join(outputDir,'user-account-mobile.png'),fullPage:true});
 if(await page.locator('body').evaluate(element=>element.scrollWidth>window.innerWidth)) throw Error('Account mobile overflow');
 await login(other,userOrigin,password); await other.getByRole('heading',{name:'Thiết bị đang đăng nhập'}).waitFor();
 await page.reload(); await page.getByRole('button',{name:'Đăng xuất các thiết bị khác',exact:true}).click(); await page.getByRole('status').filter({hasText:'Đã đăng xuất khỏi các thiết bị khác'}).waitFor();
 await other.reload(); await other.getByRole('heading',{name:/^Đăng nhập/}).waitFor();
 await page.goto(userOrigin+'/forgot-password'); await page.getByLabel('Email',{exact:true}).fill(email); await page.getByRole('button',{name:'Gửi liên kết',exact:true}).click(); await page.getByRole('status').filter({hasText:'Nếu email có trong hệ thống'}).waitFor();
 await page.goto(emailLink(email,'reset-password'));
 const appLink=await page.getByRole('link',{name:'Mở trong ứng dụng HuTube'}).getAttribute('href');
 if(!appLink?.startsWith('hutube://auth/reset-password?token=') || appLink.includes('unsafe:')) throw Error('Mobile reset link was sanitized incorrectly');
 await page.getByLabel('Mật khẩu mới',{exact:true}).fill(newPassword); await page.getByLabel('Nhập lại mật khẩu',{exact:true}).fill(newPassword); await page.getByRole('button',{name:'Đặt lại mật khẩu',exact:true}).click(); await page.getByRole('status').filter({hasText:'Đã đổi mật khẩu'}).waitFor();
 await login(page,userOrigin,password); await page.getByRole('alert').filter({hasText:'Email hoặc mật khẩu chưa đúng'}).waitFor();
 await page.getByLabel('Mật khẩu',{exact:true}).fill(newPassword); await page.getByRole('button',{name:'Đăng nhập',exact:true}).click(); await page.getByRole('heading',{name:'Thiết bị đang đăng nhập'}).waitFor();
 await page.getByRole('button',{name:'Đăng xuất',exact:true}).click(); await page.getByRole('heading',{name:/^Đăng nhập/}).waitFor(); await page.goto(userOrigin+'/account'); await page.getByRole('heading',{name:/^Đăng nhập/}).waitFor();
 await login(other,adminOrigin,newPassword); await other.getByRole('alert').filter({hasText:'quyền quản trị'}).waitFor(); if(!other.url().includes('/login')) throw Error('Normal user entered admin');
 await other.screenshot({path:path.join(outputDir,'admin-access-denied.png'),fullPage:true});
 if(process.env.RUN_ADMIN_DB_TESTS === '1') {
  adminSql(email,fs.readFileSync(path.resolve('database/scripts/grant-local-admin.sql'),'utf8'));
  await login(other,adminOrigin,newPassword); await other.getByRole('heading',{name:'Tài khoản quản trị',exact:true}).waitFor();
  await other.getByRole('heading',{name:'Thiết bị đang đăng nhập'}).waitFor(); await other.screenshot({path:path.join(outputDir,'admin-account-enabled.png'),fullPage:true});
  adminSql(email,"UPDATE public.users SET role_id=(SELECT role_id FROM public.roles WHERE code='user'), status='active', updated_at=now() WHERE email=:'email'::citext;\n");
  await other.reload(); await other.getByRole('heading',{name:/^Đăng nhập/}).waitFor();
  await login(other,adminOrigin,newPassword); await other.getByRole('alert').filter({hasText:'quyền quản trị'}).waitFor();
  await other.screenshot({path:path.join(outputDir,'admin-access-disabled.png'),fullPage:true});
  // Disabling admin access must not disable the ordinary user account.
  await login(page,userOrigin,newPassword); await page.getByRole('heading',{name:'Thiết bị đang đăng nhập'}).waitFor();
  await page.getByRole('button',{name:'Đăng xuất',exact:true}).click(); await page.getByRole('heading',{name:/^Đăng nhập/}).waitFor();
  console.log('PASS admin E2E: granted access signs in, disabled access blocks reload/new login, ordinary user login remains active.');
 }
 await browser.close(); if(exceptions.length) throw Error(exceptions.join('\n'));
 console.log('PASS real browser E2E: register, pickup email verification, login, HttpOnly cookie, empty web storage, reload restore, logout others, revoked second browser, forgot/reset, old password rejected/new accepted, current logout, protected redirect, ordinary user admin denied.');
})().catch(async error=>{await activeBrowser?.close(); console.error(error);process.exit(1)});
