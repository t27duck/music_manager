<script lang="ts" module>
  export type MenuItem =
    | {
        label: string;
        /** Keyboard shortcut shown at the right, e.g. "Space". */
        hint?: string;
        /** Set (true or false) to make this a check item. */
        checked?: boolean;
        disabled?: boolean;
        /** Leave the menu open after choosing, e.g. to toggle several check items. */
        keepOpen?: boolean;
        action: () => void;
      }
    | 'separator';
</script>

<script lang="ts">
  import { onMount, tick } from 'svelte';

  let {
    x,
    y,
    items,
    label,
    onclose,
  }: {
    /** Where to open, in viewport pixels; the menu moves to stay on screen. */
    x: number;
    y: number;
    items: MenuItem[];
    label: string;
    onclose: () => void;
  } = $props();

  let menu: HTMLDivElement;
  let left = $state(0);
  let top = $state(0);
  let hasChecks = $derived(items.some((i) => i !== 'separator' && i.checked !== undefined));

  onMount(() => {
    const previous = document.activeElement as HTMLElement | null;
    const { width, height } = menu.getBoundingClientRect();
    left = Math.max(4, Math.min(x, window.innerWidth - width - 4));
    top = Math.max(4, Math.min(y, window.innerHeight - height - 4));
    enabled()[0]?.focus();
    return () => previous?.focus();
  });

  const enabled = () => [...menu.querySelectorAll<HTMLButtonElement>('button:not(:disabled)')];

  async function choose(item: Exclude<MenuItem, 'separator'>) {
    if (item.keepOpen) return item.action();
    // Close (and hand focus back) first, so the action can move focus somewhere else.
    onclose();
    await tick();
    item.action();
  }

  function onKey(e: KeyboardEvent) {
    const buttons = enabled();
    const i = buttons.indexOf(document.activeElement as HTMLButtonElement);
    const focus = (n: number) => buttons[(n + buttons.length) % buttons.length]?.focus();
    if (e.key === 'ArrowDown') focus(i + 1);
    else if (e.key === 'ArrowUp') focus(i < 0 ? -1 : i - 1);
    else if (e.key === 'Home') focus(0);
    else if (e.key === 'End') focus(-1);
    else if (e.key === 'Escape' || e.key === 'Tab') onclose();
    else return;
    e.preventDefault();
    e.stopPropagation();
  }

  // Right-clicking elsewhere closes this menu and passes the click on, so another menu can open.
  function onBackdropContextMenu(e: MouseEvent) {
    e.preventDefault();
    onclose();
    const target = document.elementsFromPoint(e.clientX, e.clientY).find((el) => !el.closest('.menu-layer'));
    target?.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: e.clientX, clientY: e.clientY }));
  }
</script>

<div class="menu-layer">
  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
  <div class="backdrop" onclick={onclose} oncontextmenu={onBackdropContextMenu}></div>
  <div
    class="menu"
    class:checks={hasChecks}
    role="menu"
    aria-label={label}
    tabindex="-1"
    bind:this={menu}
    style:left="{left}px"
    style:top="{top}px"
    onkeydown={onKey}
    oncontextmenu={(e) => e.preventDefault()}
  >
    {#each items as item, i (i)}
      {#if item === 'separator'}
        <hr />
      {:else}
        <button
          role={item.checked === undefined ? 'menuitem' : 'menuitemcheckbox'}
          aria-checked={item.checked}
          disabled={item.disabled}
          onclick={() => choose(item)}
        >
          {#if hasChecks}<span class="check">{item.checked ? '✓' : ''}</span>{/if}
          <span class="label">{item.label}</span>
          {#if item.hint}<span class="hint">{item.hint}</span>{/if}
        </button>
      {/if}
    {/each}
  </div>
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 40;
  }
  .menu {
    position: fixed;
    z-index: 41;
    min-width: 190px;
    max-width: min(320px, calc(100vw - 8px));
    max-height: calc(100vh - 8px);
    overflow-y: auto;
    padding: 4px;
    display: flex;
    flex-direction: column;
    background: var(--navy-850);
    border: 1px solid var(--navy-600);
    border-radius: var(--radius);
    box-shadow: 0 8px 28px rgba(0, 0, 0, 0.5);
    outline: none;
  }
  button {
    display: flex;
    align-items: center;
    gap: 16px;
    text-align: left;
    border: none;
    background: transparent;
    padding: 5px 10px;
    border-radius: 4px;
  }
  .checks button {
    padding-left: 6px;
    gap: 0;
  }
  button:hover:not(:disabled),
  button:focus-visible {
    background: var(--navy-700);
    outline: none;
  }
  .label {
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .check {
    width: 20px;
    flex-shrink: 0;
    color: var(--cerulean-light);
  }
  .hint {
    color: var(--text-faint);
    font-size: 12px;
  }
  .checks .hint {
    margin-left: 16px;
  }
  hr {
    width: 100%;
    border: none;
    border-top: 1px solid var(--navy-700);
    margin: 4px 0;
  }
</style>
