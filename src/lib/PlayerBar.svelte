<script lang="ts">
  import { onMount } from 'svelte';
  import { api, formatDuration, type PlayerStatus, type Track } from './api';

  let { status }: { status: PlayerStatus } = $props();

  const VOLUME_KEY = 'music-manager.volume';

  let track = $state<Track | null>(null);
  let dragging = $state(false);
  let dragValue = $state(0);
  let volume = $state(0.8);

  let duration = $derived(status.duration_ms ?? 0);
  let position = $derived(dragging ? dragValue : Math.min(status.position_ms, duration || status.position_ms));

  // The playing track may be filtered out of the table, so look it up on its own.
  $effect(() => {
    const id = status.track_id;
    if (id == null) {
      track = null;
      return;
    }
    if (track?.id === id) return;
    api.getTracks([id]).then((rows) => {
      if (status.track_id === id) track = rows[0] ?? null;
    });
  });

  onMount(() => {
    try {
      const saved = Number(localStorage.getItem(VOLUME_KEY));
      if (saved >= 0 && saved <= 1 && localStorage.getItem(VOLUME_KEY) !== null) volume = saved;
    } catch {
      /* storage unavailable; keep the default */
    }
    api.playerVolume(volume);
  });

  function setVolume(v: number) {
    volume = v;
    api.playerVolume(v);
    try {
      localStorage.setItem(VOLUME_KEY, String(v));
    } catch {
      /* ignore */
    }
  }

  function commitSeek() {
    api.playerSeek(Math.round(dragValue));
    // Hold the dragged position briefly so the handle doesn't jump back before the
    // player reports the new position.
    setTimeout(() => (dragging = false), 300);
  }
</script>

<div class="player">
  <button class="round" title={status.playing ? 'Pause (Space)' : 'Play (Space)'} onclick={() => api.playerToggle()}>
    {#if status.playing}
      <svg viewBox="0 0 24 24"><rect x="6" y="5" width="4" height="14" rx="1" /><rect x="14" y="5" width="4" height="14" rx="1" /></svg>
    {:else}
      <svg viewBox="0 0 24 24"><path d="M8 5.5v13a1 1 0 0 0 1.5.86l10.5-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z" /></svg>
    {/if}
  </button>
  <button class="round small" title="Stop" onclick={() => api.playerStop()} aria-label="Stop">
    <svg viewBox="0 0 24 24"><rect x="6" y="6" width="12" height="12" rx="1.5" /></svg>
  </button>

  <div class="now" title={track?.path}>
    {#if status.error}
      <span class="error">{status.error}</span>
    {:else if track}
      <span class="title">{track.title || track.filename}</span>
      <span class="muted">{[track.artist, track.album].filter(Boolean).join(' — ')}</span>
    {/if}
  </div>

  <span class="time">{formatDuration(position)}</span>
  <input
    class="seek"
    type="range"
    min="0"
    max={duration || 1}
    step="100"
    value={position}
    disabled={!duration}
    style:--pct="{duration ? (100 * position) / duration : 0}%"
    oninput={(e) => {
      dragging = true;
      dragValue = Number(e.currentTarget.value);
    }}
    onchange={commitSeek}
  />
  <span class="time">{formatDuration(duration || null)}</span>

  <svg class="vol-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9h4l5-4v14l-5-4H4z" /><path class="wave" d="M16 8.5a5 5 0 0 1 0 7" /></svg>
  <input
    class="volume"
    type="range"
    min="0"
    max="1"
    step="0.05"
    value={volume}
    title="Volume {Math.round(volume * 100)}%"
    style:--pct="{volume * 100}%"
    oninput={(e) => setVolume(Number(e.currentTarget.value))}
  />
</div>

<style>
  .player {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 6px 14px;
    background: linear-gradient(90deg, var(--navy-850), var(--navy-900));
    border-top: 1px solid var(--cerulean-deep);
  }
  .round {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
    padding: 0;
    border-radius: 50%;
    background: var(--cerulean-deep);
    border-color: var(--cerulean);
  }
  .round:hover:not(:disabled) {
    background: var(--cerulean);
  }
  .round.small {
    width: 26px;
    height: 26px;
    background: var(--navy-800);
    border-color: var(--navy-600);
  }
  .round svg {
    width: 16px;
    height: 16px;
    fill: #fff;
  }
  .round.small svg {
    width: 11px;
    height: 11px;
    fill: var(--text);
  }
  .now {
    display: flex;
    flex-direction: column;
    min-width: 160px;
    max-width: 360px;
    overflow: hidden;
    line-height: 1.3;
  }
  .now span {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .title {
    font-weight: 600;
  }
  .now .muted {
    font-size: 12px;
  }
  .error {
    color: var(--danger);
    font-size: 12px;
  }
  .time {
    font-size: 12px;
    color: var(--text-muted);
    font-variant-numeric: tabular-nums;
    min-width: 36px;
    text-align: center;
  }
  input[type='range'] {
    -webkit-appearance: none;
    appearance: none;
    height: 4px;
    padding: 0;
    border: none;
    border-radius: 2px;
    background: linear-gradient(90deg, var(--cerulean) var(--pct), var(--navy-700) var(--pct));
    cursor: pointer;
  }
  input[type='range']:focus {
    box-shadow: none;
  }
  input[type='range']::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 13px;
    height: 13px;
    border-radius: 50%;
    background: var(--cerulean-light);
    border: 2px solid var(--navy-900);
  }
  .seek {
    flex: 1;
  }
  .volume {
    width: 90px;
  }
  .vol-icon {
    width: 16px;
    height: 16px;
    fill: var(--text-muted);
    stroke: var(--text-muted);
    stroke-width: 1.5;
  }
  .vol-icon .wave {
    fill: none;
    stroke-linecap: round;
  }
</style>
