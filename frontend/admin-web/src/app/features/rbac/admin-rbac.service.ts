import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { RuntimeConfig } from '../../core/runtime-config';

export interface AdminPermission {
  permissionId: string;
  code: string;
  name: string;
  description: string | null;
  status: string;
}

export interface AdminRole {
  roleId: string;
  code: string;
  name: string;
  description: string | null;
  permissions: string[];
}

export interface SaveRoleRequest {
  name: string;
  description: string | null;
  permissionCodes: string[];
  reason: string;
}

export interface CreateRoleRequest extends SaveRoleRequest {
  code: string;
}

@Injectable({ providedIn: 'root' })
export class AdminRbacService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);

  roles() {
    return this.http.get<AdminRole[]>(this.config.apiBaseUrl + '/admin/roles');
  }

  permissions() {
    return this.http.get<AdminPermission[]>(this.config.apiBaseUrl + '/admin/permissions');
  }

  createRole(request: CreateRoleRequest) {
    return this.http.post<AdminRole>(this.config.apiBaseUrl + '/admin/roles', request);
  }

  updateRole(roleId: string, request: SaveRoleRequest) {
    return this.http.put<AdminRole>(this.config.apiBaseUrl + '/admin/roles/' + encodeURIComponent(roleId), request);
  }
}
