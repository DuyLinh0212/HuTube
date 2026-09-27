import { ApplicationConfig, inject, provideAppInitializer, provideBrowserGlobalErrorListeners, provideZoneChangeDetection } from '@angular/core';
import { COMPOSITION_BUFFER_MODE } from '@angular/forms';
import { registerLocaleData } from '@angular/common';
import localeVi from '@angular/common/locales/vi';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideRouter } from '@angular/router';
import { routes } from './app.routes';
import { authInterceptor } from './core/auth.interceptor';
import { RuntimeConfig } from './core/runtime-config';

// Keep locale data available to every route, including lazy-loaded pages that
// may use Angular's DatePipe directly in the future.
registerLocaleData(localeVi, 'vi-VN');

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideZoneChangeDetection({ eventCoalescing: true }),
    provideRouter(routes),
    provideHttpClient(withInterceptors([authInterceptor])),
    provideAppInitializer(() => inject(RuntimeConfig).load()),
    { provide: COMPOSITION_BUFFER_MODE, useValue: false }
  ]
};
