import type { FeedbackService } from '@dalitu/ui/feedback.service';
import type { I18nService } from '../core/i18n.service';

export function confirmChannelUnsubscribe(feedback: FeedbackService, i18n: I18nService): Promise<boolean> {
  i18n.registerTranslations({
    vi: {
      'subscription.confirmTitle': 'Hủy đăng ký kênh?',
      'subscription.confirmDescription': 'Bạn có chắc muốn hủy đăng ký kênh này?',
      'subscription.confirmAction': 'Hủy đăng ký',
    },
    en: {
      'subscription.confirmTitle': 'Unsubscribe from this channel?',
      'subscription.confirmDescription': 'Are you sure you want to unsubscribe from this channel?',
      'subscription.confirmAction': 'Unsubscribe',
    },
  });
  return feedback.confirm(i18n.t('subscription.confirmDescription'), {
    title: i18n.t('subscription.confirmTitle'),
    confirmLabel: i18n.t('subscription.confirmAction'),
    tone: 'danger',
  });
}
