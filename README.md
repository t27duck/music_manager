# MusicManager

A local MP3 library manager. It scans a directory of MP3 files, caches their
metadata in SQLite, and lets you search, edit ID3 tags and album art, bulk-update
songs, reorganize files on disk from a path template, and upload new music — all
from a browser, with no external services.

Built with Rails 8.1 on Ruby 4.0: Hotwire (Turbo + Stimulus) over import maps,
TailwindCSS v4, SQLite, and SolidQueue/SolidCache/SolidCable in production.

## What it does

- **Sync** — scans `LIBRARY_ROOT` for MP3s, reads their ID3 tags, and removes
  songs whose files are gone. Progress streams to the browser live, and one
  unreadable file is reported rather than aborting the run. Files whose
  timestamp and size are unchanged are left unread, which takes a repeat sync of
  a ~4,900-song library from about 40 seconds to under one; **Full rescan**
  re-reads everything regardless.
- **Sync history** — every run is recorded: when it started, how long it took,
  how many files it saw, how many it skipped, and anything it could not import.
- **Browse** — sortable, paginated list with search-as-you-type across title,
  artist, album artist, album and genre, plus filters for individual fields,
  file path, and missing metadata. Or browse by **artist** and **album**: album
  identity comes from the ID3 album-artist frame, so a compilation stays one
  album instead of splitting into one per guest performer.
- **Play** — a bar pinned to the bottom of every page that keeps playing while
  you filter, sort, page and navigate. One track at a time; the server serves
  byte ranges, so the scrub bar really seeks.
- **Edit** — a modal for the full record, or double-click any cell to edit it in
  place. Every change is written back into the file's ID3v1 and ID3v2 tags; if
  the file cannot be written, the database is not changed either.
- **Album art** — view, replace and remove the embedded APIC image.
- **Bulk edit** — select songs and apply metadata or artwork to all of them,
  with per-song failures reported rather than silently swallowed.
- **Organize** — re-file songs under a path template such as
  `<Artist>/<Album>/<Track:2> - <Title>`, previewed before anything moves.
- **Select across pages** — a selection survives paging, filtering and sorting,
  and **Select all N matching** widens it to everything the current filter
  returns, not just the rows on screen.
- **Upload** — drag in files or whole folders; they land in `_NEW/` keeping
  their structure, and are imported as they arrive.

Bulk edits and file moves run in the background with a live progress bar, since
each changed song means rewriting a whole file. Only one long-running operation
runs at a time — a sync prunes rows while an organize moves the files under
them, so they are never allowed to overlap.

The layout is built for a desktop screen but collapses to one card per song on a
phone, with no sideways scrolling.

## Requirements

- Ruby 4.0.6 (see `.ruby-version`)
- SQLite 3

A devcontainer is provided (`.devcontainer/`) with Ruby, SQLite, and a headless
Chrome container for system tests already wired up.

## Getting started

```bash
bin/setup            # install gems, prepare the database, start the dev server
bin/setup --reset    # same, but drop and recreate the database first
```

Then open http://localhost:3000.

To run the server on its own:

```bash
bin/dev              # web + tailwind watcher, port 3000
```

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `LIBRARY_ROOT` | `./library` | Directory scanned for MP3 files. Uploads land in `_NEW/` inside it. |
| `PORT` | `3000` | Development server port. |

Timestamps render in the zone set by `config.time_zone` in `config/application.rb`,
currently US Eastern. Change it there if you are somewhere else.

Album and artist browsing reads the ID3 album-artist (TPE2) frame. If you are
upgrading a library that predates it, the next sync re-reads every file once by
itself — `LibrarySync::TAG_EPOCH` handles that, so there is nothing to run by
hand.

The library directory is gitignored — it holds your music, not source.

```bash
LIBRARY_ROOT=/media/music bin/dev
```

There is nothing to seed: every song is derived from a file on disk. Point
`LIBRARY_ROOT` at your music and run a sync, either from the **Sync library**
button or with `bin/rails runner 'LibrarySync.call'`.

MusicManager writes to your files. It only ever touches MP3s inside
`LIBRARY_ROOT`, but tags are rewritten in place and *Delete song* removes the
file from disk — keep a backup you trust before pointing it at an irreplaceable
library.

## Testing

```bash
bin/rails test           # unit, model, controller, integration
bin/rails test:system    # browser tests (needs the selenium container)
bin/rubocop              # Rails Omakase style
bin/ci                   # full pipeline: setup, lint, audit, brakeman, tests
```

Tests default `LIBRARY_ROOT` to `test/library/` so they can never touch your real
library. File-manipulating tests copy fixtures from `test/fixtures/files/` into a
per-test temp directory.

## Deployment

The app ships with a production `Dockerfile` and is Kamal-ready. In production the
four SQLite databases (primary, cache, queue, cable) live in a persistent volume —
set `RAILS_MASTER_KEY`, mount a volume for `storage/`, and mount your music at
`LIBRARY_ROOT`.

```bash
docker build -t music_manager .
docker run -d -p 80:80 \
  -e RAILS_MASTER_KEY=<config/master.key> \
  -e LIBRARY_ROOT=/music \
  -v music_storage:/rails/storage \
  -v /path/to/music:/music \
  music_manager
```

Background jobs run inside Puma when `SOLID_QUEUE_IN_PUMA` is set, or as a separate
`bin/jobs` process. Either way the worker must share a filesystem with the web
process: it reads the music at `LIBRARY_ROOT`, and album art for a bulk edit is
handed over as a file under `tmp/`. Running workers on a separate host is not
supported.

## Project layout notes

- `CLAUDE.md` — the feature spec and working conventions.
- `TODO.md` — step-by-step implementation plan and progress.
