import { HttpClient, HttpHeaders, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, of } from 'rxjs';
import { map, catchError, switchMap } from 'rxjs/operators';
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
export interface WatchHistoryItem extends Partial<LibraryVideo> { videoId: string; channelId: string; channelName: string; channelHandle: string; title: string; thumbnailUrl: string | null; duration: number; watchedSeconds: number; progress: number; activityAt: string; }
export interface VideoDetail extends VideoCard { categoryId: string | null; description: string | null; videoUrl: string; fileSize: number; status: string; moderationStatus: string; moderationReason?: string | null; channelWatermarkUrl?: string | null; languageCode: string | null; ageRestricted: boolean; createdAt: string; tags: string[]; chapters: { startSeconds: number; title: string }[]; stats: VideoStats; viewerState: VideoViewerState | null; }
export interface Rendition { quality: string; width: number; height: number; fileSize: number; url: string; }
export interface Playback { videoId: string; title: string; visibility: string; duration: number; renditions: Rendition[]; resumeAtSeconds: number; progress: number; }
export interface CommentItem { commentId: string; videoId: string; userId: string; displayName: string; parentCommentId: string | null; content: string; status: string; createdAt: string; updatedAt: string; likes: number; dislikes: number; myReaction: 'like' | 'dislike' | null; replyCount: number; }
export interface Category { categoryId: string; name: string; slug: string; description: string | null; }
export interface ViolationType { violationTypeId: string; code: string; name: string; description: string | null; }
export interface CategoryRankingGroup { categoryId: string; categoryName: string; slug: string; videos: VideoCard[]; }
export interface FeaturedCreator { channelId: string; name: string; handle: string; avatarUrl: string | null; subscriberCount: number; verified: boolean; }
export interface ExploreHub {
  rankings: CategoryRankingGroup[];
  creators: FeaturedCreator[];
  trending: VideoCard[];
  topVideos?: VideoCard[];
}

export const DEFAULT_VIOLATION_TYPES: ViolationType[] = [
  { violationTypeId: '00000000-0000-0002-0000-000000000001', code: 'sexual', name: 'Nội dung khiêu dâm', description: 'Hình ảnh, video hoặc nội dung khiêu dâm, không phù hợp thuần phong mỹ tục.' },
  { violationTypeId: '00000000-0000-0002-0000-000000000002', code: 'violent', name: 'Nội dung bạo lực hoặc phản cảm', description: 'Bạo lực, đẫm máu, gây sốc hoặc phản cảm.' },
  { violationTypeId: '00000000-0000-0002-0000-000000000003', code: 'hate', name: 'Nội dung lăng mạ hoặc kích động thù hận', description: 'Xúc phạm danh dự, kỳ thị hoặc kích động thù địch.' },
  { violationTypeId: '00000000-0000-0002-0000-000000000004', code: 'harassment', name: 'Nội dung quấy rối hoặc bắt nạt', description: 'Đe dọa, quấy rối, bắt nạt trực tuyến.' },
  { violationTypeId: '00000000-0000-0002-0000-000000000005', code: 'harmful', name: 'Hành động gây hại hoặc nguy hiểm', description: 'Hành vi khuyến khích nguy hiểm hoặc tự gây hại.' },
  { violationTypeId: '00000000-0000-0002-0000-000000000006', code: 'spam', name: 'Spam hoặc thông tin sai lệch', description: 'Lừa đảo, tin giả, quảng cáo rác hoặc thao túng người xem.' },
  { violationTypeId: '00000000-0000-0002-0000-000000000007', code: 'copyright', name: 'Vi phạm bản quyền', description: 'Sử dụng tác phẩm không có bản quyền hoặc quyền sở hữu hợp pháp.' },
  { violationTypeId: '00000000-0000-0002-0000-000000000008', code: 'other', name: 'Vi phạm khác', description: 'Các hành vi vi phạm điều khoản dịch vụ hoặc tiêu chuẩn cộng đồng khác.' },
];
export interface UploadPreflight {
  allowed: boolean;
  maxUploadSize: number;
  maxDuration: number;
  maxQuality: string;
  storageLimit: number;
  storageUsed: number;
  storageRemaining: number;
}

export interface ChannelStrikeStatus {
  channelId: string;
  activeStrikesCount: number;
  hasWarning: boolean;
  isSuspended: boolean;
  uploadRestrictedUntil: string | null;
  uploadRestrictionReason?: string | null;
  appealEligible?: boolean;
  strikes: ChannelStrike[];
}

export interface ChannelStrike {
  strikeId: string;
  channelId: string;
  strikeNumber: number;
  severity: string;
  policyCode: string | null;
  reason: string;
  status: string;
  expiresAt: string;
  createdAt: string;
}

export interface CreateAppealPayload {
  targetType: 'video' | 'channel' | 'comment' | 'strike';
  targetId: string;
  reason: string;
  evidenceUrl?: string;
  evidenceNote?: string;
  moderationCaseId?: string;
  strikeId?: string;
}

export interface AppealItem {
  appealId: string;
  userId: string;
  targetType: string;
  targetId: string;
  targetTitle: string | null;
  appealNumber: number;
  reviewerName?: string | null;
  reason: string;
  status: string;
  reviewNote: string | null;
  evidenceUrl: string | null;
  evidenceNote?: string | null;
  createdAt: string;
  resolvedAt: string | null;
}

@Injectable({ providedIn: 'root' })
export class ContentService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);
  private get base() { return this.config.apiBaseUrl; }

  feed(kind: 'home' | 'explore' | 'subscriptions', page = 1, pageSize = 20, categoryId?: string, tag?: string, sort?: string) {
    let params = new HttpParams().set('page', page).set('pageSize', pageSize);
    if (sort) params = params.set('sort', sort);
    if (categoryId) params = params.set('categoryId', categoryId);
    if (tag) params = params.set('tag', tag);
    return this.http.get<PageResult<VideoCard>>(`${this.base}/feed/${kind}`, { params });
  }
  search(opts: { q?: string; categoryId?: string; tag?: string; channelId?: string; dateRange?: string; duration?: string; sort?: string; page?: number; pageSize?: number }) {
    let params = new HttpParams()
      .set('page', opts.page ?? 1)
      .set('pageSize', opts.pageSize ?? 20);
    if (opts.q) params = params.set('q', opts.q);
    if (opts.sort) params = params.set('sort', opts.sort);
    if (opts.categoryId) params = params.set('categoryId', opts.categoryId);
    if (opts.tag) params = params.set('tag', opts.tag);
    if (opts.channelId) params = params.set('channelId', opts.channelId);
    if (opts.dateRange) params = params.set('dateRange', opts.dateRange);
    if (opts.duration) params = params.set('duration', opts.duration);
    return this.http.get<PageResult<VideoCard>>(`${this.base}/videos/search`, { params });
  }
  history(page = 1, pageSize = 20) { return this.http.get<PageResult<WatchHistoryItem>>(`${this.base}/library/history`, { params: { page, pageSize } }); }
  liked(rating: number | null = null, page = 1, pageSize = 20) {
    let params = new HttpParams().set('page', page).set('pageSize', pageSize);
    if (rating !== null) params = params.set('rating', rating);
    return this.http.get<PageResult<LibraryVideo>>(`${this.base}/library/liked`, { params });
  }
  categories() { return this.http.get<Category[]>(`${this.base}/categories`); }
  exploreHub() { return this.http.get<ExploreHub>(`${this.base}/feed/explore-hub`); }
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
  violationTypes(): Observable<ViolationType[]> {
    return this.http.get<ViolationType[]>(`${this.base}/violation-types`).pipe(
      map(types => (types && types.length > 0 ? types : DEFAULT_VIOLATION_TYPES)),
      catchError(() => of(DEFAULT_VIOLATION_TYPES))
    );
  }
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
  reportComment(commentId: string, violationTypeId: string, description: string) {
    return this.http.post(`${this.base}/reports`, { targetType: 'comment', targetId: commentId, violationTypeId, description }).pipe(
      catchError(() => this.http.post(`${this.base}/comments/${commentId}/report`, { violationTypeId, description }))
    );
  }
  reportVideo(videoId: string, violationTypeId: string, description: string) {
    return this.http.post(`${this.base}/videos/${videoId}/report`, { violationTypeId, description }).pipe(
      catchError(() => this.http.post(`${this.base}/reports`, { targetType: 'video', targetId: videoId, violationTypeId, description }))
    );
  }
  reportChannel(channelId: string, violationTypeId: string, description: string) {
    return this.http.post(`${this.base}/channels/${channelId}/report`, { violationTypeId, description }).pipe(
      catchError(() => this.http.post(`${this.base}/reports`, { targetType: 'channel', targetId: channelId, violationTypeId, description }))
    );
  }
  reportContent(targetType: 'video' | 'comment' | 'channel', targetId: string, violationTypeId: string, description: string, idempotencyKey?: string) {
    const headers = idempotencyKey ? new HttpHeaders({ 'Idempotency-Key': idempotencyKey }) : undefined;
    return this.http.post(`${this.base}/reports`, { targetType, targetId, violationTypeId, description }, { headers });
  }
  getChannelStrikes(channelId: string) { return this.http.get<ChannelStrikeStatus>(`${this.base}/channels/${channelId}/strikes`); }
  getAppealEvidence(appealId: string) { return this.http.get(`${this.base}/appeals/${appealId}/evidence`, { responseType: 'blob' }); }
  createAppeal(request: CreateAppealPayload, evidence?: File | null) {
    return this.http.post<AppealItem>(`${this.base}/appeals`, request).pipe(
      switchMap(appeal => evidence
        ? this.uploadAppealEvidence(appeal.appealId, evidence).pipe(map(() => appeal))
        : of(appeal))
    );
  }
  uploadAppealEvidence(appealId: string, file: File) {
    const form = new FormData();
    form.append('file', file);
    return this.http.post<{ appealId: string; evidenceUrl: string }>(`${this.base}/appeals/${appealId}/evidence`, form);
  }
  getMyAppeals() { return this.http.get<AppealItem[]>(`${this.base}/appeals/my`); }
  progress(videoId: string, watchedSeconds: number) { return this.http.put(`${this.base}/videos/${videoId}/watch-progress`, { watchedSeconds, saveHistory: true }); }
  share(videoId: string) { return this.http.post<{ url: string; shareCount: number }>(`${this.base}/videos/${videoId}/share`, { method: 'copy_link' }); }
  downloadOptions(videoId: string) { return this.http.get<Rendition[]>(`${this.base}/videos/${videoId}/download-options`); }
  createDownload(videoId: string, quality: string) { return this.http.post<{ videoDownloadId: string; videoId: string; title: string; quality: string; fileUrl: string; fileSize: number; status: string }>(`${this.base}/videos/${videoId}/downloads`, { quality }); }
  preflight(request: { channelId: string; fileSize: number; duration: number; contentType: string; sourceQuality: string }) {
    return this.http.post<UploadPreflight>(`${this.base}/videos/upload-preflight`, request);
  }
  upload(data: FormData, idempotencyKey?: string) {
    return this.http.post<VideoDetail>(`${this.base}/videos`, data, {
      reportProgress: true, observe: 'events', headers: idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : undefined
    });
  }
  publish(videoId: string) { return this.http.post<VideoDetail>(`${this.base}/videos/${videoId}/publish`, {}); }
  update(videoId: string, data: { visibility?: string; title?: string; description?: string; categoryId?: string | null; clearCategory?: boolean }) {
    return this.http.patch<VideoDetail>(`${this.base}/videos/${videoId}`, data);
  }
  updateThumbnail(videoId: string, file: File | null, generate = false) {
    const data = new FormData();
    data.append('Generate', String(generate));
    if (file) data.append('Thumbnail', file, file.name);
    return this.http.post<VideoDetail>(`${this.base}/videos/${videoId}/thumbnail`, data);
  }
}
