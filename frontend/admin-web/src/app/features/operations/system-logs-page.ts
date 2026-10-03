import { Component, OnInit, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { TranslatePipe } from '../../core/translate.pipe';
import { I18nService } from '../../core/i18n.service';
import { AdminOperationsService, AuditLogItem, AuditLogPage } from './operations.service';

@Component({
  selector: 'app-system-logs-page',
  imports: [DecimalPipe, FormsModule, TranslatePipe],
  templateUrl: './system-logs-page.html',
  styleUrl: './system-logs-page.scss',
})
export class SystemLogsPage implements OnInit {
  private readonly operations = inject(AdminOperationsService);
  readonly i18n = inject(I18nService);
  readonly result = signal<AuditLogPage | null>(null);
  readonly loading = signal(true);
  readonly error = signal(false);
  readonly search = signal('');
  readonly action = signal('all');
  readonly fromDate = signal('');
  readonly toDate = signal('');
  readonly page = signal(1);
  readonly pageSize = signal(25);
  readonly expandedId = signal<string | null>(null);

  ngOnInit(): void { this.load(); }

  load(): void {
    this.loading.set(true);
    this.error.set(false);
    this.operations.getAuditLogs({
      page: this.page(), pageSize: this.pageSize(), search: this.search(), action: this.action(),
      fromDate: this.fromDate() ? `${this.fromDate()}T00:00:00.000Z` : undefined,
      toDate: this.toDate() ? `${this.toDate()}T23:59:59.999Z` : undefined,
    }).subscribe({
      next: result => { this.result.set(result); this.loading.set(false); },
      error: () => { this.error.set(true); this.loading.set(false); },
    });
  }

  applyFilters(): void { this.page.set(1); this.load(); }
  setPage(page: number): void { this.page.set(page); this.load(); }
  setPageSize(value: string): void { this.pageSize.set(Number(value) || 25); this.page.set(1); this.load(); }
  toggle(item: AuditLogItem): void { this.expandedId.set(this.expandedId() === item.auditLogId ? null : item.auditLogId); }
  totalPages(): number { return Math.max(1, Math.ceil((this.result()?.total ?? 0) / this.pageSize())); }
  pages(): number[] {
    const total = this.totalPages();
    const current = this.page();
    const start = Math.max(1, Math.min(current - 2, total - 4));
    return Array.from({ length: Math.min(5, total) }, (_, index) => start + index);
  }
  rangeStart(): number { return this.result()?.total ? (this.page() - 1) * this.pageSize() + 1 : 0; }
  rangeEnd(): number { return Math.min(this.page() * this.pageSize(), this.result()?.total ?? 0); }
  actorLabel(item: AuditLogItem): string { return item.actorName || item.actorEmail || this.i18n.t('operations.unknownActor'); }
  actionLabel(action: string): string {
    const normalized = action.replace(/[^a-z0-9]+/gi, '_').toLowerCase();
    const key = `operations.action.${normalized}`;
    const label = this.i18n.t(key);
    return label === key ? action.replace(/[._]+/g, ' ') : label;
  }
  initials(value: string): string { return value.trim().split(/\s+/).slice(0, 2).map(part => part[0] ?? '').join('').toUpperCase(); }
  formatDate(value: string): string {
    return new Intl.DateTimeFormat(this.locale(), { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(value));
  }
  formatTime(value: string): string { return new Intl.DateTimeFormat(this.locale(), { hour: '2-digit', minute: '2-digit', second: '2-digit' }).format(new Date(value)); }
  formatTimestamp(value: string): string { return new Intl.DateTimeFormat(this.locale(), { dateStyle: 'medium', timeStyle: 'medium' }).format(new Date(value)); }
  trackLog(_: number, item: AuditLogItem): string { return item.auditLogId; }
  trackAction(_: number, action: string): string { return action; }
  trackSetting(_: number, setting: { name: string }): string { return setting.name; }
  private locale(): string { return this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US'; }
}
