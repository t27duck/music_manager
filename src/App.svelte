<script lang="ts">
  import { onMount } from 'svelte';
  import { listen } from '@tauri-apps/api/event';
  import { getCurrentWindow } from '@tauri-apps/api/window';
  import { ask, open } from '@tauri-apps/plugin-dialog';
  import {
    api,
    errorText,
    type Config,
    type FilterRow,
    type PlayerStatus,
    type Progress,
    type ScanSummary,
    type TagEdits,
    type Track,
    type WriteFailure,
    type WriteResult,
  } from './lib/api';
  import FilterBar from './lib/FilterBar.svelte';
  import TrackTable from './lib/TrackTable.svelte';
  import Editor from './lib/Editor.svelte';
  import Reorganize from './lib/Reorganize.svelte';
  import PlayerBar from './lib/PlayerBar.svelte';
  import UnsavedChanges from './lib/UnsavedChanges.svelte';
  import SaveFailures from './lib/SaveFailures.svelte';
  import Menu, { type MenuItem } from './lib/Menu.svelte';
  import { copyText, dismiss, toast, toasts } from './lib/toast.svelte';

  let config = $state<Config | null>(null);
  let tracks = $state<Track[]>([]);
  let libraryCount = $state(0);
  let selected = $state<Set<number>>(new Set());
  let search = $state('');
  let filters = $state<FilterRow[]>([]);
  let sort = $state<{ field: string | null; desc: boolean }>({ field: null, desc: false });
  let scanning = $state(false);
  let progress = $state<Progress | null>(null);
  let queryError = $state<string | null>(null);
  let reorganizing = $state<number[] | null>(null);
  let player = $state<PlayerStatus>({ track_id: null, playing: false, position_ms: 0, duration_ms: null, error: null });

  function play(id: number, toggle: boolean) {
    const request = toggle && player.track_id === id ? api.playerToggle() : api.playerPlay(id);
    request.catch((e) => toast(errorText(e), 'error'));
  }
  let querySeq = 0;

  let editor = $state<Editor>();
  let editorDirty = $state(false);
  // Selected tracks a filter has hidden while the editor had unsaved edits for them; kept so
  // the edits aren't lost. Dropped on the next refresh without unsaved edits.
  let held = $state<Track[]>([]);

  let selectedTracks = $derived.by(() => {
    const shown = tracks.filter((t) => selected.has(t.id));
    if (shown.length === selected.size) return shown;
    const ids = new Set(shown.map((t) => t.id));
    return shown.concat(held.filter((t) => selected.has(t.id) && !ids.has(t.id)));
  });

  // Something that would throw away unsaved tag edits waiting on the user's answer.
  let pending = $state<{ run: () => void; what: string; canSave: boolean } | null>(null);

  /** Runs `action` now, or once the user has saved or discarded any unsaved edits. */
  function guard(action: () => void) {
    if (!editorDirty || !editor) return action();
    if (pending) return;
    const edited = selectedTracks;
    const what = edited.length === 1 ? `“${edited[0].title || edited[0].filename}”` : `${edited.length.toLocaleString()} files`;
    pending = { run: action, what, canSave: editor.canSave() };
  }

  async function resolvePending(choice: 'save' | 'discard' | 'cancel') {
    const p = pending;
    if (!p) return;
    if (choice === 'save' && !(await editor?.save())) {
      pending = null; // the error toast explains; the edits are still in the editor
      return;
    }
    pending = null;
    if (choice === 'cancel') return;
    if (choice === 'discard') editor?.discard();
    p.run();
  }

  // Files whose last save failed, with the edits that were attempted so they can be retried.
  // Kept until the file saves or the user clears the list.
  let failures = $state<Map<number, WriteFailure & { edits: TagEdits }>>(new Map());
  let failureMessages = $derived(new Map([...failures].map(([id, f]) => [id, f.message])));
  let report = $state<{ saved: number | null } | null>(null);
  let retrying = $state(false);

  function recordSave(ids: number[], edits: TagEdits, result: WriteResult, retry = false) {
    const next = new Map(failures);
    for (const id of ids) next.delete(id);
    for (const f of result.failed) next.set(f.id, { ...f, edits });
    failures = next;
    // A first save with failures opens the report; a retry updates the open one.
    if (result.failed.length && !retry) report = { saved: result.updated };
    if (retry ? result.updated : !result.failed.length) {
      toast(`Saved ${result.updated.toLocaleString()} file${result.updated === 1 ? '' : 's'}`, 'success');
    }
    refresh();
  }

  async function retryFailures() {
    retrying = true;
    try {
      // Group by the edits each file was meant to get; usually that's a single write.
      const groups = new Map<TagEdits, number[]>();
      for (const [id, f] of failures) groups.set(f.edits, [...(groups.get(f.edits) ?? []), id]);
      for (const [edits, ids] of groups) recordSave(ids, edits, await api.writeTags(ids, edits), true);
    } catch (e) {
      toast(errorText(e), 'error');
    } finally {
      retrying = false;
    }
    if (!failures.size) report = null;
  }

  function selectFailures() {
    const ids = [...failures.values()].filter((f) => f.path).map((f) => f.id);
    guard(async () => {
      report = null;
      const shown = () => new Set(tracks.map((t) => t.id));
      if (ids.some((id) => !shown().has(id))) {
        search = '';
        filters = [];
        await refresh();
      }
      const visible = shown();
      selected = new Set(ids.filter((id) => visible.has(id)));
    });
  }

  let rowMenu = $state<{ id: number; x: number; y: number } | null>(null);
  let rowMenuItems = $derived.by((): MenuItem[] => {
    if (!rowMenu) return [];
    const id = rowMenu.id;
    const n = selected.size;
    const files = `${n.toLocaleString()} file${n === 1 ? '' : 's'}`;
    const fullPath = (t: Track) => `${config?.library_path?.replace(/\/$/, '')}/${t.path}`;
    return [
      { label: player.track_id === id && player.playing ? 'Pause' : 'Play', hint: 'Space', action: () => play(id, true) },
      { label: 'Edit tags', action: () => editor?.focusFirstField() },
      { label: `Reorganize ${files}…`, action: () => (reorganizing = [...selected]) },
      'separator',
      { label: 'Show in file manager', action: () => api.showInFolder(id).catch((e) => toast(errorText(e), 'error')) },
      {
        label: n === 1 ? 'Copy path' : `Copy ${n.toLocaleString()} paths`,
        action: () => copyText(selectedTracks.map(fullPath).join('\n'), n === 1 ? 'Copied the path' : `Copied ${n.toLocaleString()} paths`),
      },
    ];
  });

  function select(next: Set<number>, then?: () => void) {
    const same = next.size === selected.size && [...next].every((id) => selected.has(id));
    const apply = () => {
      selected = next;
      then?.();
    };
    if (same) apply();
    else guard(apply);
  }

  async function refresh() {
    const seq = ++querySeq;
    try {
      const rows = await api.query({
        search,
        filters: filters.map((f) => ({ ...f })),
        sort: sort.field,
        desc: sort.desc,
      });
      if (seq !== querySeq) return;
      const visible = new Set(rows.map((r) => r.id));
      if (editorDirty) {
        held = selectedTracks.filter((t) => !visible.has(t.id));
      } else {
        held = [];
        // Keep the selection to what's still visible so edits only touch what you can see.
        if ([...selected].some((id) => !visible.has(id))) {
          selected = new Set([...selected].filter((id) => visible.has(id)));
        }
      }
      tracks = rows;
      queryError = null;
      const status = await api.status();
      libraryCount = status.count;
      scanning = status.scanning;
    } catch (e) {
      if (seq === querySeq) queryError = errorText(e);
    }
  }

  let refreshTimer: ReturnType<typeof setTimeout> | undefined;
  function refreshSoon(delay = 150) {
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(refresh, delay);
  }

  // Re-query whenever the search, filters or sort change.
  $effect(() => {
    JSON.stringify([search, filters, sort]);
    if (config?.library_path) refreshSoon();
  });

  onMount(() => {
    const unlisten = [
      listen<Progress>('progress', (e) => {
        progress = e.payload.done >= e.payload.total ? null : e.payload;
      }),
      listen('scan-started', () => {
        scanning = true;
      }),
      listen<ScanSummary>('scan-finished', (e) => {
        scanning = false;
        progress = null;
        const s = e.payload;
        if (s.added_or_updated || s.removed) {
          toast(`Library scanned: ${s.added_or_updated} added or updated, ${s.removed} removed`, 'success');
        }
        refresh();
      }),
      listen<string>('scan-failed', (e) => {
        scanning = false;
        progress = null;
        toast(e.payload, 'error');
      }),
      listen('library-changed', () => refreshSoon(300)),
      listen<PlayerStatus>('player', (e) => {
        player = e.payload;
      }),
      getCurrentWindow().onCloseRequested((e) => {
        if (!editorDirty) return;
        e.preventDefault();
        guard(() => getCurrentWindow().destroy());
      }),
    ];
    api.getConfig().then((c) => {
      config = c;
      if (c.library_path) refresh();
    });
    return () => unlisten.forEach((p) => p.then((f) => f()));
  });

  function chooseLibrary() {
    guard(pickLibrary);
  }

  async function pickLibrary() {
    const path = await open({ directory: true, title: 'Choose your music library folder', defaultPath: config?.library_path ?? undefined });
    if (typeof path !== 'string' || path === config?.library_path) return;
    if (config?.library_path) {
      const ok = await ask(`Switch the library to\n${path}?\n\nThe index will be rebuilt from the new folder. No files are changed.`, {
        title: 'Change library folder',
        kind: 'info',
      });
      if (!ok) return;
    }
    try {
      config = await api.setLibraryPath(path);
      selected = new Set();
      tracks = [];
    } catch (e) {
      toast(errorText(e), 'error');
    }
  }

  const progressLabel: Record<Progress['kind'], string> = { scan: 'Scanning', write: 'Saving tags', reorganize: 'Moving files' };
</script>

<div class="app">
  <header class="top">
    <div class="brand">
      <svg viewBox="0 0 512 512" aria-hidden="true"><path d="M312 128v196a56 56 0 1 1-32-50.6V176l-96 24v156a56 56 0 1 1-32-50.6V164z" /></svg>
      <span>Music<b>Manager</b></span>
    </div>
    {#if config?.library_path}
      <button class="library" title="Change library folder" onclick={chooseLibrary}>
        <span class="muted">Library</span>
        {config.library_path}
      </button>
      <div class="spacer"></div>
      {#if progress}
        <div class="progress" title="{progress.done} / {progress.total}">
          <span>{progressLabel[progress.kind]} {progress.done.toLocaleString()} / {progress.total.toLocaleString()}</span>
          <div class="bar"><div style:width="{(100 * progress.done) / Math.max(1, progress.total)}%"></div></div>
        </div>
      {:else if scanning}
        <span class="muted">Scanning…</span>
      {/if}
      <button onclick={() => api.rescan()} disabled={scanning} title="Re-read changed files from disk">Rescan</button>
      <button class="primary" disabled={!selected.size} onclick={() => (reorganizing = [...selected])}>
        Reorganize{selected.size ? ` ${selected.size}` : ''}…
      </button>
    {/if}
  </header>

  {#if !config}
    <div class="center muted">Loading…</div>
  {:else if !config.library_path}
    <div class="center welcome">
      <h1>Welcome to Music<b>Manager</b></h1>
      <p class="muted">Choose the folder that holds your MP3s. It will be indexed and watched for changes.</p>
      <button class="primary big" onclick={chooseLibrary}>Choose library folder…</button>
    </div>
  {:else}
    <FilterBar bind:search bind:filters />
    <main>
      <section class="table">
        {#if queryError}<div class="query-error">{queryError}</div>{/if}
        <TrackTable
          {tracks}
          {selected}
          bind:sort
          playingId={player.track_id}
          playing={player.playing}
          unsaved={failureMessages}
          onselect={select}
          onplay={play}
          onrowmenu={(id, x, y) => (rowMenu = { id, x, y })}
        />
      </section>
      <Editor
        bind:this={editor}
        bind:dirty={editorDirty}
        tracks={selectedTracks}
        onsaved={recordSave}
        onplay={play}
        playingId={player.track_id}
        playing={player.playing}
      />
    </main>
    {#if player.track_id !== null}
      <PlayerBar status={player} />
    {/if}
    <footer class="status">
      <span>{tracks.length.toLocaleString()} shown</span>
      {#if tracks.length !== libraryCount}<span class="muted">of {libraryCount.toLocaleString()}</span>{/if}
      {#if selected.size}<span class="sel">{selected.size.toLocaleString()} selected</span>{/if}
      {#if failures.size}
        <span class="spacer"></span>
        <button class="not-saved" onclick={() => (report = { saved: null })}>
          {failures.size.toLocaleString()} not saved
        </button>
      {/if}
    </footer>
  {/if}
</div>

{#if rowMenu}
  <Menu x={rowMenu.x} y={rowMenu.y} items={rowMenuItems} label="Track" onclose={() => (rowMenu = null)} />
{/if}

{#if report && failures.size}
  <SaveFailures
    failures={[...failures.values()]}
    saved={report.saved}
    {retrying}
    onretry={retryFailures}
    onselect={selectFailures}
    onforget={() => {
      failures = new Map();
      report = null;
    }}
    onclose={() => (report = null)}
  />
{/if}

{#if pending}
  <UnsavedChanges what={pending.what} canSave={pending.canSave} onchoose={resolvePending} />
{/if}

{#if reorganizing && config}
  <Reorganize ids={reorganizing} {config} onclose={() => (reorganizing = null)} onconfig={(c) => (config = c)} />
{/if}

<div class="toasts">
  {#each toasts as t (t.id)}
    <button class="toast {t.kind}" onclick={() => dismiss(t.id)}>{t.text}</button>
  {/each}
</div>

<style>
  .app {
    display: flex;
    flex-direction: column;
    height: 100%;
  }
  .top {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 8px 14px;
    background: linear-gradient(90deg, var(--navy-850), var(--navy-900));
    border-bottom: 2px solid var(--cerulean-deep);
    min-height: 50px;
  }
  .brand {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 16px;
    letter-spacing: 0.01em;
  }
  .brand svg {
    width: 24px;
    height: 24px;
    fill: var(--cerulean);
  }
  .brand b,
  h1 b {
    color: var(--cerulean);
  }
  .library {
    display: flex;
    gap: 8px;
    max-width: 50%;
    overflow: hidden;
    text-overflow: ellipsis;
    background: transparent;
    border-color: var(--navy-700);
  }
  .spacer {
    flex: 1;
  }
  .progress {
    display: flex;
    flex-direction: column;
    gap: 3px;
    font-size: 11px;
    color: var(--text-muted);
    min-width: 200px;
  }
  .progress .bar {
    height: 4px;
    background: var(--navy-700);
    border-radius: 2px;
    overflow: hidden;
  }
  .progress .bar div {
    height: 100%;
    background: var(--cerulean);
    transition: width 0.15s;
  }
  main {
    flex: 1;
    display: flex;
    min-height: 0;
  }
  .table {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }
  .query-error {
    padding: 6px 14px;
    color: var(--danger);
    background: rgba(239, 107, 115, 0.1);
  }
  .status {
    display: flex;
    gap: 10px;
    padding: 4px 14px;
    font-size: 12px;
    background: var(--navy-900);
    border-top: 1px solid var(--navy-800);
  }
  .status .sel {
    color: var(--cerulean-light);
  }
  .status .not-saved {
    padding: 0 8px;
    font-size: 12px;
    border-color: rgba(239, 107, 115, 0.6);
    color: var(--danger);
    background: transparent;
  }
  .center {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 10px;
  }
  .welcome h1 {
    font-weight: 500;
    margin: 0;
  }
  .big {
    font-size: 15px;
    padding: 10px 22px;
    margin-top: 10px;
  }
  .toasts {
    position: fixed;
    left: 18px;
    bottom: 36px;
    z-index: 100;
    display: flex;
    flex-direction: column;
    gap: 8px;
    max-width: 460px;
  }
  .toast {
    text-align: left;
    white-space: normal;
    padding: 10px 14px;
    background: var(--navy-800);
    border-left: 4px solid var(--cerulean);
    box-shadow: 0 6px 24px rgba(0, 0, 0, 0.45);
  }
  .toast.success {
    border-left-color: var(--success);
  }
  .toast.error {
    border-left-color: var(--danger);
  }
</style>
