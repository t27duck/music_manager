import { invoke } from '@tauri-apps/api/core';

export interface Track {
  id: number;
  path: string;
  dir: string;
  filename: string;
  title: string | null;
  artist: string | null;
  album_artist: string | null;
  album: string | null;
  genre: string | null;
  composer: string | null;
  comment: string | null;
  year: number | null;
  track: number | null;
  track_total: number | null;
  disc: number | null;
  disc_total: number | null;
  has_art: boolean;
  duration_ms: number | null;
  bitrate: number | null;
  size: number;
  error: string | null;
}

export interface Config {
  library_path: string | null;
  templates: string[];
}

export interface Status {
  library_path: string | null;
  scanning: boolean;
  count: number;
}

export interface FilterRow {
  field: string;
  op: string;
  value: string;
}

export interface Query {
  search: string;
  filters: FilterRow[];
  sort: string | null;
  desc: boolean;
}

export type FieldEdit<T> = { op: 'set'; value: T } | { op: 'clear' };

export type TextField = 'title' | 'artist' | 'album_artist' | 'album' | 'genre' | 'composer' | 'comment';
export type NumberField = 'year' | 'track' | 'track_total' | 'disc' | 'disc_total';
export type EditField = TextField | NumberField;

export type TagEdits = Partial<Record<TextField, FieldEdit<string>>> &
  Partial<Record<NumberField, FieldEdit<number>>> & { art?: FieldEdit<string> };

export interface WriteResult {
  updated: number;
  failed: WriteFailure[];
}

export interface WriteFailure {
  id: number;
  /** Relative to the library; empty if the file is no longer in the index. */
  path: string;
  message: string;
}

export interface PlanItem {
  id: number;
  from: string;
  to: string;
  status: 'move' | 'unchanged' | 'conflict' | 'error';
  message: string | null;
}

export interface ApplyResult {
  moved: number;
  skipped: number;
  failed: [string, string][];
  removed_dirs: number;
}

export interface ScanSummary {
  total: number;
  added_or_updated: number;
  removed: number;
}

export interface Progress {
  kind: 'scan' | 'write' | 'reorganize';
  done: number;
  total: number;
}

export interface PlayerStatus {
  track_id: number | null;
  playing: boolean;
  position_ms: number;
  duration_ms: number | null;
  error: string | null;
}

export interface TokenInfo {
  token: string;
  description: string;
}

export const api = {
  getConfig: () => invoke<Config>('get_config'),
  status: () => invoke<Status>('status'),
  setLibraryPath: (path: string) => invoke<Config>('set_library_path', { path }),
  rescan: () => invoke<void>('rescan'),
  query: (query: Query) => invoke<Track[]>('query_tracks', { query }),
  getTracks: (ids: number[]) => invoke<Track[]>('get_tracks', { ids }),
  distinct: (field: string) => invoke<string[]>('distinct_values', { field }),
  getArt: (id: number) => invoke<string | null>('get_art', { id }),
  imagePreview: (path: string) => invoke<string>('image_preview', { path }),
  writeTags: (ids: number[], edits: TagEdits) => invoke<WriteResult>('write_tags', { ids, edits }),
  templateTokens: () => invoke<TokenInfo[]>('template_tokens'),
  previewReorganize: (ids: number[], template: string) => invoke<PlanItem[]>('preview_reorganize', { ids, template }),
  applyReorganize: (ids: number[], template: string) => invoke<ApplyResult>('apply_reorganize', { ids, template }),
  saveTemplate: (template: string) => invoke<Config>('save_template', { template }),
  removeTemplate: (template: string) => invoke<Config>('remove_template', { template }),
  playerPlay: (id: number) => invoke<void>('player_play', { id }),
  playerToggle: () => invoke<void>('player_toggle'),
  playerStop: () => invoke<void>('player_stop'),
  playerSeek: (positionMs: number) => invoke<void>('player_seek', { positionMs }),
  playerVolume: (volume: number) => invoke<void>('player_volume', { volume }),
};

export type FieldKind = 'text' | 'number' | 'bool';

/** Everything that can be filtered on, in menu order. */
export const FILTER_FIELDS: { key: string; label: string; kind: FieldKind }[] = [
  { key: 'title', label: 'Title', kind: 'text' },
  { key: 'artist', label: 'Artist', kind: 'text' },
  { key: 'album_artist', label: 'Album Artist', kind: 'text' },
  { key: 'album', label: 'Album', kind: 'text' },
  { key: 'genre', label: 'Genre', kind: 'text' },
  { key: 'year', label: 'Year', kind: 'number' },
  { key: 'track', label: 'Track #', kind: 'number' },
  { key: 'track_total', label: 'Track Total', kind: 'number' },
  { key: 'disc', label: 'Disc #', kind: 'number' },
  { key: 'disc_total', label: 'Disc Total', kind: 'number' },
  { key: 'composer', label: 'Composer', kind: 'text' },
  { key: 'comment', label: 'Comment', kind: 'text' },
  { key: 'has_art', label: 'Has Album Art', kind: 'bool' },
  { key: 'bitrate', label: 'Bitrate (kbps)', kind: 'number' },
  { key: 'duration', label: 'Duration (sec)', kind: 'number' },
  { key: 'path', label: 'File Path', kind: 'text' },
  { key: 'dir', label: 'Folder', kind: 'text' },
  { key: 'filename', label: 'File Name', kind: 'text' },
];

export const OPS: Record<FieldKind, { key: string; label: string; needsValue: boolean }[]> = {
  text: [
    { key: 'contains', label: 'contains', needsValue: true },
    { key: 'not_contains', label: 'does not contain', needsValue: true },
    { key: 'equals', label: 'is', needsValue: true },
    { key: 'not_equals', label: 'is not', needsValue: true },
    { key: 'starts_with', label: 'starts with', needsValue: true },
    { key: 'ends_with', label: 'ends with', needsValue: true },
    { key: 'empty', label: 'is empty', needsValue: false },
    { key: 'not_empty', label: 'is not empty', needsValue: false },
  ],
  number: [
    { key: 'equals', label: '=', needsValue: true },
    { key: 'not_equals', label: '≠', needsValue: true },
    { key: 'gt', label: '>', needsValue: true },
    { key: 'gte', label: '≥', needsValue: true },
    { key: 'lt', label: '<', needsValue: true },
    { key: 'lte', label: '≤', needsValue: true },
    { key: 'empty', label: 'is empty', needsValue: false },
    { key: 'not_empty', label: 'is not empty', needsValue: false },
  ],
  bool: [
    { key: 'yes', label: 'yes', needsValue: false },
    { key: 'no', label: 'no', needsValue: false },
  ],
};

export function fieldKind(key: string): FieldKind {
  return FILTER_FIELDS.find((f) => f.key === key)?.kind ?? 'text';
}

export function formatDuration(ms: number | null): string {
  if (ms == null) return '';
  const s = Math.round(ms / 1000);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = String(s % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${sec}` : `${m}:${sec}`;
}

export function errorText(e: unknown): string {
  return typeof e === 'string' ? e : e instanceof Error ? e.message : JSON.stringify(e);
}
