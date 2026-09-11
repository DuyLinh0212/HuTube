import { Injectable, signal } from '@angular/core';

export type AppThemeMode = 'light' | 'dark';

@Injectable({
  providedIn: 'root'
})
export class ThemeService {
  private readonly STORAGE_KEY = 'hutube_theme';
  readonly currentTheme = signal<AppThemeMode>('light');

  constructor() {
    this.initTheme();
  }

  private initTheme(): void {
    const saved = localStorage.getItem(this.STORAGE_KEY) as AppThemeMode | null;
    if (saved === 'light' || saved === 'dark') {
      this.applyTheme(saved);
    } else {
      const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
      this.applyTheme(prefersDark ? 'dark' : 'light');
    }
  }

  setTheme(theme: AppThemeMode): void {
    this.applyTheme(theme);
    localStorage.setItem(this.STORAGE_KEY, theme);
  }

  toggleTheme(): AppThemeMode {
    const next = this.currentTheme() === 'dark' ? 'light' : 'dark';
    this.setTheme(next);
    return next;
  }

  private applyTheme(theme: AppThemeMode): void {
    this.currentTheme.set(theme);
    if (typeof document !== 'undefined') {
      document.documentElement.setAttribute('data-theme', theme);
      if (theme === 'dark') {
        document.body.classList.add('dark-theme');
      } else {
        document.body.classList.remove('dark-theme');
      }
    }
  }
}
