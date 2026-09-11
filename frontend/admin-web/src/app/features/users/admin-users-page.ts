import { Component, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { I18nService } from '../../core/i18n.service';
import { TranslatePipe } from '../../core/translate.pipe';

export interface AdminUserItem {
  id: string;
  displayName: string;
  email: string;
  username: string;
  role: 'SUPER_ADMIN' | 'ADMIN' | 'MODERATOR' | 'CREATOR' | 'USER';
  status: 'ACTIVE' | 'BANNED';
  emailVerified: boolean;
  createdAt: string;
}

@Component({
  selector: 'app-admin-users-page',
  imports: [CommonModule, FormsModule, TranslatePipe],
  templateUrl: './admin-users-page.html',
  styleUrl: './admin-users-page.scss',
})
export class AdminUsersPage {
  readonly i18n = inject(I18nService);

  readonly searchQuery = signal('');
  readonly selectedRole = signal('ALL');
  readonly selectedStatus = signal('ALL');

  readonly users = signal<AdminUserItem[]>([
    {
      id: 'usr_01',
      displayName: 'Nguyễn Duy Linh',
      email: 'linh.duy@hutube.vn',
      username: 'duylinh0212',
      role: 'SUPER_ADMIN',
      status: 'ACTIVE',
      emailVerified: true,
      createdAt: '2026-01-15'
    },
    {
      id: 'usr_02',
      displayName: 'Trần Minh Tâm',
      email: 'tam.tran@hutube.vn',
      username: 'minhtam_mod',
      role: 'MODERATOR',
      status: 'ACTIVE',
      emailVerified: true,
      createdAt: '2026-02-01'
    },
    {
      id: 'usr_03',
      displayName: 'Nắng Lang Thang',
      email: 'nanglangthang@gmail.com',
      username: 'nangcreator',
      role: 'CREATOR',
      status: 'ACTIVE',
      emailVerified: true,
      createdAt: '2026-02-20'
    },
    {
      id: 'usr_04',
      displayName: 'Lê Hoàng Nam',
      email: 'hoangnam99@gmail.com',
      username: 'nam_viewer',
      role: 'USER',
      status: 'ACTIVE',
      emailVerified: false,
      createdAt: '2026-03-05'
    },
    {
      id: 'usr_05',
      displayName: 'Spammer Account',
      email: 'bot_spam@fakebox.com',
      username: 'bot_bot_99',
      role: 'USER',
      status: 'BANNED',
      emailVerified: false,
      createdAt: '2026-03-10'
    }
  ]);

  readonly filteredUsers = computed(() => {
    const q = this.searchQuery().trim().toLowerCase();
    const role = this.selectedRole();
    const status = this.selectedStatus();

    return this.users().filter(u => {
      const matchQuery = !q ||
        u.displayName.toLowerCase().includes(q) ||
        u.email.toLowerCase().includes(q) ||
        u.username.toLowerCase().includes(q);

      const matchRole = role === 'ALL' || u.role === role;
      const matchStatus = status === 'ALL' || u.status === status;

      return matchQuery && matchRole && matchStatus;
    });
  });

  toggleBan(user: AdminUserItem) {
    this.users.update(list =>
      list.map(u => u.id === user.id ? { ...u, status: u.status === 'ACTIVE' ? 'BANNED' : 'ACTIVE' } : u)
    );
  }
}
