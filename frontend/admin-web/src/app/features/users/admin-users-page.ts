import { Component, signal } from '@angular/core';

type UsersTab = 'users' | 'roles';

@Component({
  selector: 'app-admin-users-page',
  templateUrl: './admin-users-page.html',
  styleUrl: './admin-users-page.scss',
})
export class AdminUsersPage {
  readonly tab = signal<UsersTab>('users');
  setTab(tab: UsersTab) { this.tab.set(tab); }
}
