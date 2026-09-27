<script lang="ts">
  import { onMount } from 'svelte';

  let {
    what,
    canSave,
    onchoose,
  }: {
    /** What has unsaved edits, e.g. “Song Title” or “3 files”. */
    what: string;
    canSave: boolean;
    onchoose: (choice: 'save' | 'discard' | 'cancel') => void;
  } = $props();

  let dialog: HTMLDivElement;
  let busy = $state(false);

  onMount(() => {
    const previous = document.activeElement as HTMLElement | null;
    dialog.querySelector<HTMLElement>(canSave ? '.primary' : '.discard')?.focus();
    return () => previous?.focus();
  });

  function choose(choice: 'save' | 'discard' | 'cancel') {
    if (busy) return;
    if (choice === 'save') busy = true;
    onchoose(choice);
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      choose('cancel');
    } else if (e.key === 'Tab') {
      // Keep focus inside the dialog.
      const buttons = [...dialog.querySelectorAll<HTMLButtonElement>('button:not(:disabled)')];
      const i = buttons.indexOf(document.activeElement as HTMLButtonElement);
      e.preventDefault();
      buttons[(i + (e.shiftKey ? buttons.length - 1 : 1)) % buttons.length]?.focus();
    }
    // Ctrl+S etc. shouldn't reach the rest of the app while this is open.
    e.stopPropagation();
  }
</script>

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="backdrop" onclick={(e) => e.target === e.currentTarget && choose('cancel')}>
  <div
    class="dialog"
    role="alertdialog"
    aria-modal="true"
    aria-labelledby="unsaved-title"
    aria-describedby="unsaved-body"
    tabindex="-1"
    bind:this={dialog}
    onkeydown={onKey}
  >
    <h2 id="unsaved-title">Save changes to {what}?</h2>
    <p id="unsaved-body" class="muted">
      {#if canSave}
        Your tag edits haven’t been saved. If you don’t save them, they’ll be lost.
      {:else}
        Some numbers aren’t valid, so the edits can’t be saved yet. Cancel to fix them, or discard the edits.
      {/if}
    </p>
    <div class="actions">
      <button class="danger discard" onclick={() => choose('discard')} disabled={busy}>Discard changes</button>
      <span class="spacer"></span>
      <button class="ghost" onclick={() => choose('cancel')} disabled={busy}>Cancel</button>
      <button class="primary" onclick={() => choose('save')} disabled={!canSave || busy}>{busy ? 'Saving…' : 'Save'}</button>
    </div>
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
    width: min(440px, 100%);
    padding: 18px 20px 16px;
    background: var(--navy-900);
    border: 1px solid var(--navy-700);
    border-radius: 10px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
    outline: none;
  }
  h2 {
    margin: 0;
    font-size: 15px;
    color: var(--cerulean-light);
    overflow-wrap: anywhere;
  }
  p {
    margin: 8px 0 18px;
    line-height: 1.5;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .spacer {
    flex: 1;
  }
</style>
