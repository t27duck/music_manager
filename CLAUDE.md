# Project Overview

MusicManager is a local MP3 library management web application built with Rails 8.1 and Ruby 4.0. It scans directories for MP3 files, caches metadata in SQLite, and allows editing ID3 tags and album art.

## Development Commands

```bash
bin/setup              # Install deps, prepare DB, start dev server
bin/setup --reset      # Full reset with DB drop/recreate
bin/dev                # Start development server (port 3000)
bin/rails console      # Rails console
```

## Testing

- Run all tests: `bin/rails test`
- Run system tests: `bin/rails test:system`
- Run specific test file: `bin/rails test test/path/to/test_file.rb`
- Run specific test method: `bin/rails test test/path/to/test_file.rb:LINE_NUMBER`
- Headless Chrome via selenium is available running in a separate container on port 45678 under the docker hostname selenium.

### Test Patterns for File Operations

Tests that manipulate files (sync, organize, bulk operations) `include LibraryTestHelper`
(`test/support/library_test_helper.rb`). It gives each test its own temp directory as the library
root, so tests never see each other's files and never touch the real library:

```ruby
class SomethingTest < ActiveSupport::TestCase
  include LibraryTestHelper

  test "..." do
    song = create_test_song("Artist/Album/track.mp3", title: "Midnight Drive", year: 2021)
    # @temp_dir is the library root for the duration of the test
  end
end
```

What the helper provides:

| Method | Purpose |
|---|---|
| `create_test_song(subpath, **attributes)` | Copies a fixture MP3 into the temp library and creates the Song. Attributes are **keywords**, not a positional hash. Passes `skip_tag_write`, so the file keeps the fixture's own tags. |
| `copy_fixture(subpath, fixture_name:)` | Just the file, no record. |
| `fixture_file(name)` | Absolute path to a file in `test/fixtures/files/`. |
| `songs_in_temp_dir` | `Song.in_library(@temp_dir)` — scope queries when testing something that operates on the whole library. |
| `tags_on_disk(path)` | Reads tags straight back off the file, bypassing the database. |

Key points:
- Each test gets a unique temp directory (includes PID + thread ID for parallel safety); setup and
  teardown stub and restore `Configuration.library_root` and clear the cache.
- The test environment defaults the library root to `test/library/`, so a test that forgets to
  include the helper scans an empty directory rather than the real library.
- Fixtures live at `test/fixtures/files/`: `song 1.mp3` … `song 8.mp3` and `cover.jpg`. Note that
  `cover.jpg` is **actually a PNG**, and is byte-identical to the art already embedded in the MP3
  fixtures — a test needing *different* artwork must supply its own.
- There is deliberately no `songs.yml` fixture: a Song is only meaningful next to a real file.

## Linting & CI

```bash
bin/rubocop            # Ruby style (Rails Omakase)
bin/ci                 # Full CI pipeline: setup, lint, security, tests
```

CI pipeline runs: rubocop → bundler-audit → importmap audit → brakeman → rails test → db:seed:replant

## Tech Stack

- **Frontend**: Hotwire (Turbo + Stimulus), Importmap for JS, TailwindCSS v4 (CSS-first, theme in `app/assets/tailwind/application.css` — there is no `tailwind.config.js`)
- **Background Jobs**: SolidQueue with ActiveJob (production only — see Key Configuration). Every
  long-running operation reports through the shared progress component
  (`app/models/concerns/progress_reporting.rb` + `progress_status.rb`): one cache key, one Turbo
  Stream, one bar under the nav. Operations are **mutually exclusive** — a sync prunes song rows
  while an organize moves the files underneath them — so `ProgressReporting.busy?` gates every
  enqueue. A status put in the cache must hold **primitives only**; it is Marshalled, so an Active
  Record object in it would bloat the entry and come back stale
- **Database**: SQLite (storage/ directory)
- **MP3 Tags**: ruby-mp3info, pinned to the `ruby_34` branch of the fork at github.com/t27duck/ruby-mp3info. That branch is the one that survives Ruby 3.4+ frozen string literals; `master` is upstream 0.8.10 and does not.
- **Filtering/Pagination**: Ransack, Kaminari

## Key Configuration

- `Configuration.library_root` class method defined in `config/initializers/configuration.rb` - defaults to `{pwd}/library/`, overridable via `LIBRARY_ROOT` ENV variable. In the test environment it defaults to `test/library/` so a test that forgets to stub the root scans an empty directory instead of the real music library.
- Database files stored in `storage/` directory
- Background jobs run on the **`:async` adapter in development and test, on purpose**. `config/cable.yml` uses the in-process `async` cable adapter in development, so a separate SolidQueue worker process would broadcast progress into its own memory and the browser would never receive it. Production uses SolidQueue + SolidCable. Do not add a `jobs:` line to `Procfile.dev`.
- `TODO.md` tracks implementation progress step by step; read it before starting work.
- Timestamps are rendered with `ApplicationHelper#formatted_time`, which formats through
  `en.time.formats.run` in `config/locales/en.yml` — never inline `strftime`, and absolute rather
  than relative. `config.time_zone` is Eastern; change it in `config/application.rb`.
- `Setting` (`app/models/setting.rb`) is a generic key/value table for app preferences that must
  outlive a browser session — `Setting[:name]` reads, `Setting[:name] = value` writes. There is no
  `User` model or authentication, so these are settings for the app, not for a person. Adding a
  preference needs no migration.

## Instructions

- Write code in the "Rails Way" and take advantage of the functionality of the Rails framework and best practice design patterns.
- Always read entire files. Otherwise, you don't know what you don't know, and will end up making mistakes, duplicating code that already exists, or misunderstanding the architecture.
- Organise code into separate files wherever appropriate, and follow general coding best practices about variable naming, modularity, function complexity, file sizes, commenting, etc.
- Code is read more often than it is written, optimize code for readability.
- Do not carry out large refactors unless explicitly instructed to do so.
- When doing UI & UX work, make sure designs are easy to use and follow UI / UX best practices. Pay attention to interaction patterns, micro-interactions, and are proactive about creating smooth, engaging user interfaces that delight users.
- Prefer RESTful routes and nested controllers over custom actions
- When importing files without title, default to filename without extension
- Ask to commit often - specifically after each feature is implemented.

## Documentation Maintenance

Keep `CLAUDE.md` updated as the project evolves. Update these files when:

- Adding or removing significant dependencies (gems, JS libraries)
- Changing the technology stack or infrastructure
- Adding new domain concepts or models
- Restructuring directories or namespaces
- Adding new build, test, or deployment commands
- Changing authentication, authorization, or API patterns

`README.md` is meant for people to read to learn how to boostrap and deploy the app along with a brief general overview of the project. Only update it with applicable information.

# Features

## MP3 Library Management

### Scanning & Import

- Scan library directory for MP3 files (background job with real-time progress)
- Automatic metadata extraction from ID3 tags (title, artist, album artist, album, genre, year,
  track number, disc number)
- `album_artist` comes from the ID3 **TPE2** frame and falls back to `artist` when absent (about a
  tenth of real files). It is what makes a compilation one album instead of one album per track
  artist, and it is bulk-editable so a mis-tagged compilation can be collapsed in one pass
- `LibrarySync::TAG_EPOCH` — bump it whenever a release starts reading a tag it did not read
  before. The next sync force-re-reads every file once, then reverts to skipping. Without it the
  mtime/size skip would leave the new tag unread on every existing song
- Default to filename if no title tag found
- Automatic sync: removes database entries when files are deleted from disk
- Real-time sync progress via WebSocket (ActionCable)
- Sync progress bar below navigation with stable counter (current/total) and current filename
- Color-coded status text: blue (running), green (completed), red (failed)
- Completed status auto-hides after 5 seconds
- Sync button disabled while sync is running
- Sync history at `/sync_runs`: one `SyncRun` row per run, written once at the start and once at
  the end, capped at `SyncRun::KEEP` runs. It is an audit trail, not a progress store — live
  progress is still the cache plus a broadcast
- Re-syncing updates existing song metadata instead of skipping
- Files whose modification time (to the second) and size are both unchanged are left unread, since
  parsing ID3 and hashing the cover is nearly all of a sync's cost. A "Full rescan" button beside
  "Sync library" re-reads everything regardless
- Completed status reports how many files were skipped ("Sync complete — N unchanged")
- Per-file error handling: individual import failures are logged without aborting the sync
- MP3 tag string sanitization (invalid UTF-8, null characters)

## User Interface

- Moderately dark professional theme
- Toast notifications for user actions
- Whenever possible, instead of full pages and full redirects with forms, render interfaces in large browser-based modals. On successful submission, dismiss the modal so the user remains on the original song list page. Refresh any active filters and current pagination to reflect changes to the user. Utilize Turbo streams, actions, and frames as needed.
- Responsive layout and mobile-friendly though the focus should be desktop. Below `sm:` the song
  table reflows into one card per song — art, title and artist prominent, album/genre/year/length
  subdued — by changing only `display` on the existing elements. Never emit a second markup tree:
  the row, its checkbox and every editable cell carry `dom_id`s that inline editing, the selection
  and the album-art stream all address. A `sm:hidden` sort select in the filter panel stands in for
  the hidden column headers
- Prefer blues for accent theme colors

### Metadata Editing

- Edit song metadata: title, artist, album, genre, year, disc number, track number
- Changes to database records should always be reflected on the file metadata
- Album art upload and management
- Inline editing on song list (double-click to edit cells)
- ID3v1 and ID3v2 tag writing with APIC frame support for album art

### Bulk Operations

- Multi-select songs with checkboxes
- Bulk update metadata fields and album art assignment across multiple songs. Applied in a
  background job with live progress: every changed song has its ID3 tags rewritten, which is a
  whole-file rewrite (~10ms each on a real library), so a large selection cannot be done in the
  request. Album art is spooled to a tempfile at enqueue time, since the bytes cannot ride in job
  arguments
- Select all / deselect all on the current page, and a "Select all N matching" escalation that
  sends the active filter instead of a list of ids so the server can resolve it — the only way to
  act on more songs than a URL can carry
- Selection spans pages, filters and sorts. It is held in memory outside the `songs` turbo frame,
  so a full page reload clears it — deliberately, since the only thing that reloads on its own is
  a finished sync or organize, which is exactly when the selection would have gone stale
- One action may touch at most `SongListing::SELECTION_LIMIT` songs; over that it is refused, never
  silently trimmed
- Selection count indicator

### File Organization

- Reorganize files using customizable path templates
- Template tokens: `<Artist>`, `<Album>`, `<Title>`, `<Genre>`, `<Year>`, `<Disc>`, `<Track>`, `<Track:N>` (zero-padded), `<Filename>`
- Preview changes before applying
- Moves run in a background job with live progress, so a large selection cannot time out the
  request. The modal closes at once and the list refreshes when the job finishes
- Automatic directory creation
- Filename sanitization (removes illegal characters)
- The last applied template is remembered in a `Setting` record, so it survives a cleared
  cookie and is shared across browsers

### Upload

- Drag-and-drop upload page for MP3 files and folders
- Files saved to `_NEW/` directory inside the library root
- Folder structure from dragged directories is preserved
- Metadata extracted automatically and Song records created
- Click-to-browse fallback via hidden file input
- Client-side progress tracking: progress bar, counter (completed/total), scrollable message log
- Summary shown on completion with success/failure counts
- Path traversal prevention on server side
- Duplicate file handling via `find_or_initialize_by` on file path
- Real-time server broadcast via `UploadChannel` (ActionCable)
- Non-MP3 files rejected with error response
- Upload link in navigation bar

### Song Removal

- Delete song from library and file permanently from disk

### Playback

- `GET /songs/:song_id/audio` serves the MP3 with real byte-range support, so the browser can seek.
  It delegates to `Rack::Files#serving` — `send_file`/`send_data` ignore `Range` entirely. Keyed on
  the song id, not the path, so a link survives a file organize

### Browsing

- `/albums` — a paginated cover grid of every `(album_artist, album)` group, with its own search
  across album and album artist. An album page lists its tracks, naming the track artist only where
  it differs from the album artist (which is what makes a compilation legible)
- `/artists` — the same grid over `album_artist`, leading to an artist page of their albums.
  Grouping on `album_artist` rather than `artist` is what keeps a compilation one entry instead of
  one per guest performer. The hierarchy is Artists → Albums → Songs
- `Album` and `Artist` are **POROs, not tables** (`app/models/album.rb`): the file on disk is the source of
  truth, so a table would need syncing and pruning on every tag edit for no query benefit
- Album URLs carry the grouping key itself, encoded by `LibraryKey` (JSON inside urlsafe Base64 —
  it round-trips `nil` and cannot be confused by a delimiter inside a name). A malformed key raises
  `RecordNotFound`, so a hand-edited URL is a 404 rather than a 500

## Search & Filtering

### Global Search

- Single search field searches across title, artist, album, and genre
- Real-time search as-you-type with debounce
- Clear button to reset search

### Advanced Filters

- Individual filter fields for title, artist, album, genre, year, file path
- Every text filter escapes underscores (`_`) and percent signs (`%`) in the query. They are
  `Song` scopes built by `Song.contains` and listed in `Song::FILTER_SCOPES` — Ransack's built-in
  `cont` cannot emit SQLite's required `ESCAPE` clause. Query params read `q[title_contains]`,
  `q[text_contains]` (the global box), etc. Any new user-typed scope must also be added to
  `Song.ransackable_scopes_skip_sanitize_args`, or Ransack coerces values like `t` and `0` into
  booleans.
- Combine multiple filters simultaneously
- Sort by any column
- Filter by missing metadata (songs without artist, album, genre, or year)

### Pagination

- Paginated results with count display

