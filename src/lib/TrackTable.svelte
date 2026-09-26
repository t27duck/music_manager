<script lang="ts">
  import { formatDuration, type Track } from './api';

  type Sort = { field: string | null; desc: boolean };

  let {
    tracks,
    selected = $bindable(),
    sort = $bindable(),
    playingId = null,
    playing = false,
    onplay,
  }: {
    tracks: Track[];
    selected: Set<number>;
    sort: Sort;
    playingId?: number | null;
    playing?: boolean;
    /** `toggle` asks to pause/resume if this track is already loaded. */
    onplay: (id: number, toggle: boolean) => void;
  } = $props();

  const ROW_H = 28;
  const HEADER_H = 32;
  const OVERSCAN = 12;

  type Column = { key: string; label: string; width: string; align?: 'right' | 'center'; value: (t: Track) => string };
  const text = (k: keyof Track) => (t: Track) => (t[k] ?? '') as string;
  const COLUMNS: Column[] = [
    { key: 'track', label: '#', width: '48px', align: 'right', value: (t) => (t.track ?? '').toString() },
    { key: 'title', label: 'Title', width: 'minmax(180px, 2fr)', value: text('title') },
    { key: 'artist', label: 'Artist', width: 'minmax(130px, 1.2fr)', value: text('artist') },
    { key: 'album', label: 'Album', width: 'minmax(150px, 1.4fr)', value: text('album') },
    { key: 'album_artist', label: 'Album Artist', width: 'minmax(110px, 1fr)', value: text('album_artist') },
    { key: 'disc', label: 'Disc', width: '46px', align: 'right', value: (t) => (t.disc ?? '').toString() },
    { key: 'year', label: 'Year', width: '54px', align: 'right', value: (t) => (t.year ?? '').toString() },
    { key: 'genre', label: 'Genre', width: 'minmax(90px, 0.7fr)', value: text('genre') },
    { key: 'duration', label: 'Time', width: '58px', align: 'right', value: (t) => formatDuration(t.duration_ms) },
    { key: 'has_art', label: 'Art', width: '40px', align: 'center', value: () => '' },
    { key: 'path', label: 'Path', width: 'minmax(220px, 2fr)', value: text('path') },
  ];
  const grid = COLUMNS.map((c) => c.width).join(' ');

  let scroller: HTMLDivElement;
  let scrollTop = $state(0);
  let viewHeight = $state(600);
  let anchor = $state<number | null>(null); // index of last plain/ctrl click
  let cursor = $state<number | null>(null); // index with keyboard focus

  let start = $derived(Math.max(0, Math.floor(scrollTop / ROW_H) - OVERSCAN));
  let end = $derived(Math.min(tracks.length, Math.ceil((scrollTop + viewHeight) / ROW_H) + OVERSCAN));
  let visible = $derived(tracks.slice(start, end));

  // Keep the anchor/cursor meaningful when the list changes underneath us.
  $effect(() => {
    if (cursor !== null && cursor >= tracks.length) cursor = tracks.length ? tracks.length - 1 : null;
    if (anchor !== null && anchor >= tracks.length) anchor = null;
  });

  function toggleSort(key: string) {
    if (sort.field !== key) sort = { field: key, desc: false };
    else if (!sort.desc) sort = { field: key, desc: true };
    else sort = { field: null, desc: false };
  }

  function range(a: number, b: number): number[] {
    const [lo, hi] = a < b ? [a, b] : [b, a];
    return tracks.slice(lo, hi + 1).map((t) => t.id);
  }

  function clickRow(e: MouseEvent, index: number) {
    const id = tracks[index].id;
    if (e.shiftKey && anchor !== null) {
      const ids = range(anchor, index);
      selected = e.ctrlKey || e.metaKey ? new Set([...selected, ...ids]) : new Set(ids);
    } else if (e.ctrlKey || e.metaKey) {
      const next = new Set(selected);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      selected = next;
      anchor = index;
    } else {
      selected = new Set([id]);
      anchor = index;
    }
    cursor = index;
    scroller.focus();
  }

  function scrollIntoView(index: number) {
    const top = index * ROW_H;
    const bodyView = viewHeight - HEADER_H;
    if (top < scroller.scrollTop) scroller.scrollTop = top;
    else if (top + ROW_H > scroller.scrollTop + bodyView) scroller.scrollTop = top + ROW_H - bodyView;
  }

  function onKey(e: KeyboardEvent) {
    if (!tracks.length) return;
    const mod = e.ctrlKey || e.metaKey;
    if (mod && e.key.toLowerCase() === 'a') {
      e.preventDefault();
      selected = new Set(tracks.map((t) => t.id));
      return;
    }
    if (e.key === 'Escape') {
      selected = new Set();
      return;
    }
    if (e.key === ' ') {
      e.preventDefault();
      const index = cursor ?? (selected.size === 1 ? tracks.findIndex((t) => selected.has(t.id)) : -1);
      if (index >= 0) onplay(tracks[index].id, true);
      return;
    }
    const page = Math.max(1, Math.floor((viewHeight - HEADER_H) / ROW_H) - 1);
    const moves: Record<string, number> = { ArrowDown: 1, ArrowUp: -1, PageDown: page, PageUp: -page };
    let next: number | null = null;
    if (e.key in moves) next = (cursor ?? -1) + moves[e.key];
    else if (e.key === 'Home') next = 0;
    else if (e.key === 'End') next = tracks.length - 1;
    if (next === null) return;
    e.preventDefault();
    next = Math.max(0, Math.min(tracks.length - 1, next));
    if (e.shiftKey) {
      if (anchor === null) anchor = cursor ?? next;
      selected = new Set(range(anchor, next));
    } else {
      selected = new Set([tracks[next].id]);
      anchor = next;
    }
    cursor = next;
    scrollIntoView(next);
  }
</script>

<div
  class="scroller"
  bind:this={scroller}
  bind:clientHeight={viewHeight}
  onscroll={() => (scrollTop = scroller.scrollTop)}
  onkeydown={onKey}
  tabindex="0"
  role="grid"
  aria-rowcount={tracks.length}
  aria-multiselectable="true"
>
  <div class="header" style:grid-template-columns={grid} role="row">
    {#each COLUMNS as c (c.key)}
      <button
        class="th"
        class:sorted={sort.field === c.key}
        style:justify-content={c.align === 'right' ? 'flex-end' : c.align === 'center' ? 'center' : 'flex-start'}
        onclick={() => toggleSort(c.key)}
        role="columnheader"
      >
        {c.label}
        {#if sort.field === c.key}<span class="arrow">{sort.desc ? '▼' : '▲'}</span>{/if}
      </button>
    {/each}
  </div>
  <div class="body" style:height="{tracks.length * ROW_H}px">
    {#each visible as t, i (t.id)}
      {@const index = start + i}
      <!-- svelte-ignore a11y_click_events_have_key_events -->
      <div
        class="row"
        class:odd={index % 2 === 1}
        class:selected={selected.has(t.id)}
        class:cursor={cursor === index}
        class:playing={playingId === t.id}
        style:grid-template-columns={grid}
        style:transform="translateY({index * ROW_H}px)"
        onclick={(e) => clickRow(e, index)}
        ondblclick={() => onplay(t.id, false)}
        onmousedown={(e) => e.shiftKey && e.preventDefault()}
        role="row"
        tabindex="-1"
        aria-selected={selected.has(t.id)}
        title={t.error ? `Tag error: ${t.error}` : undefined}
      >
        {#each COLUMNS as c (c.key)}
          <div class="td" class:right={c.align === 'right'} class:center={c.align === 'center'} role="gridcell">
            {#if c.key === 'track' && playingId === t.id}
              <span class="now-playing" title={playing ? 'Playing' : 'Paused'}>{playing ? '▶' : '❚❚'}</span>
            {:else if c.key === 'has_art'}
              {#if t.has_art}<span class="art-dot" title="Has album art"></span>{/if}
            {:else if c.key === 'title' && t.error}
              <span class="error-dot"></span>{c.value(t) || t.filename}
            {:else if c.key === 'title'}
              {c.value(t) || t.filename}
            {:else if c.key === 'path'}
              <span class="path">{t.dir ? `${t.dir}/` : ''}<b>{t.filename}</b></span>
            {:else}
              {c.value(t)}
            {/if}
          </div>
        {/each}
      </div>
    {/each}
  </div>
  {#if !tracks.length}
    <div class="empty">No tracks match.</div>
  {/if}
</div>

<style>
  .scroller {
    height: 100%;
    overflow: auto;
    outline: none;
    position: relative;
    background: var(--navy-950);
  }
  .header,
  .row {
    display: grid;
    min-width: 1250px;
    column-gap: 0;
  }
  .header {
    position: sticky;
    top: 0;
    z-index: 2;
    height: 32px;
    background: var(--navy-850);
    border-bottom: 1px solid var(--navy-700);
  }
  .th {
    display: flex;
    align-items: center;
    gap: 4px;
    border: none;
    border-radius: 0;
    background: transparent;
    padding: 0 8px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: var(--text-muted);
    border-right: 1px solid var(--navy-800);
  }
  .th:hover:not(:disabled) {
    background: var(--navy-800);
    color: var(--text);
    border-color: var(--navy-800);
  }
  .th.sorted {
    color: var(--cerulean-light);
  }
  .arrow {
    font-size: 9px;
  }
  .body {
    position: relative;
  }
  .row {
    position: absolute;
    left: 0;
    right: 0;
    top: 0;
    height: 28px;
    align-items: center;
    cursor: default;
    user-select: none;
    border-left: 2px solid transparent;
  }
  .row.odd {
    background: rgba(15, 42, 82, 0.35);
  }
  .row:hover {
    background: var(--navy-800);
  }
  .row.selected {
    background: var(--cerulean-select);
  }
  .row.cursor {
    border-left-color: var(--cerulean);
  }
  .row.playing .td {
    color: var(--cerulean-light);
  }
  .now-playing {
    color: var(--cerulean);
    font-size: 10px;
  }
  .td {
    padding: 0 8px;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .td.right {
    text-align: right;
    font-variant-numeric: tabular-nums;
    color: var(--text-muted);
  }
  .td.center {
    text-align: center;
  }
  .path {
    color: var(--text-faint);
  }
  .path b {
    font-weight: normal;
    color: var(--text-muted);
  }
  .art-dot {
    display: inline-block;
    width: 8px;
    height: 8px;
    border-radius: 2px;
    background: var(--cerulean);
  }
  .error-dot {
    display: inline-block;
    width: 7px;
    height: 7px;
    margin-right: 6px;
    border-radius: 50%;
    background: var(--danger);
  }
  .empty {
    position: absolute;
    top: 80px;
    width: 100%;
    text-align: center;
    color: var(--text-muted);
  }
</style>
