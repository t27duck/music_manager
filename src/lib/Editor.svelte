<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import { open } from '@tauri-apps/plugin-dialog';
  import { getCurrentWebview } from '@tauri-apps/api/webview';
  import { api, errorText, formatDuration, type EditField, type TagEdits, type Track, type WriteResult } from './api';
  import { toast } from './toast.svelte';

  let {
    tracks,
    onsaved,
    onplay,
    playingId = null,
    playing = false,
    dirty = $bindable(false),
  }: {
    tracks: Track[];
    /** After a write, with what was attempted; reporting the outcome is up to the caller. */
    onsaved: (ids: number[], edits: TagEdits, result: WriteResult) => void;
    onplay: (id: number, toggle: boolean) => void;
    playingId?: number | null;
    playing?: boolean;
    /** Out: whether there are unsaved edits. */
    dirty?: boolean;
  } = $props();

  type FieldDef = { key: EditField; label: string; kind: 'text' | 'number' | 'long'; list?: boolean };
  const FIELDS: Record<EditField, FieldDef> = {
    title: { key: 'title', label: 'Title', kind: 'text' },
    artist: { key: 'artist', label: 'Artist', kind: 'text', list: true },
    album_artist: { key: 'album_artist', label: 'Album Artist', kind: 'text', list: true },
    album: { key: 'album', label: 'Album', kind: 'text', list: true },
    genre: { key: 'genre', label: 'Genre', kind: 'text', list: true },
    composer: { key: 'composer', label: 'Composer', kind: 'text', list: true },
    year: { key: 'year', label: 'Year', kind: 'number' },
    track: { key: 'track', label: 'Track', kind: 'number' },
    track_total: { key: 'track_total', label: 'of', kind: 'number' },
    disc: { key: 'disc', label: 'Disc', kind: 'number' },
    disc_total: { key: 'disc_total', label: 'of', kind: 'number' },
    comment: { key: 'comment', label: 'Comment', kind: 'long' },
  };
  const KEYS = Object.keys(FIELDS) as EditField[];
  const LIST_FIELDS = KEYS.filter((k) => FIELDS[k].list);

  type Art = { kind: 'keep' } | { kind: 'set'; path: string; preview: string } | { kind: 'clear' };

  let initial = $state({} as Record<EditField, string>);
  let mixed = $state({} as Record<EditField, boolean>);
  let values = $state({} as Record<EditField, string>);
  let cleared = $state({} as Record<EditField, boolean>);
  let art = $state<Art>({ kind: 'keep' });
  let currentArt = $state<string | null>(null);
  let saving = $state(false);
  let suggestions = $state({} as Record<string, string[]>);
  let artRequest = 0;

  let multi = $derived(tracks.length > 1);
  // Order-independent: a filter can reorder the tracks being edited without changing them.
  let selectionKey = $derived(
    tracks
      .map((t) => t.id)
      .sort((a, b) => a - b)
      .join(','),
  );
  let withArt = $derived(tracks.filter((t) => t.has_art).length);

  const str = (v: string | number | null) => (v == null ? '' : String(v));

  function reset(source: Track[]) {
    const nextInitial = {} as Record<EditField, string>;
    const nextMixed = {} as Record<EditField, boolean>;
    for (const k of KEYS) {
      const vals = new Set(source.map((t) => str(t[k])));
      nextMixed[k] = vals.size > 1;
      nextInitial[k] = vals.size === 1 ? [...vals][0] : '';
    }
    initial = nextInitial;
    mixed = nextMixed;
    values = { ...nextInitial };
    cleared = Object.fromEntries(KEYS.map((k) => [k, false])) as Record<EditField, boolean>;
    art = { kind: 'keep' };
    loadArt(source);
  }

  async function loadArt(source: Track[]) {
    const req = ++artRequest;
    const first = source.find((t) => t.has_art);
    currentArt = null;
    if (!first) return;
    try {
      const url = await api.getArt(first.id);
      if (req === artRequest) currentArt = url;
    } catch {
      /* the file may have moved; the next refresh will sort it out */
    }
  }

  async function loadSuggestions() {
    const entries = await Promise.all(LIST_FIELDS.map(async (k) => [k, await api.distinct(k).catch(() => [])]));
    suggestions = Object.fromEntries(entries);
  }

  // Reset the form only when the selection itself changes, not when the list refreshes
  // underneath (e.g. the watcher noticed something), so in-progress edits survive.
  $effect(() => {
    selectionKey;
    untrack(() => reset(tracks));
  });

  $effect(() => {
    untrack(loadSuggestions);
  });

  function invalid(k: EditField): boolean {
    if (FIELDS[k].kind !== 'number' || cleared[k]) return false;
    const v = values[k]?.trim() ?? '';
    return v !== '' && !/^\d{1,9}$/.test(v);
  }

  let edits = $derived.by((): TagEdits => {
    const out: Record<string, unknown> = {};
    for (const k of KEYS) {
      const v = (values[k] ?? '').trim();
      if (cleared[k]) {
        out[k] = { op: 'clear' };
      } else if (v !== initial[k]) {
        // Bulk: a blank field means "leave as is". Single file: blanking clears it.
        if (v === '') {
          if (!multi) out[k] = { op: 'clear' };
        } else if (FIELDS[k].kind === 'number') {
          if (/^\d{1,9}$/.test(v)) out[k] = { op: 'set', value: Number(v) };
        } else {
          out[k] = { op: 'set', value: v };
        }
      }
    }
    if (art.kind === 'set') out.art = { op: 'set', value: art.path };
    if (art.kind === 'clear') out.art = { op: 'clear' };
    return out as TagEdits;
  });

  let hasErrors = $derived(KEYS.some(invalid));
  $effect(() => {
    dirty = Object.keys(edits).length > 0;
  });

  function toggleClear(k: EditField) {
    cleared[k] = !cleared[k];
    if (cleared[k]) values[k] = '';
    else values[k] = initial[k];
  }

  const IMAGE_EXT = /\.(jpe?g|png|gif|webp)$/i;
  const NO_TRACKS = 'Select the tracks to give this album art first.';
  const dialogOpen = () => !!document.querySelector('[aria-modal="true"]');

  async function chooseArt() {
    const path = await open({
      multiple: false,
      directory: false,
      title: 'Choose album art',
      filters: [{ name: 'Images', extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'JPG', 'JPEG', 'PNG'] }],
    });
    if (typeof path === 'string') setArtFromPath(path);
  }

  async function setArtFromPath(path: string) {
    try {
      art = { kind: 'set', path, preview: await api.imagePreview(path) };
    } catch (e) {
      toast(errorText(e), 'error');
    }
  }

  async function setArtFromBytes(data: Uint8Array) {
    try {
      setArtFromPath(await api.stageImage(data));
    } catch (e) {
      toast(errorText(e), 'error');
    }
  }

  /** A single image file path from pasted text: a path or file:// URI (as file managers copy). */
  function imagePathFrom(text: string): string | null {
    const lines = text
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter((l) => l && !l.startsWith('#'));
    if (lines.length !== 1) return null;
    // Explorer's "Copy as path" wraps the path in quotes.
    let path = lines[0].replace(/^"(.*)"$/, '$1');
    if (path.startsWith('file://')) {
      try {
        // file:///C:/x.jpg has the pathname /C:/x.jpg.
        path = decodeURIComponent(new URL(path).pathname).replace(/^\/([A-Za-z]:\/)/, '$1');
      } catch {
        return null;
      }
    }
    const absolute = path.startsWith('/') || /^[A-Za-z]:[\\/]/.test(path) || path.startsWith('\\\\');
    return absolute && IMAGE_EXT.test(path) ? path : null;
  }

  // Ctrl+V anywhere but a text field sets the album art from a copied image or image file.
  function onPaste(e: ClipboardEvent) {
    const target = e.target as HTMLElement | null;
    if (target?.closest('input, textarea, [contenteditable]') || !e.clipboardData || dialogOpen()) return;
    const data = e.clipboardData;
    const file =
      [...data.files].find((f) => f.type.startsWith('image/')) ??
      [...data.items].find((i) => i.kind === 'file' && i.type.startsWith('image/'))?.getAsFile();
    const path = file ? null : imagePathFrom(data.getData('text/uri-list') || data.getData('text/plain'));
    if (!file && !path) return;
    e.preventDefault();
    if (!tracks.length) return toast(NO_TRACKS);
    if (file) file.arrayBuffer().then((b) => setArtFromBytes(new Uint8Array(b)));
    else setArtFromPath(path!);
  }

  // Files dragged in from a file manager arrive through Tauri (with real paths), not as DOM
  // drop events. Dropping one image anywhere on this panel sets it as the album art.
  let dragPaths = $state<string[] | null>(null);
  let dragOver = $state(false);
  let dragIsImage = $derived(dragPaths?.length === 1 && IMAGE_EXT.test(dragPaths[0]));

  function overPanel(position: { x: number; y: number }) {
    if (dialogOpen()) return false;
    const r = panel?.getBoundingClientRect();
    const x = position.x / devicePixelRatio;
    const y = position.y / devicePixelRatio;
    return !!r && x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
  }

  onMount(() => {
    const unlisten = getCurrentWebview().onDragDropEvent(({ payload }) => {
      if (payload.type === 'enter') {
        dragPaths = payload.paths;
        dragOver = overPanel(payload.position);
      } else if (payload.type === 'over') {
        dragOver = overPanel(payload.position);
      } else if (payload.type === 'drop') {
        const onPanel = overPanel(payload.position);
        dragPaths = null;
        dragOver = false;
        if (!onPanel || dialogOpen()) return;
        if (!tracks.length) toast(NO_TRACKS);
        else if (payload.paths.length !== 1 || !IMAGE_EXT.test(payload.paths[0])) toast('Drop a single JPEG, PNG, GIF or WebP image.', 'error');
        else setArtFromPath(payload.paths[0]);
      } else {
        dragPaths = null;
        dragOver = false;
      }
    });
    return () => {
      unlisten.then((f) => f());
    };
  });

  /** Whether the edits can be saved as they stand (no invalid numbers). */
  export function canSave() {
    return !hasErrors;
  }

  let panel: HTMLElement;

  /** Moves keyboard focus to the first tag field. */
  export function focusFirstField() {
    panel?.querySelector<HTMLElement>('.fields input')?.focus();
  }

  /** Throws the edits away. */
  export function discard() {
    reset(tracks);
  }

  /** Saves the edits; resolves to whether they were written (at least in part). */
  export async function save(): Promise<boolean> {
    if (!dirty || hasErrors || saving) return false;
    const ids = tracks.map((t) => t.id);
    saving = true;
    try {
      const attempted = $state.snapshot(edits) as TagEdits;
      const result = await api.writeTags(ids, attempted);
      reset(await api.getTracks(ids));
      loadSuggestions();
      onsaved(ids, attempted, result);
      return true;
    } catch (e) {
      toast(errorText(e), 'error');
      return false;
    } finally {
      saving = false;
    }
  }

  function onKey(e: KeyboardEvent) {
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
      e.preventDefault();
      save();
    }
  }

  function placeholder(k: EditField) {
    if (cleared[k]) return 'will be cleared';
    // The header already says blank fields are left unchanged; keep this short enough for the
    // narrow number fields.
    if (mixed[k]) return multi ? (FIELDS[k].kind === 'number' ? 'Mixed' : 'Mixed values') : '';
    return '';
  }
</script>

<svelte:window onkeydown={onKey} onpaste={onPaste} />

{#snippet field(k: EditField, extraClass = '')}
  {@const def = FIELDS[k]}
  <label class="field {extraClass}" class:is-cleared={cleared[k]} class:is-changed={edits[k] && !cleared[k]}>
    <span class="label">{def.label}</span>
    <span class="control">
      {#if def.kind === 'long'}
        <textarea rows="3" bind:value={values[k]} placeholder={placeholder(k)} disabled={cleared[k]}></textarea>
      {:else}
        <input
          type="text"
          inputmode={def.kind === 'number' ? 'numeric' : undefined}
          class:invalid={invalid(k)}
          bind:value={values[k]}
          placeholder={placeholder(k)}
          disabled={cleared[k]}
          list={def.list ? `list-${k}` : undefined}
          spellcheck="false"
        />
      {/if}
      <button
        type="button"
        class="ghost clear"
        title={cleared[k] ? 'Undo clear' : `Clear ${def.label.toLowerCase()} on ${multi ? 'all selected files' : 'this file'}`}
        onclick={() => toggleClear(k)}>{cleared[k] ? '↺' : '×'}</button
      >
    </span>
  </label>
{/snippet}

<aside class="editor" class:drop-target={dragOver && dragIsImage && tracks.length} bind:this={panel}>
  {#if tracks.length === 0}
    <div class="placeholder">
      <p>Select one or more tracks to edit their tags.</p>
      <p class="muted">Shift-click selects a range, Ctrl-click toggles, Ctrl+A selects everything shown.</p>
    </div>
  {:else}
    <header>
      <div class="title-row">
        <h2>{multi ? `Editing ${tracks.length} files` : 'Editing 1 file'}</h2>
        {#if !multi}
          {@const isCurrent = playingId === tracks[0].id}
          <button class="listen" onclick={() => onplay(tracks[0].id, true)} title="Listen to this file (Space in the list)">
            {isCurrent && playing ? '❚❚ Pause' : '▶ Listen'}
          </button>
        {/if}
      </div>
      {#if multi}<p class="muted hint">Blank fields are left unchanged. Use × to clear a field on every file.</p>{/if}
    </header>

    <div class="scroll">
      <section class="art">
        <div class="art-frame" class:pending={art.kind !== 'keep'} title="Drop or paste an image to use it as the album art">
          {#if dragOver && dragIsImage}
            <span class="drop-hint">Drop to use as album art</span>
          {:else if art.kind === 'set'}
            <img src={art.preview} alt="New album art" />
          {:else if art.kind === 'clear'}
            <span class="muted">Art will be removed</span>
          {:else if currentArt}
            <img src={currentArt} alt="Album art" />
          {:else}
            <span class="muted">No album art<br /><small>Drop or paste an image</small></span>
          {/if}
        </div>
        <div class="art-meta">
          {#if multi}
            <span class="muted">{withArt} of {tracks.length} have art{withArt ? '; showing the first' : ''}</span>
          {/if}
          <div class="art-buttons">
            <button onclick={chooseArt} title="Choose an image file (or drop or paste one onto the editor)"
              >{art.kind === 'set' ? 'Change…' : 'Set image…'}</button
            >
            <button class="danger" onclick={() => (art = { kind: 'clear' })} disabled={art.kind === 'clear' || (!withArt && art.kind === 'keep')}
              >Remove</button
            >
            {#if art.kind !== 'keep'}
              <button class="ghost" onclick={() => (art = { kind: 'keep' })}>Undo</button>
            {/if}
          </div>
        </div>
      </section>

      <section class="fields">
        {@render field('title')}
        {@render field('artist')}
        {@render field('album')}
        {@render field('album_artist')}
        {@render field('genre')}
        <div class="pair">
          {@render field('track', 'num')}
          {@render field('track_total', 'num total')}
        </div>
        <div class="pair">
          {@render field('disc', 'num')}
          {@render field('disc_total', 'num total')}
        </div>
        {@render field('year', 'num')}
        {@render field('composer')}
        {@render field('comment')}
      </section>

      {#if !multi}
        {@const t = tracks[0]}
        <section class="info">
          <div><span class="muted">File</span> {t.path}</div>
          <div>
            <span class="muted">Length</span>
            {formatDuration(t.duration_ms)}
            <span class="muted">· Bitrate</span>
            {t.bitrate ?? '?'} kbps
            <span class="muted">· Size</span>
            {(t.size / 1048576).toFixed(1)} MB
          </div>
          {#if t.error}<div class="error">Tag error: {t.error}</div>{/if}
        </section>
      {/if}
    </div>

    <footer>
      <button class="ghost" disabled={!dirty || saving} onclick={() => reset(tracks)}>Revert</button>
      <button class="primary" disabled={!dirty || hasErrors || saving} onclick={save}>
        {saving ? 'Saving…' : multi ? `Save to ${tracks.length} files` : 'Save'}
      </button>
    </footer>
  {/if}

  {#each LIST_FIELDS as k (k)}
    <datalist id="list-{k}">
      {#each suggestions[k] ?? [] as v (v)}<option value={v}></option>{/each}
    </datalist>
  {/each}
</aside>

<style>
  .editor {
    /* Shrinks in narrow (e.g. tiled) windows so the table keeps some room. */
    width: clamp(290px, 32vw, 380px);
    flex-shrink: 0;
    display: flex;
    flex-direction: column;
    background: var(--navy-900);
    border-left: 1px solid var(--navy-800);
    min-height: 0;
  }
  .placeholder {
    padding: 40px 28px;
    text-align: center;
    line-height: 1.6;
  }
  header {
    padding: 14px 16px 8px;
    border-bottom: 1px solid var(--navy-800);
  }
  .title-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }
  .listen {
    padding: 3px 10px;
    font-size: 12px;
    border-radius: 14px;
    border-color: var(--cerulean);
    color: var(--cerulean-light);
  }
  h2 {
    margin: 0;
    font-size: 15px;
    color: var(--cerulean-light);
  }
  .hint {
    margin: 4px 0 0;
    font-size: 12px;
  }
  .scroll {
    flex: 1;
    overflow-y: auto;
    padding: 14px 16px;
  }
  .art {
    display: flex;
    gap: 12px;
    margin-bottom: 16px;
  }
  .art-frame {
    width: 132px;
    height: 132px;
    flex-shrink: 0;
    display: grid;
    place-items: center;
    background: var(--navy-950);
    border: 1px solid var(--navy-700);
    border-radius: var(--radius);
    overflow: hidden;
    text-align: center;
    font-size: 12px;
    padding: 4px;
  }
  .editor.drop-target {
    box-shadow: inset 0 0 0 2px var(--cerulean);
  }
  .drop-target .art-frame {
    border: 2px dashed var(--cerulean);
    background: var(--cerulean-wash);
  }
  .drop-hint {
    color: var(--cerulean-light);
    font-weight: 600;
  }
  .art-frame small {
    color: var(--text-faint);
  }
  .art-frame.pending {
    border-color: var(--cerulean);
    box-shadow: 0 0 0 2px var(--cerulean-wash);
  }
  .art-frame img {
    width: 100%;
    height: 100%;
    object-fit: contain;
  }
  .art-meta {
    display: flex;
    flex-direction: column;
    justify-content: flex-end;
    gap: 8px;
    font-size: 12px;
  }
  .art-buttons {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .fields {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .field {
    display: flex;
    flex-direction: column;
    gap: 3px;
    flex: 1;
    min-width: 0;
  }
  .label {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--text-muted);
  }
  .is-changed .label {
    color: var(--cerulean-light);
  }
  .is-changed .label::after {
    content: ' •';
  }
  .is-cleared .label {
    color: var(--warning);
  }
  .control {
    display: flex;
    gap: 2px;
    align-items: flex-start;
  }
  .control input,
  .control textarea {
    flex: 1;
    width: 100%;
  }
  .control textarea {
    resize: vertical;
  }
  .is-changed input,
  .is-changed textarea {
    border-color: var(--cerulean-deep);
  }
  .is-cleared input,
  .is-cleared textarea {
    border-style: dashed;
    border-color: var(--warning);
  }
  input.invalid {
    border-color: var(--danger);
  }
  .clear {
    width: 26px;
    height: 29px;
    padding: 0;
    font-size: 15px;
  }
  .pair {
    display: flex;
    gap: 10px;
  }
  .info {
    margin-top: 18px;
    padding-top: 12px;
    border-top: 1px solid var(--navy-800);
    font-size: 12px;
    line-height: 1.7;
    word-break: break-all;
  }
  .error {
    color: var(--danger);
  }
  footer {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    padding: 12px 16px;
    border-top: 1px solid var(--navy-800);
    background: var(--navy-850);
  }
</style>
