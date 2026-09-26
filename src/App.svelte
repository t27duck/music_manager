<script lang="ts">
  import { onMount } from 'svelte';
  import { listen } from '@tauri-apps/api/event';
  import { ask, open } from '@tauri-apps/plugin-dialog';
  import { api, errorText, type Config, type FilterRow, type Progress, type ScanSummary, type Track } from './lib/api';
  import FilterBar from './lib/FilterBar.svelte';
  import TrackTable from './lib/TrackTable.svelte';
  import Editor from './lib/Editor.svelte';
  import Reorganize from './lib/Reorganize.svelte';
  import { dismiss, toast, toasts } from './lib/toast.svelte';

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
  let querySeq = 0;

  let selectedTracks = $derived(tracks.filter((t) => selected.has(t.id)));

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
      tracks = rows;
      queryError = null;
      // Keep the selection to what's still visible so edits only touch what you can see.
      const visible = new Set(rows.map((r) => r.id));
      if ([...selected].some((id) => !visible.has(id))) {
        selected = new Set([...selected].filter((id) => visible.has(id)));
      }
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
    ];
    api.getConfig().then((c) => {
      config = c;
      if (c.library_path) refresh();
    });
    return () => unlisten.forEach((p) => p.then((f) => f()));
  });

  async function chooseLibrary() {
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
        <TrackTable {tracks} bind:selected bind:sort />
      </section>
      <Editor tracks={selectedTracks} onsaved={refresh} />
    </main>
    <footer class="status">
      <span>{tracks.length.toLocaleString()} shown</span>
      {#if tracks.length !== libraryCount}<span class="muted">of {libraryCount.toLocaleString()}</span>{/if}
      {#if selected.size}<span class="sel">{selected.size.toLocaleString()} selected</span>{/if}
    </footer>
  {/if}
</div>

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
