# MusicManager

A local MP3 library manager. It scans a directory of MP3 files, caches their
metadata in SQLite, and lets you search, edit ID3 tags and album art, bulk-update
songs, reorganize files on disk from a path template, and upload new music — all
from a browser, with no external services.

Built with Rails 8.1 on Ruby 4.0: Hotwire (Turbo + Stimulus) over import maps,
TailwindCSS v4, SQLite, and SolidQueue/SolidCache/SolidCable in production.

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

The library directory is gitignored — it holds your music, not source.

```bash
LIBRARY_ROOT=/media/music bin/dev
```

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
`bin/jobs` process.

## Project layout notes

- `CLAUDE.md` — the feature spec and working conventions.
- `TODO.md` — step-by-step implementation plan and progress.
