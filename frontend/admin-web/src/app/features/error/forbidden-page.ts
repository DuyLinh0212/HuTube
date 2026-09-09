import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

@Component({
  selector: 'app-forbidden-page',
  imports: [RouterLink],
  template: `
    <main class="forbidden-card" style="max-width: 520px; margin: 60px auto; padding: 32px; background: #fff; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.08); text-align: center;">
      <h1 style="font-size: 48px; margin: 0 0 16px; color: #dc2626;">403</h1>
      <h2 style="font-size: 20px; margin: 0 0 12px; color: #111827;">Không có quyền truy cập</h2>
      <p style="color: #6b7280; line-height: 1.5; margin: 0 0 24px;">Tài khoản của bạn không có đủ quyền hạn để truy cập trang này. Vui lòng liên hệ Quản trị viên hệ thống nếu bạn cần cấp quyền.</p>
      <a routerLink="/account" style="display: inline-block; padding: 10px 20px; background: #2563eb; color: #fff; border-radius: 8px; text-decoration: none; font-weight: 500;">Về trang Tài khoản</a>
    </main>
  `
})
export class ForbiddenPage {}
