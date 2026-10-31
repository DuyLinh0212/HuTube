import { DecimalPipe } from '@angular/common';
import { Component, OnDestroy, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';
import {
  DatabaseBackupOverview,
  DatabaseBackupRun,
  DatabaseBackupsService,
} from './database-backups.service';

const dayKeys = [
  'backups.day.sunday', 'backups.day.monday', 'backups.day.tuesday', 'backups.day.wednesday',
  'backups.day.thursday', 'backups.day.friday', 'backups.day.saturday',
];

function dateInputValue(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

@Component({
  selector: 'app-database-backups-page',
  imports: [DecimalPipe, FormsModule, TranslatePipe],
  templateUrl: './database-backups-page.html',
  styleUrl: './database-backups-page.scss',
})
export class DatabaseBackupsPage implements OnInit, OnDestroy {
  private readonly backups = inject(DatabaseBackupsService);
  private readonly auth = inject(AuthService);
  readonly i18n = inject(I18nService);
  readonly overview = signal<DatabaseBackupOverview | null>(null);
  readonly loading = signal(true);
  readonly loadError = signal(false);
  readonly runError = signal(false);
  readonly saving = signal(false);
  readonly saveError = signal(false);
  readonly saved = signal(false);
  readonly startingRun = signal(false);
  readonly downloadingRunId = signal<string | null>(null);
  readonly downloadError = signal(false);
  readonly enabled = signal(false);
  readonly frequency = signal<'daily' | 'weekly'>('daily');
  readonly dayOfWeek = signal(1);
  readonly time = signal('02:00');
  readonly fromDate = signal(dateInputValue(new Date(Date.now() - 29 * 24 * 60 * 60 * 1000)));
  readonly toDate = signal(dateInputValue(new Date()));
  readonly canManage = computed(() => this.auth.hasPermission('backup.manage'));
  readonly activeRun = computed(() => this.overview()?.activeRun ?? null);
  readonly invalidDateRange = computed(() => !!this.fromDate() && !!this.toDate() && this.fromDate() > this.toDate());
  readonly dayOptions = dayKeys.map((key, value) => ({ value, key }));
  private pollTimer: number | null = null;
  private historyFilterTimer: number | null = null;

  ngOnInit(): void { this.load(); }

  ngOnDestroy(): void {
    this.clearPoll();
    this.clearHistoryFilterTimer();
  }

  load(refreshSchedule = true): void {
    this.clearHistoryFilterTimer();
    this.loading.set(true);
    this.loadError.set(false);
    this.backups.getOverview(this.fromDate(), this.toDate()).subscribe({
      next: data => {
        this.overview.set(data);
        if (refreshSchedule) this.applySchedule(data);
        this.loading.set(false);
        if (data.activeRun) this.pollForCompletion();
        else this.clearPoll();
      },
      error: () => { this.loadError.set(true); this.loading.set(false); },
    });
  }

  setScheduleEnabled(value: boolean): void {
    const previousEnabled = this.enabled();
    if (value === previousEnabled || this.saving()) return;
    this.enabled.set(value);
    this.saveSchedule(previousEnabled);
  }

  setFromDate(value: string): void {
    this.fromDate.set(value);
    this.scheduleHistoryReload();
  }

  setToDate(value: string): void {
    this.toDate.set(value);
    this.scheduleHistoryReload();
  }

  setFrequency(value: string): void { this.frequency.set(value === 'weekly' ? 'weekly' : 'daily'); }
  setDayOfWeek(value: string | number): void { this.dayOfWeek.set(Number(value)); }

  saveSchedule(previousEnabled = this.enabled()): void {
    if (!this.canManage() || this.saving()) return;
    this.saving.set(true);
    this.saveError.set(false);
    this.saved.set(false);
    this.backups.updateSchedule({
      enabled: this.enabled(),
      frequency: this.frequency(),
      dayOfWeek: this.frequency() === 'weekly' ? this.dayOfWeek() : null,
      time: this.time(),
    }).subscribe({
      next: schedule => {
        const current = this.overview();
        if (current) this.overview.set({ ...current, schedule });
        this.applySchedule({ schedule });
        this.saved.set(true);
        this.saving.set(false);
      },
      error: () => {
        this.enabled.set(previousEnabled);
        this.saveError.set(true);
        this.saved.set(false);
        this.saving.set(false);
      },
    });
  }

  runNow(): void {
    if (!this.canManage() || this.startingRun() || this.activeRun()) return;
    this.startingRun.set(true);
    this.runError.set(false);
    this.backups.runNow().subscribe({
      next: run => {
        const current = this.overview();
        if (current) this.overview.set({ ...current, activeRun: run, runs: [run, ...current.runs] });
        this.startingRun.set(false);
        this.pollForCompletion();
      },
      error: () => { this.runError.set(true); this.startingRun.set(false); },
    });
  }

  download(run: DatabaseBackupRun): void {
    if (!run.canDownload || this.downloadingRunId()) return;
    this.downloadingRunId.set(run.runId);
    this.downloadError.set(false);
    this.backups.getDownloadUrl(run.runId).subscribe({
      next: result => {
        const link = document.createElement('a');
        link.href = result.url;
        link.rel = 'noopener';
        link.click();
        this.downloadingRunId.set(null);
      },
      error: () => { this.downloadError.set(true); this.downloadingRunId.set(null); },
    });
  }

  statusKey(run: DatabaseBackupRun): string {
    return `backups.status.${run.status}`;
  }

  triggerKey(run: DatabaseBackupRun): string {
    return run.trigger === 'schedule' ? 'backups.trigger.schedule' : 'backups.trigger.manual';
  }

  dayLabel(day: number | null): string {
    return this.i18n.t(dayKeys[day ?? 1] ?? dayKeys[1]);
  }

  formatDate(value: string): string {
    return new Intl.DateTimeFormat(this.locale(), { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'Asia/Ho_Chi_Minh' }).format(new Date(value));
  }

  formatTime(value: string): string {
    return new Intl.DateTimeFormat(this.locale(), { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Ho_Chi_Minh' }).format(new Date(value));
  }

  formatBytes(value: number | null): string {
    if (value === null || value < 0) return '—';
    if (value < 1024) return `${value} B`;
    const units = ['KB', 'MB', 'GB', 'TB'];
    let size = value / 1024;
    let unit = 0;
    while (size >= 1024 && unit < units.length - 1) { size /= 1024; unit++; }
    return `${new Intl.NumberFormat(this.locale(), { maximumFractionDigits: 1 }).format(size)} ${units[unit]}`;
  }

  trackRun(_: number, run: DatabaseBackupRun): string { return run.runId; }

  private applySchedule(data: Pick<DatabaseBackupOverview, 'schedule'>): void {
    this.enabled.set(data.schedule.enabled);
    this.frequency.set(data.schedule.frequency === 'weekly' ? 'weekly' : 'daily');
    this.dayOfWeek.set(data.schedule.dayOfWeek ?? 1);
    this.time.set(data.schedule.time || '02:00');
  }

  private pollForCompletion(): void {
    this.clearPoll();
    this.pollTimer = window.setTimeout(() => this.load(false), 4000);
  }

  private clearPoll(): void {
    if (this.pollTimer !== null) window.clearTimeout(this.pollTimer);
    this.pollTimer = null;
  }

  private scheduleHistoryReload(): void {
    this.clearHistoryFilterTimer();
    if (!this.fromDate() || !this.toDate() || this.invalidDateRange()) return;
    this.historyFilterTimer = window.setTimeout(() => {
      this.historyFilterTimer = null;
      this.load(false);
    }, 250);
  }

  private clearHistoryFilterTimer(): void {
    if (this.historyFilterTimer !== null) window.clearTimeout(this.historyFilterTimer);
    this.historyFilterTimer = null;
  }

  private locale(): string { return this.i18n.currentLang() === 'vi' ? 'vi-VN' : 'en-US'; }
}
