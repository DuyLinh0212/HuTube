export type CfSeedVisibility = 'public' | 'unlisted' | 'private';
export type CfSeedAccountMode = 'new' | 'existing';
export type CfSeedRunState = 'idle' | 'provisioning' | 'running' | 'completed' | 'completed_with_errors' | 'cancelled' | 'failed';

export interface CfSeedAccountInput {
  username: string;
  displayName: string;
  channelName?: string;
}

export interface CfSeedAccount {
  userId: string;
  channelId: string;
  username: string;
  displayName: string;
  channelName: string;
  channelHandle: string;
}

export interface CfSeedProvisionResponse {
  batchId: string;
  accounts: CfSeedAccount[];
}

export interface CfSeedVideoResponse {
  videoId: string;
  userId: string;
  channelId: string;
  title: string;
  status: string;
  visibility: CfSeedVisibility;
  fileSize: number;
}

export interface CfSeedFileEntry {
  name: string;
  file: File;
  handle?: FileSystemFileHandle;
}

export interface CfSeedFolderSelection {
  name: string;
  files: CfSeedFileEntry[];
  ignoredFileCount: number;
  totalBytes: number;
  directoryHandle?: FileSystemDirectoryHandle;
  canDeleteSources: boolean;
}

export type CfSeedQualityScanStatus = 'idle' | 'scanning' | 'ready' | 'error';

export interface CfSeedQualityScan {
  status: CfSeedQualityScanStatus;
  processedFiles: number;
  totalFiles: number;
  minimumSourceHeight?: number;
  maxCommonQuality?: string;
  error?: string;
}

export interface CfSeedRunConfig {
  accountMode: CfSeedAccountMode;
  categoryId: string;
  categoryName: string;
  userCount: number;
  existingAccounts: CfSeedAccount[];
  maxVideosPerChannel: number;
  maxQuality: string;
  visibility: CfSeedVisibility;
}

export interface CfSeedMetrics {
  usersCreated: number;
  channelsCreated: number;
  targetVideos: number;
  processedVideos: number;
  uploadedVideos: number;
  failedVideos: number;
  deletedSources: number;
  uploadedBytes: number;
}

export interface CfSeedVideoResult {
  sequence: number;
  fileName: string;
  username: string;
  channelId: string;
  videoId?: string;
  uploaded: boolean;
  sourceDeleted: boolean;
  sizeBytes: number;
  error?: string;
}

export interface CfSeedRunHistory {
  schemaVersion: 1;
  runId: string;
  batchId?: string;
  startedAt: string;
  completedAt: string;
  status: CfSeedRunState;
  sourceFolder: string;
  categoryId: string;
  categoryName: string;
  accountMode?: CfSeedAccountMode;
  userCount: number;
  channelCount: number;
  maxVideosPerChannel: number;
  selectedVideoCount: number;
  targetVideoCount: number;
  maxQuality: string;
  visibility: CfSeedVisibility;
  canDeleteSources: boolean;
  metrics: CfSeedMetrics;
  results: CfSeedVideoResult[];
  logs: string[];
  error?: string;
}

export const EMPTY_CF_SEED_METRICS: CfSeedMetrics = {
  usersCreated: 0,
  channelsCreated: 0,
  targetVideos: 0,
  processedVideos: 0,
  uploadedVideos: 0,
  failedVideos: 0,
  deletedSources: 0,
  uploadedBytes: 0,
};

export const EMPTY_CF_SEED_QUALITY_SCAN: CfSeedQualityScan = {
  status: 'idle',
  processedFiles: 0,
  totalFiles: 0,
};
