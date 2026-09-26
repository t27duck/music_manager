# MusicManager

A desktop app for managing a local MP3 library on Linux (Arch/Omarchy and Ubuntu).

The MP3 files are the source of truth. A SQLite index mirrors their tags so filtering and
sorting thousands of files is instant, and it is kept in sync by an incremental rescan at
startup plus live file watching while the app runs.

## Features

- **Browse and filter**: free-text search across tags and paths, plus any number of
  field filters (title, artist, album artist, album, genre, year, track/disc numbers,
  composer, comment, has album art, bitrate, duration, file path, folder, file name) with
  operators like *contains*, *is*, *starts with*, *is empty*, `>`, `≤`, …
- **Edit tags** on one file or many. In bulk editing, a blank field is skipped; use the
  × button beside a field to explicitly clear it on every selected file. Fields shared by
  all selected files are pre-filled; differing ones show *(multiple values)*.
- **Album art**: set (JPEG/PNG/GIF/WebP) or remove the embedded front cover on one or many
  files.
- **Reorganize** selected files with a path template, preview every move first, and skip
  conflicts. Folders left without music are removed; loose cover images and the like follow
  their album if it moved as a whole, otherwise they are deleted with the folder.

Tags are written as **ID3v2.4**. Any ID3v1 tag is removed on write (it can't hold the full
tag and would go stale), and a v2.3 year (`TYER`) is carried over to the v2.4 date frame.
Frames the app doesn't edit (lyrics, PRIV, ReplayGain, …) are preserved.

### Template tokens

| Token | Value |
| --- | --- |
| `<Artist>` | Track artist (*Unknown Artist* if blank) |
| `<AlbumArtist>` | Album artist, falling back to the track artist |
| `<Album>` | Album (*Unknown Album* if blank) |
| `<Title>` | Title, falling back to the original file name |
| `<Genre>` | Genre (*Unknown Genre* if blank) |
| `<Year>`, `<Composer>`, `<Bitrate>` | As named |
| `<Track>`, `<Disc>`, `<TrackTotal>`, `<DiscTotal>` | Numbers; add `:N` to zero-pad, e.g. `<Track:2>` → `07` |
| `<Filename>` | Original file name without extension |
| `<Dir>` | Original folder, relative to the library |

`/` in the template creates folders. Characters in tag values that would break a path
(`/ \ : * ? " < > |`) are replaced, brackets left empty by a blank token (`()`, `[]`) are
dropped, and the `.mp3` extension is always kept. Example:

```
<AlbumArtist>/<Album> (<Year>)/<Disc>-<Track:2> <Title>
→ Queen/Jazz (1978)/1-12 Don't Stop Me Now.mp3
```

### Keyboard

| Keys | Action |
| --- | --- |
| Click / Shift-click / Ctrl-click | Select / select range / toggle |
| ↑ ↓ PgUp PgDn Home End (+Shift) | Move (extend) selection |
| Ctrl+A / Esc | Select all shown / clear selection |
| Ctrl+F | Focus search |
| Ctrl+S | Save tag edits |

## Building

Everything builds inside Docker, so the host only needs Docker and `make`.

```sh
make images    # once: build the Ubuntu 24.04 and Arch build containers
make deb       # dist/MusicManager_<version>_amd64.deb
make arch      # dist/music-manager-<version>-1-x86_64.pkg.tar.zst
make package   # both
make test      # Rust unit tests
make check     # svelte-check, cargo check and clippy
```

`make arch` packages the **committed** tree (`git archive HEAD`), so commit first.
The `.deb` targets Ubuntu 24.04 and newer.

### Installing

```sh
sudo apt install ./dist/MusicManager_0.1.0_amd64.deb        # Ubuntu
sudo pacman -U dist/music-manager-0.1.0-1-x86_64.pkg.tar.zst  # Arch / Omarchy
```

### Developing on the host

With Rust, Node and `webkit2gtk-4.1` installed locally:

```sh
npm install
npm run tauri dev
```

## Files

| Path | Contents |
| --- | --- |
| `~/.config/music-manager/config.json` | Library folder and saved templates |
| `~/.local/share/music-manager/library.db` | SQLite index (safe to delete; it is rebuilt) |

The app sets `WEBKIT_DISABLE_DMABUF_RENDERER=1` unless you set it yourself, which avoids
blank windows with some GPU drivers (notably NVIDIA).

## Layout

```
src/                 Svelte 5 + TypeScript frontend
src-tauri/src/
  tags.rs            ID3 read/write and album art
  db.rs              SQLite index, filtering and sorting
  scanner.rs         incremental scan and path re-sync
  watcher.rs         inotify watching
  template.rs        path template rendering
  reorganize.rs      move planning, execution and folder pruning
  commands.rs        Tauri commands used by the UI
docker/              build containers
packaging/           desktop entry and Arch PKGBUILD
```
