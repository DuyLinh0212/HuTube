import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { RuntimeConfig } from '../../core/runtime-config';

export type TopicStatus = 'active' | 'inactive';

export interface AdminTopic {
  categoryId: string;
  name: string;
  slug: string;
  description: string | null;
  status: TopicStatus;
  videoCount: number;
  createdAt: string;
  updatedAt: string;
}

export interface AdminTag {
  tagId: string;
  name: string;
  videoCount: number;
  createdAt: string;
}

export interface TopicRequest {
  name: string;
  slug: string | null;
  description: string | null;
  status: TopicStatus;
}

@Injectable({ providedIn: 'root' })
export class AdminTopicsService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);
  private readonly baseUrl = `${this.config.apiBaseUrl}/admin`;

  getTopics(status: 'all' | TopicStatus = 'all'): Observable<AdminTopic[]> {
    let params = new HttpParams();
    if (status !== 'all') params = params.set('status', status);
    return this.http.get<AdminTopic[]>(`${this.baseUrl}/topics`, { params });
  }

  createTopic(request: TopicRequest): Observable<AdminTopic> {
    return this.http.post<AdminTopic>(`${this.baseUrl}/topics`, request);
  }

  updateTopic(categoryId: string, request: TopicRequest): Observable<AdminTopic> {
    return this.http.put<AdminTopic>(`${this.baseUrl}/topics/${categoryId}`, request);
  }

  archiveTopic(categoryId: string): Observable<void> {
    return this.http.post<void>(`${this.baseUrl}/topics/${categoryId}/archive`, {});
  }

  getTags(search = ''): Observable<AdminTag[]> {
    let params = new HttpParams();
    if (search.trim()) params = params.set('search', search.trim());
    return this.http.get<AdminTag[]>(`${this.baseUrl}/tags`, { params });
  }

  createTag(name: string): Observable<AdminTag> {
    return this.http.post<AdminTag>(`${this.baseUrl}/tags`, { name });
  }

  updateTag(tagId: string, name: string): Observable<AdminTag> {
    return this.http.put<AdminTag>(`${this.baseUrl}/tags/${tagId}`, { name });
  }

  deleteTag(tagId: string): Observable<void> {
    return this.http.delete<void>(`${this.baseUrl}/tags/${tagId}`);
  }
}
