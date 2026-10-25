import { Component, EventEmitter, Input, Output, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { FormsModule } from '@angular/forms';
import { Observable } from 'rxjs';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { DestroyRef } from '@angular/core';
import { ConfirmDialogComponent } from '@dalitu/ui/confirm-dialog.component';
import { ResultNoticeComponent } from '@dalitu/ui/result-notice.component';
import { AuthService, errorMessage } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { RuntimeConfig } from '../../core/runtime-config';
import { TranslatePipe } from '../../core/translate.pipe';

interface TargetStrike { strikeId: string; reason: string; strikeNumber: number; }

@Component({
  selector: 'app-admin-target-actions',
  standalone: true,
  imports: [FormsModule, ConfirmDialogComponent, ResultNoticeComponent, TranslatePipe],
  template: `
    <div class="actions">
      @if (targetType === 'channel' && auth.hasPermission('channel.edit')) {
        <button type="button" data-testid="channel-edit" (click)="open('edit')">{{ 'targetActions.edit' | translate }}</button>
      }
      @if (auth.hasPermission(targetType + '.strike')) {
        <button type="button" [attr.data-testid]="targetType + '-strike'" (click)="open('strike')">{{ 'targetActions.strike' | translate }}</button>
      }
      @if (targetType === 'channel' && auth.hasPermission('channel.remove_strike')) {
        <button type="button" data-testid="channel-remove-strike" (click)="open('revoke')">{{ 'targetActions.revoke' | translate }}</button>
      }
    </div>
    <app-result-notice tone="success" [message]="notice()" />
    @if (action(); as kind) {
      <app-confirm-dialog [title]="('targetActions.' + (kind === 'edit' ? 'edit' : kind === 'strike' ? 'strike' : 'revoke')) | translate"
        [description]="name" [confirmLabel]="'targetActions.confirm' | translate" initialFocus="field"
        [busy]="busy()" [confirmDisabled]="!valid()" (confirmed)="submit()" (cancelled)="close()">
        <app-result-notice tone="error" [message]="error()" />
        @if (kind === 'edit') {
          <label>{{ 'targetActions.name' | translate }}<input data-testid="target-name" maxlength="100" [ngModel]="draftName" (ngModelChange)="draftName = $event" [disabled]="busy()" /></label>
          <label>{{ 'targetActions.description' | translate }}<textarea data-testid="target-description" rows="3" maxlength="5000" [ngModel]="draftDescription" (ngModelChange)="draftDescription = $event" [disabled]="busy()"></textarea></label>
          <label>{{ 'targetActions.email' | translate }}<input data-testid="target-email" type="email" maxlength="255" [ngModel]="draftEmail" (ngModelChange)="draftEmail = $event" [disabled]="busy()" /></label>
        }
        @if (kind === 'strike') {
          <p class="hint">{{ 'targetActions.strikeHint' | translate }}</p>
          <label>{{ 'targetActions.severity' | translate }}<select data-testid="target-severity" [(ngModel)]="severity" [disabled]="busy()">
            @for (level of ['low', 'medium', 'high', 'critical']; track level) { <option [value]="level">{{ ('targetActions.' + level) | translate }}</option> }
          </select></label>
        }
        @if (kind === 'revoke') {
          <label>{{ 'targetActions.selectStrike' | translate }}<select data-testid="target-strike-id" [(ngModel)]="strikeId" [disabled]="busy() || loading()">
            <option value="">{{ (loading() ? 'targetActions.loading' : 'targetActions.choose') | translate }}</option>
            @for (strike of strikes(); track strike.strikeId) { <option [value]="strike.strikeId">#{{ strike.strikeNumber }} — {{ strike.reason }}</option> }
          </select></label>
          @if (!loading() && !strikes().length) { <p>{{ 'targetActions.noStrikes' | translate }}</p> }
        }
        <label>{{ 'targetActions.reason' | translate }}<textarea data-testid="target-reason" rows="3" maxlength="300" [ngModel]="reason" (ngModelChange)="reason = $event" [disabled]="busy()"></textarea></label>
      </app-confirm-dialog>
    }
  `,
  styles: [`
    :host { display: block; } .actions { display: flex; flex-wrap: wrap; gap: 8px; margin: 12px 0; }
    button { padding: 9px 12px; border: 1px solid var(--line); border-radius: 8px; background: var(--surface); color: var(--ink); cursor: pointer; font: inherit; }
    label { display: grid; gap: 6px; margin: 12px 0; color: var(--ink); font-weight: 600; }
    input, textarea, select { width: 100%; box-sizing: border-box; font: inherit; color: var(--ink); background: var(--surface); border: 1px solid var(--line); border-radius: 8px; padding: 10px; }
    textarea { resize: vertical; } .hint { color: var(--muted); line-height: 1.5; }
  `]
})
export class AdminTargetActionsComponent {
  readonly auth = inject(AuthService);
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);
  private readonly i18n = inject(I18nService);
  private readonly destroyRef = inject(DestroyRef);
  @Input({required: true}) targetType: 'channel' | 'video' = 'channel';
  @Input({required: true}) targetId = '';
  @Input() name = '';
  @Input() description: string | null = null;
  @Input() contactEmail: string | null = null;
  @Output() changed = new EventEmitter<void>();
  readonly action = signal<'edit' | 'strike' | 'revoke' | null>(null);
  readonly busy = signal(false);
  readonly loading = signal(false);
  readonly strikes = signal<TargetStrike[]>([]);
  readonly error = signal('');
  readonly notice = signal('');
  draftName = ''; draftDescription = ''; draftEmail = ''; reason = ''; severity = 'high'; strikeId = '';
  private generation = 0;
  private get base() { return this.config.apiBaseUrl + '/admin/' + this.targetType + 's/' + this.targetId; }
  private permission(kind: 'edit' | 'strike' | 'revoke') {
    return kind === 'revoke' ? 'channel.remove_strike' : this.targetType + '.' + kind;
  }
  open(kind: 'edit' | 'strike' | 'revoke') {
    if (this.busy() || !this.auth.hasPermission(this.permission(kind))) return;
    this.reason = ''; this.error.set(''); this.notice.set(''); this.strikeId = ''; this.strikes.set([]);
    this.draftName = this.name; this.draftDescription = this.description ?? ''; this.draftEmail = this.contactEmail ?? '';
    this.action.set(kind);
    const generation = ++this.generation;
    if (kind === 'revoke') {
      this.loading.set(true);
      this.http.get<TargetStrike[]>(this.base + '/strikes').pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
        next: rows => { if (generation === this.generation) { this.strikes.set(rows); this.loading.set(false); } },
        error: error => { if (generation === this.generation) { this.loading.set(false); this.error.set(errorMessage(error, this.i18n)); } }
      });
    } else this.loading.set(false);
  }
  close() { if (!this.busy()) { ++this.generation; this.action.set(null); } }
  valid() {
    return this.reason.trim().length >= 3 && this.reason.trim().length <= 300 && !this.loading()
      && (this.action() !== 'edit' || !!this.draftName.trim())
      && (this.action() !== 'revoke' || this.strikes().some(s => s.strikeId === this.strikeId));
  }
  submit() {
    const kind = this.action();
    if (!kind || this.busy() || !this.valid() || !this.auth.hasPermission(this.permission(kind))) return;
    const base = this.base;
    const reason = this.reason.trim();
    const request: Observable<unknown> = kind === 'edit'
      ? this.http.put<void>(base + '/metadata', {name: this.draftName.trim(), description: this.draftDescription, contactEmail: this.draftEmail, reason})
      : kind === 'strike'
        ? this.http.post(base + '/strikes', {severity: this.severity, reason})
        : this.http.post(base + '/strikes/' + this.strikeId + '/revoke', {reason});
    this.busy.set(true); this.error.set('');
    request.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => { this.busy.set(false); this.action.set(null); this.notice.set(this.i18n.t('targetActions.success')); this.changed.emit(); },
      error: error => { this.busy.set(false); this.error.set(errorMessage(error, this.i18n)); }
    });
  }
}
