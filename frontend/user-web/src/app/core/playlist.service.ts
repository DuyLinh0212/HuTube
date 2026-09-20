import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { RuntimeConfig } from './runtime-config';

export interface PlaylistItem {
  playlistVideoId: string;
  videoId: string;
  position: number;
  title: string | null;
  thumbnailUrl: string | null;
  duration: number;
  visibility: string | null;
  status: string | null;
  moderationStatus: string | null;
  available: boolean;
  unavailableReason: string | null;
}

export interface Playlist {
  playlistId: string;
  userId: string;
  name: string;
  description: string | null;
  visibility: string;
  playlistType: string;
  createdAt: string;
  updatedAt: string;
  items: PlaylistItem[];
}

export interface PlaylistSummary {
  playlistId: string;
  userId: string;
  name: string;
  description: string | null;
  visibility: string;
  playlistType: string;
  itemCount: number;
  updatedAt: string;
}

@Injectable({ providedIn: 'root' })
export class PlaylistService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(RuntimeConfig);
  private get base() { return this.config.apiBaseUrl + '/playlists'; }

  mine() { return this.http.get<PlaylistSummary[]>(this.base); }
  publicByChannel(channelId: string) { return this.http.get<PlaylistSummary[]>(this.base + '/channel/' + channelId); }
  channelMine(channelId: string) { return this.http.get<PlaylistSummary[]>(this.base + '/channel/' + channelId + '/mine'); }
  get(id: string) { return this.http.get<Playlist>(this.base + '/' + id); }
  create(name: string, description: string, visibility: string, playlistType = 'personal') {
    return this.http.post<Playlist>(this.base, { name, description, visibility, playlistType });
  }
  update(id: string, name: string, description: string, visibility: string) {
    return this.http.patch<Playlist>(this.base + '/' + id, { name, description, visibility });
  }
  remove(id: string) { return this.http.delete<void>(this.base + '/' + id); }
  addVideo(id: string, videoId: string) {
    return this.http.post<Playlist>(this.base + '/' + id + '/videos', { videoId });
  }
  saveVideo(videoId: string) { return this.http.post<Playlist>(this.base + '/save', { videoId }); }
  removeVideo(id: string, videoId: string) {
    return this.http.delete<void>(this.base + '/' + id + '/videos/' + videoId);
  }
  reorder(id: string, videoIds: string[]) {
    return this.http.put<Playlist>(this.base + '/' + id + '/order', { videoIds });
  }
}
