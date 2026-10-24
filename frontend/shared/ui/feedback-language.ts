import { InjectionToken } from '@angular/core';

export type FeedbackLanguage = 'vi' | 'en';
export const FEEDBACK_LANGUAGE = new InjectionToken<() => FeedbackLanguage>('Dalitu feedback language', {
  providedIn: 'root', factory: () => () => 'vi',
});
export const FEEDBACK_TEXT = {
  vi: { confirm: 'Xác nhận', cancel: 'Hủy', close: 'Đóng', confirmation: 'Xác nhận thao tác', success: 'Thành công', error: 'Chưa thể hoàn tất', warning: 'Cần lưu ý', info: 'Thông tin', working: 'Đang xử lý…' },
  en: { confirm: 'Confirm', cancel: 'Cancel', close: 'Close', confirmation: 'Confirm action', success: 'Success', error: 'Unable to complete', warning: 'Please note', info: 'Information', working: 'Processing…' },
} as const;
export type FeedbackTone = 'success' | 'error' | 'warning' | 'info';
export interface FeedbackDetail { label: string; message?: string; }
