import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from '../../../frontend/user-web/node_modules/playwright/index.mjs';

const toolDirectory = dirname(fileURLToPath(import.meta.url));
const appDirectory = resolve(toolDirectory, '..');
const mark = readFileSync(resolve(appDirectory, 'assets/logo-mark.png'));
const encodedMark = mark.toString('base64');

const targets = [
  ['android/app/src/main/res/mipmap-mdpi/ic_launcher.png', 48],
  ['android/app/src/main/res/mipmap-hdpi/ic_launcher.png', 72],
  ['android/app/src/main/res/mipmap-xhdpi/ic_launcher.png', 96],
  ['android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png', 144],
  ['android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png', 192],
  ['ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png', 20],
  ['ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png', 40],
  ['ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png', 60],
  ['ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png', 29],
  ['ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png', 58],
  ['ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png', 87],
  ['ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png', 40],
  ['ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png', 80],
  ['ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png', 120],
  ['ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png', 120],
  ['ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png', 180],
  ['ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png', 76],
  ['ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png', 152],
  ['ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png', 167],
  ['ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png', 1024],
];

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1024, height: 1024 } });
await page.setContent(`<!doctype html><style>html,body{margin:0;width:100%;height:100%;overflow:hidden}body{display:grid;place-items:center;background:#fff}img{display:block;width:82%;height:82%;object-fit:contain}</style><img src="data:image/png;base64,${encodedMark}">`);

for (const [relativePath, size] of targets) {
  const outputPath = resolve(appDirectory, relativePath);
  mkdirSync(dirname(outputPath), { recursive: true });
  await page.setViewportSize({ width: size, height: size });
  await page.screenshot({ path: outputPath, animations: 'disabled' });
}

for (const faviconPath of [
  resolve(appDirectory, '../../frontend/user-web/public/favicon.png'),
  resolve(appDirectory, '../../frontend/admin-web/public/favicon.png'),
]) {
  await page.setViewportSize({ width: 64, height: 64 });
  await page.screenshot({ path: faviconPath, animations: 'disabled' });
  const png = readFileSync(faviconPath);
  const icoHeader = Buffer.alloc(22);
  icoHeader.writeUInt16LE(0, 0);
  icoHeader.writeUInt16LE(1, 2);
  icoHeader.writeUInt16LE(1, 4);
  icoHeader.writeUInt8(64, 6);
  icoHeader.writeUInt8(64, 7);
  icoHeader.writeUInt16LE(1, 10);
  icoHeader.writeUInt16LE(32, 12);
  icoHeader.writeUInt32LE(png.length, 14);
  icoHeader.writeUInt32LE(22, 18);
  writeFileSync(faviconPath.replace(/\.png$/, '.ico'), Buffer.concat([icoHeader, png]));
}

await browser.close();
console.log(`Generated ${targets.length} launcher icons and 2 favicons from the HuTube Orbit mark.`);
