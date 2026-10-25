import { FEEDBACK_LANGUAGE } from '@dalitu/ui/feedback-language';
import { I18nService } from './core/i18n.service';
import { ApplicationConfig, inject, provideAppInitializer, provideBrowserGlobalErrorListeners, provideZoneChangeDetection } from '@angular/core';
import { COMPOSITION_BUFFER_MODE } from '@angular/forms';
import { registerLocaleData } from '@angular/common';
import localeVi from '@angular/common/locales/vi';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideRouter, RedirectCommand, Router, withNavigationErrorHandler } from '@angular/router';
import { routes } from './app.routes';
import { authInterceptor } from './core/auth.interceptor';
import { readCacheInterceptor } from './core/read-cache.interceptor';
import { RuntimeConfig } from './core/runtime-config';
import { I18nTitleStrategy } from './core/i18n-title.strategy';
import { TitleStrategy } from '@angular/router';
import { ChunkLoadRecovery } from './core/chunk-load-recovery';

// DatePipe receives the active language as an explicit locale on the admin pages.
// Register Vietnamese data once during app startup so every standalone page can
// safely render dates without throwing NG0701/NG02100 at runtime.
registerLocaleData(localeVi, 'vi-VN');

export const appConfig: ApplicationConfig = {
  providers: [
    { provide: FEEDBACK_LANGUAGE, useFactory: () => { const i18n = inject(I18nService); return () => i18n.currentLang(); } },
    provideBrowserGlobalErrorListeners(),
    provideZoneChangeDetection({ eventCoalescing: true }),
    provideRouter(routes, withNavigationErrorHandler(event => {
      const target = inject(ChunkLoadRecovery).recover(event.error, event.url);
      if (target) {
        return new RedirectCommand(inject(Router).createUrlTree(['/load-error'], {
          queryParams: { returnUrl: target },
        }), { replaceUrl: true });
      }
      return undefined;
    })),
    { provide: TitleStrategy, useClass: I18nTitleStrategy },
    provideHttpClient(withInterceptors([authInterceptor, readCacheInterceptor])),
    provideAppInitializer(() => inject(RuntimeConfig).load()),
    { provide: COMPOSITION_BUFFER_MODE, useValue: false }
  ]
};
