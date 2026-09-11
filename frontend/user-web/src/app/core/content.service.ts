import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { RuntimeConfig } from './runtime-config';

export interface PageResult<T> { items: T[]; page: number; pageSize: number; total: number; }
export interface VideoStats { views: number; likes: number; dislikes: number; comments: number; averageRating: number | null; ratingCount: number; shares: number; }
export interface VideoViewerState { reaction: 'like' | 'dislike' | null; rating: number | null; resumeAtSeconds: number; progress: number; }
export interface VideoCard { videoId: string; channelId: string; channelName: string; channelHandle: string; title: string; thumbnailUrl: string | null; duration: number; visibility: string; publishedAt: string | null; views: number; }
export interface LibraryVideo extends VideoCard {
  likes: number;
  dislikes: number;
  averageRating: number | null;
  ratingCount: number;
  myRating: number | null;
  watchedSeconds: number;
  progress: number;
  activityAt: string;
}
export interface VideoDetail extends VideoCard { categoryId: string | null; description: string | null; videoUrl: string; fileSize: number; status: string; moderationStatus: string; languageCode: string | null; ageRestricted: boolean; createdAt: string; tags: string[]; chapters: { startSeconds: number; title: string }[]; stats: VideoStats; viewerState: VideoViewerState | null; }
export interface Rendition { quality: string; width: number; height: number; fileSize: number; url: string; }
export interface Playback { videoId: string; title: string; visibility: string; duration: number; renditions: Rendition[]; resumeAtSeconds: number; progress: number; }
export interface CommentItem { commentId: string; videoId: string; userId: string; displayName: string; parentCommentId: string | null; content: string; status: string; createdAt: string; updatedAt: string; likes: number; dislikes: number; myReaction: 'like' | 'dislike' | null; replyCount: number; }
export interface Category { categoryId: string; name: string; slug: string; description: string | null; }
export interface ViolationType { violationTypeId: string; code: string; name: string; description: string | null; }
export interface UploadPreflight {
  allowed: boolean;
  maxUploadSize: number;
  maxDuration: number;
  maxQuality: string;
  storageLimit: number;
  storageUsed: number;
  storageRemaining: number;
}

@Injectable({ providedIn: 'root' })
export class ContentService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);
  private get base() { return this.config.apiBaseUrl; }

  feed(kind: 'home' | 'explore', page = 1, pageSize = 20) { return this.http.get<PageResult<VideoCard>>(`${this.base}/feed/${kind}`, { params: { page, pageSize } }); }
  history(page = 1, pageSize = 20) { return this.http.get<PageResult<LibraryVideo>>(`${this.base}/library/history`, { params: { page, pageSize } }); }
  liked(rating: number | null = null, page = 1, pageSize = 20) {
    let params = new HttpParams().set('page', page).set('pageSize', pageSize);
    if (rating !== null) params = params.set('rating', rating);
    return this.http.get<PageResult<LibraryVideo>>(`${this.base}/library/liked`, { params });
  }
  categories() { return this.http.get<Category[]>(`${this.base}/categories`); }
  detail(id: string) { return this.http.get<VideoDetail>(`${this.base}/videos/${id}`); }
  playback(id: string) { return this.http.get<Playback>(`${this.base}/videos/${id}/playback`); }
  managed(channelId: string, page = 1, pageSize = 20, search = '') {
    let params = new HttpParams().set('channelId', channelId).set('page', page).set('pageSize', pageSize);
    if (search) params = params.set('search', search);
    return this.http.get<PageResult<VideoDetail>>(`${this.base}/videos/manage`, { params });
  }
  comments(videoId: string, page = 1, pageSize = 20, sort = 'newest') { return this.http.get<PageResult<CommentItem>>(`${this.base}/videos/${videoId}/comments`, { params: { page, pageSize, sort } }); }
  replies(commentId: string, page = 1, pageSize = 20) { return this.http.get<PageResult<CommentItem>>(`${this.base}/comments/${commentId}/replies`, { params: { page, pageSize } }); }
  managedComments(channelId: string, status = '', page = 1, pageSize = 50) { return this.http.get<PageResult<CommentItem>>(`${this.base}/channels/${channelId}/comments/manage`, { params: { status, page, pageSize } }); }
  violationTypes() { return this.http.get<ViolationType[]>(`${this.base}/violation-types`); }
  createComment(videoId: string, content: string, parentCommentId: string | null = null) { return this.http.post<CommentItem>(`${this.base}/videos/${videoId}/comments`, { content, parentCommentId }); }
  reactVideo(videoId: string, type: 'like' | 'dislike' | null): Observable<{ myReaction: string | null; likes: number; dislikes: number }> { return type ? this.http.put<{ myReaction: string | null; likes: number; dislikes: number }>(`${this.base}/videos/${videoId}/reaction`, { type }) : this.http.delete<{ myReaction: string | null; likes: number; dislikes: number }>(`${this.base}/videos/${videoId}/reaction`); }
  rate(videoId: string, score: number | null) {
    return score !== null
      ? this.http.put<{ myRating: number | null; average: number | null; count: number }>(`${this.base}/videos/${videoId}/rating`, { score })
      : this.http.delete<{ myRating: number | null; average: number | null; count: number }>(`${this.base}/videos/${videoId}/rating`);
  }
  reactComment(commentId: string, type: 'like' | 'dislike' | null): Observable<{ myReaction: string | null; likes: number; dislikes: number }> { return type ? this.http.put<{ myReaction: string | null; likes: number; dislikes: number }>(`${this.base}/comments/${commentId}/reaction`, { type }) : this.http.delete<{ myReaction: string | null; likes: number; dislikes: number }>(`${this.base}/comments/${commentId}/reaction`); }
  hideComment(commentId: string, hidden: boolean, reason = '') { return this.http.patch<CommentItem>(`${this.base}/comments/${commentId}/visibility`, { hidden, reason }); }
  deleteComment(commentId: string) { return this.http.delete<void>(`${this.base}/comments/${commentId}`); }
  reportComment(commentId: string, violationTypeId: string, description: string) { return this.http.post(`${this.base}/comments/${commentId}/report`, { violationTypeId, description }); }
  progress(videoId: string, watchedSeconds: number) { return this.http.put(`${this.base}/videos/${videoId}/watch-progress`, { watchedSeconds, saveHistory: true }); }
  share(videoId: string) { return this.http.post<{ url: string; shareCount: number }>(`${this.base}/videos/${videoId}/share`, { method: 'copy_link' }); }
  preflight(request: { channelId: string; fileSize: number; duration: number; contentType: string; sourceQuality: string }) {
    return this.http.post<UploadPreflight>(`${this.base}/videos/upload-preflight`, request);
  }
  upload(data: FormData) { return this.http.post<VideoDetail>(`${this.base}/videos`, data, { reportProgress: true, observe: 'events' }); }
  publish(videoId: string) { return this.http.post<VideoDetail>(`${this.base}/videos/${videoId}/publish`, {}); }
}
