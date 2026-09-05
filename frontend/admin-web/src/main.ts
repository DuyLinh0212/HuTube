import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { App } from './app/app';
bootstrapApplication(App, appConfig).catch(() => {
  const host = document.querySelector('app-root');
  if (host) host.textContent = 'Không thể khởi động HuTube. Vui lòng tải lại trang hoặc kiểm tra cấu hình kết nối.';
});
