import { ApplicationConfig, inject, provideAppInitializer, provideBrowserGlobalErrorListeners, provideZoneChangeDetection } from '@angular/core';
import { COMPOSITION_BUFFER_MODE } from '@angular/forms';
import { registerLocaleData } from '@angular/common';
import localeVi from '@angular/common/locales/vi';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideRouter } from '@angular/router';
import { routes } from './app.routes';
import { authInterceptor } from './core/auth.interceptor';
import { RuntimeConfig } from './core/runtime-config';
import { I18nTitleStrategy } from './core/i18n-title.strategy';
import { TitleStrategy } from '@angular/router';

// DatePipe receives the active language as an explicit locale on the admin pages.
// Register Vietnamese data once during app startup so every standalone page can
// safely render dates without throwing NG0701/NG02100 at runtime.
registerLocaleData(localeVi, 'vi-VN');

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideZoneChangeDetection({ eventCoalescing: true }),
    provideRouter(routes),
    { provide: TitleStrategy, useClass: I18nTitleStrategy },
    provideHttpClient(withInterceptors([authInterceptor])),
    provideAppInitializer(() => inject(RuntimeConfig).load()),
    { provide: COMPOSITION_BUFFER_MODE, useValue: false }
  ]
};
