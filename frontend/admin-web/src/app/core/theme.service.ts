import { Injectable, signal, effect } from '@angular/core';

export type AppTheme = 'light' | 'dark';

@Injectable({
  providedIn: 'root'
})
export class ThemeService {
  private readonly STORAGE_KEY = 'hutube_admin_theme';
  readonly currentTheme = signal<AppTheme>('light');

  constructor() {
    const saved = localStorage.getItem(this.STORAGE_KEY) as AppTheme | null;
    const globalSaved = localStorage.getItem('hutube_theme') as AppTheme | null;
    const initial = saved || globalSaved;

    if (initial === 'dark' || initial === 'light') {
      this.currentTheme.set(initial);
    } else if (typeof window !== 'undefined' && window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
      this.currentTheme.set('dark');
    }

    this.applyTheme(this.currentTheme());

    effect(() => {
      const theme = this.currentTheme();
      this.applyTheme(theme);
    });
  }

  toggleTheme(): void {
    const next = this.currentTheme() === 'dark' ? 'light' : 'dark';
    this.setTheme(next);
  }

  setTheme(theme: AppTheme): void {
    this.currentTheme.set(theme);
    localStorage.setItem(this.STORAGE_KEY, theme);
    localStorage.setItem('hutube_theme', theme);
    this.applyTheme(theme);
  }

  private applyTheme(theme: AppTheme): void {
    if (typeof document === 'undefined') return;
    const root = document.documentElement;
    root.setAttribute('data-theme', theme);
    if (theme === 'dark') {
      document.body.classList.add('dark-theme');
    } else {
      document.body.classList.remove('dark-theme');
    }
  }
}
