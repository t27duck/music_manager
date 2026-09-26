<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import { api, errorText, type ApplyResult, type Config, type PlanItem, type TokenInfo } from './api';
  import { toast } from './toast.svelte';

  let {
    ids,
    config,
    onclose,
    onconfig,
  }: { ids: number[]; config: Config; onclose: () => void; onconfig: (c: Config) => void } = $props();

  const MAX_ROWS = 1000;

  let template = $state(untrack(() => config.templates[0]) ?? '<AlbumArtist>/<Album>/<Track:2> <Title>');
  let tokens = $state<TokenInfo[]>([]);
  let plan = $state<PlanItem[]>([]);
  let error = $state<string | null>(null);
  let loading = $state(false);
  let applying = $state(false);
  let confirming = $state(false);
  let result = $state<ApplyResult | null>(null);
  let show = $state<'all' | 'move' | 'conflict' | 'error'>('all');
  let input = $state<HTMLInputElement>();
  let requestSeq = 0;

  let counts = $derived({
    move: plan.filter((p) => p.status === 'move').length,
    unchanged: plan.filter((p) => p.status === 'unchanged').length,
    conflict: plan.filter((p) => p.status === 'conflict').length,
    error: plan.filter((p) => p.status === 'error').length,
  });
  let shown = $derived(show === 'all' ? plan : plan.filter((p) => p.status === show));

  onMount(async () => {
    tokens = await api.templateTokens();
    input?.focus();
  });

  // Live preview, debounced while typing.
  $effect(() => {
    const t = template;
    const seq = ++requestSeq;
    confirming = false;
    const timer = setTimeout(async () => {
      loading = true;
      try {
        const items = await api.previewReorganize(ids, t);
        if (seq !== requestSeq) return;
        plan = items;
        error = null;
      } catch (e) {
        if (seq !== requestSeq) return;
        plan = [];
        error = errorText(e);
      } finally {
        if (seq === requestSeq) loading = false;
      }
    }, 250);
    return () => clearTimeout(timer);
  });

  function insertToken(token: string) {
    if (!input) return;
    const el = input;
    const start = el.selectionStart ?? template.length;
    const end = el.selectionEnd ?? template.length;
    template = template.slice(0, start) + token + template.slice(end);
    requestAnimationFrame(() => {
      el.focus();
      el.setSelectionRange(start + token.length, start + token.length);
    });
  }

  async function saveTemplate() {
    try {
      onconfig(await api.saveTemplate(template));
      toast('Template saved', 'success');
    } catch (e) {
      toast(errorText(e), 'error');
    }
  }

  async function removeTemplate(t: string) {
    onconfig(await api.removeTemplate(t));
  }

  async function apply() {
    applying = true;
    try {
      result = await api.applyReorganize(ids, template);
      onconfig(await api.getConfig());
      toast(`Moved ${result.moved} file${result.moved === 1 ? '' : 's'}`, result.failed.length ? 'error' : 'success');
    } catch (e) {
      toast(errorText(e), 'error');
    } finally {
      applying = false;
      confirming = false;
    }
  }

  function split(path: string): [string, string] {
    const i = path.lastIndexOf('/');
    return i < 0 ? ['', path] : [path.slice(0, i + 1), path.slice(i + 1)];
  }
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && !applying && onclose()} />

<div class="backdrop" role="presentation" onclick={(e) => e.target === e.currentTarget && !applying && onclose()}>
  <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="reorg-title">
    <header>
      <h2 id="reorg-title">Reorganize {ids.length} file{ids.length === 1 ? '' : 's'}</h2>
      <button class="ghost" onclick={onclose} disabled={applying} aria-label="Close">✕</button>
    </header>

    {#if result}
      <div class="result">
        <p><strong>{result.moved}</strong> moved, <strong>{result.skipped}</strong> skipped{result.removed_dirs ? `, ${result.removed_dirs} emptied folder${result.removed_dirs === 1 ? '' : 's'} removed` : ''}.</p>
        {#if result.failed.length}
          <p class="bad">{result.failed.length} failed:</p>
          <ul class="failures">
            {#each result.failed as [path, msg] (path)}<li><code>{path}</code>: {msg}</li>{/each}
          </ul>
        {/if}
        <div class="actions"><button class="primary" onclick={onclose}>Done</button></div>
      </div>
    {:else}
      <section class="template">
        <label for="template-input" class="label">Path template <span class="muted">(relative to the library folder; “/” makes folders)</span></label>
        <div class="row">
          <input id="template-input" bind:this={input} bind:value={template} spellcheck="false" autocomplete="off" />
          <button onclick={saveTemplate} disabled={!!error || config.templates.includes(template)}>Save</button>
        </div>
        <div class="tokens">
          {#each tokens as t (t.token)}
            <button class="token" title={t.description} onclick={() => insertToken(`<${t.token}>`)}>&lt;{t.token}&gt;</button>
          {/each}
          <button class="token" title="Track number zero-padded to 2 digits" onclick={() => insertToken('<Track:2>')}>&lt;Track:2&gt;</button>
        </div>
        {#if config.templates.length}
          <div class="saved">
            <span class="label">Saved</span>
            {#each config.templates as t (t)}
              <span class="chip" class:active={t === template}>
                <button class="chip-text" onclick={() => (template = t)}>{t}</button>
                <button class="chip-x" title="Forget this template" onclick={() => removeTemplate(t)}>×</button>
              </span>
            {/each}
          </div>
        {/if}
      </section>

      <section class="preview">
        {#if error}
          <p class="bad">{error}</p>
        {:else}
          <div class="tabs">
            <button class:active={show === 'all'} onclick={() => (show = 'all')}>All {plan.length}</button>
            <button class:active={show === 'move'} onclick={() => (show = 'move')}>Will move {counts.move}</button>
            <button class:active={show === 'conflict'} class:warn={counts.conflict > 0} onclick={() => (show = 'conflict')}>Conflicts {counts.conflict}</button>
            {#if counts.error}<button class:active={show === 'error'} class="warn" onclick={() => (show = 'error')}>Errors {counts.error}</button>{/if}
            <span class="muted unchanged">{counts.unchanged} already in place</span>
            {#if loading}<span class="muted">updating…</span>{/if}
          </div>
          <div class="list">
            {#each shown.slice(0, MAX_ROWS) as p (p.id)}
              {@const [toDir, toFile] = split(p.to)}
              <div class="item {p.status}">
                <div class="from" title={p.from}>{p.from}</div>
                <div class="to" title={p.message ?? p.to}>
                  {#if p.status === 'error'}
                    {p.message}
                  {:else}
                    <span class="arrow">→</span><span class="dir">{toDir}</span>{toFile}
                    {#if p.message}<span class="msg">{p.message}</span>{/if}
                  {/if}
                </div>
              </div>
            {/each}
            {#if shown.length > MAX_ROWS}
              <div class="more muted">…and {shown.length - MAX_ROWS} more</div>
            {/if}
          </div>
        {/if}
      </section>

      <footer>
        <span class="muted note">Conflicting files are skipped. Folders left without music are removed; their cover images follow the album when it moves as a whole.</span>
        <button class="ghost" onclick={onclose} disabled={applying}>Cancel</button>
        {#if confirming}
          <button class="primary" onclick={apply} disabled={applying}>{applying ? 'Moving…' : `Yes, move ${counts.move} files`}</button>
        {:else}
          <button class="primary" onclick={() => (confirming = true)} disabled={!!error || loading || counts.move === 0}>
            Move {counts.move} file{counts.move === 1 ? '' : 's'}
          </button>
        {/if}
      </footer>
    {/if}
  </div>
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 50;
    display: grid;
    place-items: center;
    background: rgba(2, 8, 20, 0.7);
  }
  .dialog {
    width: min(1100px, 94vw);
    height: min(780px, 90vh);
    display: flex;
    flex-direction: column;
    background: var(--navy-900);
    border: 1px solid var(--navy-700);
    border-radius: 10px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
  }
  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 14px 18px;
    border-bottom: 1px solid var(--navy-800);
  }
  h2 {
    margin: 0;
    font-size: 16px;
    color: var(--cerulean-light);
  }
  .template {
    padding: 14px 18px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    border-bottom: 1px solid var(--navy-800);
  }
  .label {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--text-muted);
  }
  .label .muted {
    text-transform: none;
    font-weight: normal;
    letter-spacing: 0;
  }
  .row {
    display: flex;
    gap: 8px;
  }
  .row input {
    flex: 1;
    font-family: ui-monospace, 'JetBrains Mono', 'Fira Code', monospace;
    font-size: 14px;
    padding: 8px 10px;
  }
  .tokens,
  .saved {
    display: flex;
    flex-wrap: wrap;
    gap: 5px;
    align-items: center;
  }
  .token {
    padding: 2px 8px;
    font-family: ui-monospace, monospace;
    font-size: 12px;
    background: var(--cerulean-wash);
    border-color: rgba(42, 159, 214, 0.4);
    color: var(--cerulean-light);
  }
  .chip {
    display: inline-flex;
    border: 1px solid var(--navy-700);
    border-radius: 14px;
    overflow: hidden;
  }
  .chip.active {
    border-color: var(--cerulean);
  }
  .chip button {
    border: none;
    border-radius: 0;
    background: var(--navy-850);
    padding: 2px 8px;
    font-family: ui-monospace, monospace;
    font-size: 12px;
  }
  .chip-x {
    color: var(--text-muted);
  }
  .preview {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
  }
  .tabs {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 10px 18px;
  }
  .tabs button {
    padding: 3px 10px;
    border-radius: 14px;
    font-size: 12px;
  }
  .tabs button.active {
    background: var(--cerulean-deep);
    border-color: var(--cerulean);
  }
  .tabs button.warn:not(.active) {
    border-color: var(--warning);
    color: var(--warning);
  }
  .unchanged {
    margin-left: 8px;
  }
  .list {
    flex: 1;
    overflow: auto;
    padding: 0 18px 10px;
    font-size: 12px;
  }
  .item {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
    padding: 4px 6px;
    border-bottom: 1px solid rgba(23, 55, 102, 0.5);
  }
  .item > div {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .from {
    color: var(--text-faint);
  }
  .arrow {
    color: var(--cerulean);
    margin-right: 6px;
  }
  .dir {
    color: var(--text-muted);
  }
  .item.unchanged .to {
    color: var(--text-faint);
  }
  .item.conflict .to,
  .item.error .to {
    color: var(--warning);
  }
  .msg {
    margin-left: 8px;
    font-style: italic;
  }
  .more {
    padding: 8px;
  }
  .bad {
    color: var(--danger);
    padding: 0 18px;
  }
  footer {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 12px 18px;
    border-top: 1px solid var(--navy-800);
    background: var(--navy-850);
    border-radius: 0 0 10px 10px;
  }
  .note {
    flex: 1;
    font-size: 12px;
  }
  .result {
    padding: 24px 18px;
    overflow: auto;
  }
  .failures {
    font-size: 12px;
  }
  .actions {
    margin-top: 18px;
  }
</style>
