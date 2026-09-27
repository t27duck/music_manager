<script lang="ts">
  import { formatDuration, type Track } from './api';

  type Sort = { field: string | null; desc: boolean };

  let {
    tracks,
    selected,
    sort = $bindable(),
    playingId = null,
    playing = false,
    unsaved = new Map(),
    onselect,
    onplay,
  }: {
    tracks: Track[];
    selected: Set<number>;
    sort: Sort;
    playingId?: number | null;
    playing?: boolean;
    /** Files whose last save failed, with why. */
    unsaved?: Map<number, string>;
    /** Asks to change the selection; `then` runs only if the change goes ahead. */
    onselect: (next: Set<number>, then?: () => void) => void;
    /** `toggle` asks to pause/resume if this track is already loaded. */
    onplay: (id: number, toggle: boolean) => void;
  } = $props();

  const ROW_H = 28;
  const HEADER_H = 32;
  const OVERSCAN = 12;
  const MENU_W = 28;
  const COLUMNS_KEY = 'music-manager.columns';

  // `flex` columns share the spare width and shrink down to `min`; the rest are fixed at
  // `width`. Dragging a column edge pins it to an explicit width.
  type Column = {
    key: string;
    label: string;
    width: number;
    min: number;
    flex?: number;
    align?: 'right' | 'center';
    value: (t: Track) => string;
  };
  const text = (k: keyof Track) => (t: Track) => (t[k] ?? '') as string;
  const COLUMNS: Column[] = [
    { key: 'track', label: '#', width: 48, min: 32, align: 'right', value: (t) => (t.track ?? '').toString() },
    { key: 'title', label: 'Title', width: 180, min: 72, flex: 2, value: text('title') },
    { key: 'artist', label: 'Artist', width: 130, min: 56, flex: 1.2, value: text('artist') },
    { key: 'album', label: 'Album', width: 150, min: 56, flex: 1.4, value: text('album') },
    { key: 'album_artist', label: 'Album Artist', width: 110, min: 56, flex: 1, value: text('album_artist') },
    { key: 'disc', label: 'Disc', width: 46, min: 32, align: 'right', value: (t) => (t.disc ?? '').toString() },
    { key: 'year', label: 'Year', width: 54, min: 40, align: 'right', value: (t) => (t.year ?? '').toString() },
    { key: 'genre', label: 'Genre', width: 90, min: 48, flex: 0.7, value: text('genre') },
    { key: 'duration', label: 'Time', width: 58, min: 44, align: 'right', value: (t) => formatDuration(t.duration_ms) },
    { key: 'has_art', label: 'Art', width: 40, min: 32, align: 'center', value: () => '' },
    { key: 'path', label: 'Path', width: 220, min: 72, flex: 2, value: text('path') },
  ];
  const ALWAYS_SHOWN = 'title';

  type Layout = { hidden: string[]; widths: Record<string, number> };
  function loadLayout(): Layout {
    try {
      const saved = JSON.parse(localStorage.getItem(COLUMNS_KEY) ?? 'null');
      const known = new Set(COLUMNS.map((c) => c.key));
      return {
        hidden: Array.isArray(saved?.hidden) ? saved.hidden.filter((k: string) => known.has(k) && k !== ALWAYS_SHOWN) : [],
        widths: Object.fromEntries(
          Object.entries(saved?.widths ?? {}).filter(([k, w]) => known.has(k) && typeof w === 'number' && w > 0),
        ) as Record<string, number>,
      };
    } catch {
      return { hidden: [], widths: {} };
    }
  }
  function saveLayout() {
    try {
      localStorage.setItem(COLUMNS_KEY, JSON.stringify(layout));
    } catch {
      /* storage unavailable; the layout just won't be remembered */
    }
  }

  let layout = $state<Layout>(loadLayout());
  let columns = $derived(COLUMNS.filter((c) => !layout.hidden.includes(c.key)));
  let grid = $derived(
    columns
      .map((c) => {
        const w = layout.widths[c.key];
        if (w) return `${w}px`;
        return c.flex ? `minmax(${c.min}px, ${c.flex}fr)` : `${c.width}px`;
      })
      .concat(`${MENU_W}px`)
      .join(' '),
  );
  // Below this the columns can't shrink any further and the table scrolls sideways.
  let minWidth = $derived(columns.reduce((sum, c) => sum + (layout.widths[c.key] ?? (c.flex ? c.min : c.width)), MENU_W) + 2);
  let markerColumn = $derived(columns.some((c) => c.key === 'track') ? 'track' : 'title');

  function toggleColumn(key: string) {
    const hidden = layout.hidden.includes(key) ? layout.hidden.filter((k) => k !== key) : [...layout.hidden, key];
    layout = { ...layout, hidden };
    saveLayout();
  }

  function resetColumns() {
    layout = { hidden: [], widths: {} };
    saveLayout();
    menu = null;
  }

  function startResize(e: PointerEvent, c: Column) {
    if (e.button !== 0) return;
    e.preventDefault();
    const handle = e.currentTarget as HTMLElement;
    const startX = e.clientX;
    const startW = handle.parentElement!.getBoundingClientRect().width;
    handle.setPointerCapture(e.pointerId);
    const move = (ev: PointerEvent) => {
      layout.widths = { ...layout.widths, [c.key]: Math.round(Math.max(c.min, startW + ev.clientX - startX)) };
    };
    const end = () => {
      handle.removeEventListener('pointermove', move);
      handle.removeEventListener('pointerup', end);
      handle.removeEventListener('pointercancel', end);
      saveLayout();
    };
    handle.addEventListener('pointermove', move);
    handle.addEventListener('pointerup', end);
    handle.addEventListener('pointercancel', end);
  }

  function autoWidth(c: Column) {
    const { [c.key]: _, ...rest } = layout.widths;
    layout.widths = rest;
    saveLayout();
  }

  let menu = $state<{ x: number; y: number } | null>(null);
  let menuEl = $state<HTMLDivElement>();

  function openMenu(x: number, y: number) {
    // Keep it on screen; the menu is about 190×330.
    menu = { x: Math.min(x, window.innerWidth - 200), y: Math.max(4, Math.min(y, window.innerHeight - 340)) };
    requestAnimationFrame(() => menuEl?.querySelector<HTMLElement>('[role=menuitemcheckbox]:not(:disabled)')?.focus());
  }

  function closeMenu() {
    menu = null;
    scroller?.focus();
  }

  function menuKey(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.stopPropagation();
      closeMenu();
    } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      const items = [...menuEl!.querySelectorAll<HTMLElement>('button:not(:disabled)')];
      const i = items.indexOf(document.activeElement as HTMLElement);
      items[(i + (e.key === 'ArrowDown' ? 1 : items.length - 1)) % items.length]?.focus();
    }
  }

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
    let next: Set<number>;
    let nextAnchor = index;
    if (e.shiftKey && anchor !== null) {
      const ids = range(anchor, index);
      next = e.ctrlKey || e.metaKey ? new Set([...selected, ...ids]) : new Set(ids);
      nextAnchor = anchor;
    } else if (e.ctrlKey || e.metaKey) {
      next = new Set(selected);
      if (next.has(id)) next.delete(id);
      else next.add(id);
    } else {
      next = new Set([id]);
    }
    scroller.focus();
    onselect(next, () => {
      anchor = nextAnchor;
      cursor = index;
    });
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
      onselect(new Set(tracks.map((t) => t.id)));
      return;
    }
    if (e.key === 'Escape') {
      onselect(new Set());
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
    const to = Math.max(0, Math.min(tracks.length - 1, next));
    const from = e.shiftKey ? (anchor ?? cursor ?? to) : to;
    onselect(new Set(e.shiftKey ? range(from, to) : [tracks[to].id]), () => {
      anchor = from;
      cursor = to;
      scrollIntoView(to);
    });
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
  <div
    class="header"
    style:grid-template-columns={grid}
    style:min-width="{minWidth}px"
    role="row"
    tabindex="-1"
    oncontextmenu={(e) => {
      e.preventDefault();
      openMenu(e.clientX, e.clientY);
    }}
  >
    {#each columns as c (c.key)}
      <div class="th-cell" role="columnheader" aria-sort={sort.field === c.key ? (sort.desc ? 'descending' : 'ascending') : undefined}>
        <button
          class="th"
          class:sorted={sort.field === c.key}
          style:justify-content={c.align === 'right' ? 'flex-end' : c.align === 'center' ? 'center' : 'flex-start'}
          onclick={() => toggleSort(c.key)}
        >
          <span class="th-label">{c.label}</span>
          {#if sort.field === c.key}<span class="arrow">{sort.desc ? '▼' : '▲'}</span>{/if}
        </button>
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div
          class="resize"
          class:pinned={layout.widths[c.key]}
          title="Drag to resize; double-click to fit the window"
          onpointerdown={(e) => startResize(e, c)}
          ondblclick={() => autoWidth(c)}
        ></div>
      </div>
    {/each}
    <button
      class="th columns-button"
      title="Choose columns"
      aria-label="Choose columns"
      aria-haspopup="menu"
      aria-expanded={!!menu}
      onclick={(e) => {
        const r = e.currentTarget.getBoundingClientRect();
        if (menu) closeMenu();
        else openMenu(r.right - 190, r.bottom + 2);
      }}>⋮</button
    >
  </div>
  <div class="body" style:height="{tracks.length * ROW_H}px" style:min-width="{minWidth}px">
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
        class:unsaved={unsaved.has(t.id)}
        title={[unsaved.has(t.id) && `Not saved: ${unsaved.get(t.id)}`, t.error && `Tag error: ${t.error}`].filter(Boolean).join('\n') ||
          undefined}
      >
        {#each columns as c (c.key)}
          <div class="td" class:right={c.align === 'right'} class:center={c.align === 'center'} role="gridcell">
            {#if c.key === markerColumn && playingId === t.id}
              <span class="now-playing" title={playing ? 'Playing' : 'Paused'}>{playing ? '▶' : '❚❚'}</span>
            {/if}
            {#if c.key === 'track' && playingId === t.id}
              <!-- the marker replaces the number -->
            {:else if c.key === 'has_art'}
              {#if t.has_art}<span class="art-dot" title="Has album art"></span>{/if}
            {:else if c.key === 'title' && (t.error || unsaved.has(t.id))}
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

{#if menu}
  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
  <div
    class="menu-backdrop"
    onclick={closeMenu}
    oncontextmenu={(e) => {
      e.preventDefault();
      closeMenu();
    }}
  ></div>
  <div class="menu" role="menu" aria-label="Columns" tabindex="-1" bind:this={menuEl} style:left="{menu.x}px" style:top="{menu.y}px" onkeydown={menuKey}>
    {#each COLUMNS as c (c.key)}
      {@const shown = !layout.hidden.includes(c.key)}
      <button role="menuitemcheckbox" aria-checked={shown} disabled={c.key === ALWAYS_SHOWN} onclick={() => toggleColumn(c.key)}>
        <span class="check">{shown ? '✓' : ''}</span>{c.key === 'track' ? 'Track #' : c.label}
      </button>
    {/each}
    <hr />
    <button onclick={resetColumns}><span class="check"></span>Reset columns</button>
  </div>
{/if}

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
  .th-cell {
    position: relative;
    display: flex;
    min-width: 0;
    border-right: 1px solid var(--navy-800);
  }
  .th {
    flex: 1;
    min-width: 0;
    overflow: hidden;
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
  }
  .th:hover:not(:disabled) {
    background: var(--navy-800);
    color: var(--text);
    border-color: var(--navy-800);
  }
  .th.sorted {
    color: var(--cerulean-light);
  }
  .th-label {
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .arrow {
    font-size: 9px;
  }
  .resize {
    position: absolute;
    top: 0;
    right: -4px;
    width: 8px;
    height: 100%;
    z-index: 1;
    cursor: col-resize;
  }
  .resize:hover,
  .resize.pinned:hover {
    background: linear-gradient(90deg, transparent 3px, var(--cerulean) 3px, var(--cerulean) 5px, transparent 5px);
  }
  .columns-button {
    justify-content: center;
    padding: 0;
    font-size: 15px;
    letter-spacing: 0;
  }
  .menu-backdrop {
    position: fixed;
    inset: 0;
    z-index: 40;
  }
  .menu {
    position: fixed;
    z-index: 41;
    width: 190px;
    padding: 4px;
    display: flex;
    flex-direction: column;
    background: var(--navy-850);
    border: 1px solid var(--navy-600);
    border-radius: var(--radius);
    box-shadow: 0 8px 28px rgba(0, 0, 0, 0.5);
    outline: none;
  }
  .menu button {
    display: flex;
    align-items: center;
    text-align: left;
    border: none;
    background: transparent;
    padding: 5px 8px;
    border-radius: 4px;
  }
  .menu button:hover:not(:disabled),
  .menu button:focus-visible {
    background: var(--navy-700);
    outline: none;
  }
  .menu .check {
    width: 18px;
    color: var(--cerulean-light);
  }
  .menu hr {
    width: 100%;
    border: none;
    border-top: 1px solid var(--navy-700);
    margin: 4px 0;
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
  .row.unsaved {
    border-left-color: var(--danger);
  }
  .row.playing .td {
    color: var(--cerulean-light);
  }
  .now-playing {
    color: var(--cerulean);
    font-size: 10px;
  }
  .td:not(.right) .now-playing {
    margin-right: 6px;
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
