<script lang="ts">
  import { onMount } from 'svelte';
  import type { WriteFailure } from './api';
  import { copyText } from './toast.svelte';

  let {
    failures,
    saved,
    retrying,
    onretry,
    onselect,
    onforget,
    onclose,
  }: {
    failures: WriteFailure[];
    /** How many files the save that just finished did write; null when reopened later. */
    saved: number | null;
    retrying: boolean;
    onretry: () => void;
    onselect: () => void;
    onforget: () => void;
    onclose: () => void;
  } = $props();

  let dialog: HTMLDivElement;
  const plural = (n: number, word: string) => `${n.toLocaleString()} ${word}${n === 1 ? '' : 's'}`;
  let selectable = $derived(failures.some((f) => f.path));

  onMount(() => {
    const previous = document.activeElement as HTMLElement | null;
    dialog.querySelector<HTMLElement>('.primary')?.focus();
    return () => previous?.focus();
  });

  function copyList() {
    const text = failures.map((f) => `${f.path || `(file #${f.id})`}\t${f.message}`).join('\n');
    copyText(text, `Copied ${plural(failures.length, 'line')}`);
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape' && !retrying) {
      e.preventDefault();
      onclose();
    } else if (e.key === 'Tab') {
      const buttons = [...dialog.querySelectorAll<HTMLButtonElement>('button:not(:disabled)')];
      const i = buttons.indexOf(document.activeElement as HTMLButtonElement);
      e.preventDefault();
      buttons[(i + (e.shiftKey ? buttons.length - 1 : 1)) % buttons.length]?.focus();
    }
    e.stopPropagation();
  }
</script>

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="backdrop" onclick={(e) => e.target === e.currentTarget && !retrying && onclose()}>
  <div
    class="dialog"
    role="alertdialog"
    aria-modal="true"
    aria-labelledby="failures-title"
    aria-describedby="failures-summary"
    tabindex="-1"
    bind:this={dialog}
    onkeydown={onKey}
  >
    <header>
      <h2 id="failures-title">{plural(failures.length, 'file')} {failures.length === 1 ? 'wasn’t' : 'weren’t'} saved</h2>
      <p id="failures-summary" class="muted">
        {#if saved}
          The other {plural(saved, 'file')} {saved === 1 ? 'was' : 'were'} saved.
        {/if}
        {failures.length === 1 ? 'This file keeps its' : 'These files keep their'} old tags. Fix the problem, for example a file that’s read-only or in use, then retry.
      </p>
    </header>

    <ul class="list">
      {#each failures as f (f.id)}
        <li>
          <span class="path" title={f.path}>{f.path || `File #${f.id}`}</span>
          <span class="message">{f.message}</span>
        </li>
      {/each}
    </ul>

    <footer>
      <button class="ghost" onclick={onforget} disabled={retrying} title="Stop marking these files as not saved">Clear list</button>
      <span class="spacer"></span>
      <button onclick={copyList}>Copy list</button>
      <button onclick={onselect} disabled={retrying || !selectable}>Select these files</button>
      <button class="primary" onclick={onretry} disabled={retrying}>{retrying ? 'Retrying…' : 'Retry'}</button>
      <button class="ghost" onclick={onclose} disabled={retrying}>Close</button>
    </footer>
  </div>
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 60;
    display: grid;
    place-items: center;
    padding: 16px;
    background: rgba(2, 8, 20, 0.6);
  }
  .dialog {
    width: min(720px, 100%);
    max-height: min(600px, 100%);
    display: flex;
    flex-direction: column;
    background: var(--navy-900);
    border: 1px solid var(--navy-700);
    border-radius: 10px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
    outline: none;
  }
  header {
    padding: 16px 20px 12px;
    border-bottom: 1px solid var(--navy-800);
  }
  h2 {
    margin: 0;
    font-size: 15px;
    color: var(--danger);
  }
  header p {
    margin: 6px 0 0;
    line-height: 1.5;
  }
  .list {
    flex: 1;
    min-height: 0;
    overflow: auto;
    margin: 0;
    padding: 6px 20px;
    list-style: none;
    font-size: 12px;
  }
  .list li {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 6px 0;
    border-bottom: 1px solid rgba(23, 55, 102, 0.5);
  }
  .path {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .message {
    color: var(--text-muted);
    overflow-wrap: anywhere;
  }
  footer {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
    padding: 12px 20px;
    border-top: 1px solid var(--navy-800);
    background: var(--navy-850);
    border-radius: 0 0 10px 10px;
  }
  .spacer {
    flex: 1;
  }
</style>
