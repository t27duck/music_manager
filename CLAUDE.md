# CLAUDE.md

Working notes for this repo. See README.md for what the app does and the module layout.

## Building and checking

- There is **no Rust toolchain on the host**. All Rust builds, tests and lints run in the
  `music-manager-ubuntu` container via `make` (`make images` builds the containers once).
  For ad-hoc cargo commands, mirror the Makefile's `DOCKER_UBUNTU` invocation (runs as the
  host uid, mounts the repo at `/src` and the cargo cache from `~/.cache/music-manager-build`).
- Before calling a change done: `make check` (svelte-check, cargo check, clippy with
  `-D warnings`, `cargo fmt --check`) and `make test`. For UI changes also `npm run test:ui`.
- `cargo fmt` uses `src-tauri/rustfmt.toml` (width 120). Run it in the container.
- `make arch` packages `git archive HEAD`, so **commit before building the Arch package**.
- TypeScript is pinned to 6.x: svelte-check does not support TypeScript 7 yet.
- Tauri's compile-time context needs `build/` (the frontend output) to exist, so run
  `npm run build` (or create an empty `build/index.html`) before cargo on a fresh clone.

## Testing against real music

- The user's library at `~/Music/library` (~5,600 MP3s) is **read-only for testing**: mount it
  with `:ro`, and exercise writes or reorganizing only on copies in a scratch directory.
- Never mount a test folder at `/lib` in the container; it hides the system libraries.
- `src-tauri/examples/scan.rs` scans a folder into an in-memory index and reports timing and
  tag stats; `examples/play.rs` plays a file through the preview player (runs on the host
  for audio; build it in the container, then run `src-tauri/target/release/examples/play`).
- To run the app itself without touching the user's settings or index, point
  `XDG_CONFIG_HOME`/`XDG_DATA_HOME` at a scratch directory and pre-write
  `music-manager/config.json` with `{"library_path": "<copy of some albums>"}`.

## UI tests

`npm run test:ui` (host, needs Chromium) serves the frontend with Vite and drives it with
puppeteer against `tests/ui/mock-tauri.js`, which fakes Tauri's IPC: commands are recorded in
`window.__calls` and `window.__emit(event, payload)` delivers backend events. Add a test to the
`tests` object in `tests/ui/run.mjs` when changing UI behaviour; `SCREENSHOTS=1` saves
screenshots to `tests/ui/screenshots/` for a visual check. Keep the mock's command list in
step with `src/lib/api.ts`.

## Behaviour to preserve

- Files are the source of truth; the SQLite index is a cache and can always be rebuilt.
- Tags are written as ID3v2.4, ID3v1 is stripped on write, TYER migrates to TDRC, and frames
  the app doesn't edit must survive a write (see `tags.rs` tests).
- Bulk edit: a blank field is skipped; clearing is explicit (× button). Single-file edit: a
  blanked field clears. Album art edits touch the embedded front cover only.
- Reorganize skips conflicts, never overwrites, and prunes folders left without music;
  leftover images follow the album if all its files went to one folder, else are deleted.
- Anything touching files takes `AppState::op_lock` so the watcher can't race it. Drop the
  watcher *before* taking that lock (dropping waits for its handler, which may hold it).
- Packaging targets are `.deb` (Ubuntu 24.04+) and the Arch PKGBUILD only; no AppImage.
- UI palette is navy and cerulean; colours live as CSS variables in `src/app.css`.
