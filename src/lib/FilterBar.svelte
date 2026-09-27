<script lang="ts">
  import { FILTER_FIELDS, OPS, fieldKind, type FilterRow } from './api';
  import Menu, { type MenuItem } from './Menu.svelte';

  let { search = $bindable(), filters = $bindable() }: { search: string; filters: FilterRow[] } = $props();

  let searchInput: HTMLInputElement;

  function addFilter() {
    filters = [...filters, { field: 'artist', op: 'contains', value: '' }];
  }

  // Ready-made filters for tidying the library. Choosing one adds it to the current filters.
  const PROBLEMS: { label: string; filter: FilterRow }[] = [
    { label: 'Tag errors', filter: { field: 'has_error', op: 'yes', value: '' } },
    { label: 'No album art', filter: { field: 'has_art', op: 'no', value: '' } },
    { label: 'No title', filter: { field: 'title', op: 'empty', value: '' } },
    { label: 'No artist', filter: { field: 'artist', op: 'empty', value: '' } },
    { label: 'No album', filter: { field: 'album', op: 'empty', value: '' } },
    { label: 'No track number', filter: { field: 'track', op: 'empty', value: '' } },
    { label: 'No year', filter: { field: 'year', op: 'empty', value: '' } },
  ];
  const same = (a: FilterRow, b: FilterRow) => a.field === b.field && a.op === b.op;

  let problemsMenu = $state<{ x: number; y: number } | null>(null);
  let problemItems = $derived<MenuItem[]>(
    PROBLEMS.map((p) => ({
      label: p.label,
      disabled: filters.some((f) => same(f, p.filter)),
      action: () => (filters = [...filters.filter((f) => !(f.field === p.filter.field && !f.value.trim())), { ...p.filter }]),
    })),
  );

  function removeFilter(i: number) {
    filters = filters.filter((_, j) => j !== i);
  }

  function changeField(i: number, field: string) {
    const ops = OPS[fieldKind(field)];
    const f = filters[i];
    const keepOp = ops.some((o) => o.key === f.op);
    filters[i] = { field, op: keepOp ? f.op : ops[0].key, value: f.value };
  }

  function needsValue(f: FilterRow) {
    return OPS[fieldKind(f.field)].find((o) => o.key === f.op)?.needsValue ?? true;
  }

  function onKey(e: KeyboardEvent) {
    if ((e.ctrlKey || e.metaKey) && e.key === 'f') {
      e.preventDefault();
      searchInput?.focus();
      searchInput?.select();
    }
  }
</script>

<svelte:window onkeydown={onKey} />

<div class="bar">
  <div class="search">
    <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></svg>
    <input
      bind:this={searchInput}
      type="search"
      placeholder="Search title, artist, album, genre, path…  (Ctrl+F)"
      bind:value={search}
      onkeydown={(e) => e.key === 'Escape' && (search = '')}
    />
  </div>
  <button onclick={addFilter}>+ Filter</button>
  <button
    aria-haspopup="menu"
    aria-expanded={!!problemsMenu}
    title="Show tracks with tag errors, no album art or missing tags"
    onclick={(e) => {
      const r = e.currentTarget.getBoundingClientRect();
      problemsMenu = { x: r.left, y: r.bottom + 4 };
    }}>Find problems ▾</button
  >
  {#if filters.length || search}
    <button
      class="ghost"
      onclick={() => {
        filters = [];
        search = '';
      }}>Clear all</button
    >
  {/if}
</div>

{#if problemsMenu}
  <Menu x={problemsMenu.x} y={problemsMenu.y} items={problemItems} label="Find problems" onclose={() => (problemsMenu = null)} />
{/if}

{#if filters.length}
  <div class="filters">
    {#each filters as f, i (i)}
      <div class="filter">
        <select value={f.field} onchange={(e) => changeField(i, e.currentTarget.value)}>
          {#each FILTER_FIELDS as field (field.key)}
            <option value={field.key}>{field.label}</option>
          {/each}
        </select>
        <select bind:value={filters[i].op}>
          {#each OPS[fieldKind(f.field)] as op (op.key)}
            <option value={op.key}>{op.label}</option>
          {/each}
        </select>
        {#if needsValue(f)}
          <!-- svelte-ignore a11y_autofocus -->
          <input
            class="value"
            type={fieldKind(f.field) === 'number' ? 'number' : 'text'}
            bind:value={filters[i].value}
            placeholder="value"
            autofocus
          />
        {/if}
        <button class="ghost remove" title="Remove filter" onclick={() => removeFilter(i)}>×</button>
      </div>
    {/each}
  </div>
{/if}

<style>
  .bar {
    display: flex;
    gap: 8px;
    align-items: center;
    padding: 10px 14px;
    background: var(--navy-900);
    border-bottom: 1px solid var(--navy-800);
  }
  .search {
    position: relative;
    flex: 1;
    max-width: 640px;
    display: flex;
  }
  .search svg {
    position: absolute;
    left: 9px;
    top: 50%;
    width: 15px;
    height: 15px;
    transform: translateY(-50%);
    fill: none;
    stroke: var(--text-muted);
    stroke-width: 2;
    stroke-linecap: round;
  }
  .search input {
    flex: 1;
    padding-left: 30px;
    height: 32px;
  }
  .filters {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    padding: 8px 14px;
    background: var(--navy-900);
    border-bottom: 1px solid var(--navy-800);
  }
  .filter {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 3px 3px 3px 6px;
    background: var(--cerulean-wash);
    border: 1px solid rgba(42, 159, 214, 0.45);
    border-radius: 16px;
  }
  .filter select,
  .filter input {
    padding: 3px 6px;
    border-radius: 12px;
  }
  .filter .value {
    width: 150px;
  }
  .filter .remove {
    border-radius: 50%;
    width: 24px;
    height: 24px;
    padding: 0;
    font-size: 16px;
    line-height: 1;
  }
</style>
