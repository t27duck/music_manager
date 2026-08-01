# MusicManager — Implementation TODO

Living plan and progress tracker. `CLAUDE.md` is the **spec** (what to build); this
file is the **plan** (what order, what is done, what is known-broken).

## How to resume

1. Read `CLAUDE.md`, then **Current status** below.
2. Pick the first unchecked step. Do not skip ahead — later steps assume earlier ones.
3. A step is done when:
   - `bin/rubocop` is clean
   - `bin/rails test` is green (tests land in the same step as the code)
   - `bin/rails test:system` is green if the step touched views
   - `bin/brakeman --quiet --no-pager --exit-on-warn` is clean
   - `git status --short` never lists `library/**`
   - this file is updated
4. Ask the user to commit to `main` before starting the next step.

## Current status

- **Working on:** Step 4 — Library sync
- **Last completed:** Step 3 — Song index UI
- **Blocked on:** nothing

---

## Steps

- [x] **Step 1 — Foundation & chrome**
  - [x] `ruby-mp3info` fork added (`t27duck/ruby-mp3info`, branch `ruby_34`)
  - [x] `/library/*` gitignored; `.DS_STORE` → `.DS_Store` (Linux is case-sensitive)
  - [x] `Configuration` defaults to `test/library` in the test env; adds `library_pathname`, `relative_path`
  - [x] Action Cable scaffolding: `ApplicationCable::{Connection,Channel}`, consumer JS, importmap pins
  - [x] Tailwind v4 `@theme` dark/blue tokens + `.btn`/`.input`/`.label`/`.card` component layer
  - [x] Layout chrome: sticky nav, `#sync_status` slot, `#sync_button` slot, `modal` turbo-frame, `#toasts` region
  - [x] Toast partials + `toast_controller.js`; removed generated `hello_controller.js`
  - [x] Tests: `test/configuration_test.rb`, `test/helpers/application_helper_test.rb`, `test/integration/health_check_test.rb`
  - Notes: mp3info verified read **and** write under Ruby 4.0; APIC art survives a tag rewrite.
    Layout brand links to `"/"` — swap to `root_path` in step 3 once the root route exists.

- [x] **Step 2 — Song model + ID3 layer**
  - [x] `CreateSongs` migration + `db/schema.rb` (see schema notes below)
  - [x] `Mp3File` — the only class that touches `Mp3Info`; read/write, `sanitize_string`,
        `image_content_type`, `album_art` reader
  - [x] `SongImporter.call(path)` — `find_or_initialize_by(file_path:)`, filename-without-extension
        as the title fallback; sets `skip_tag_write`
  - [x] `Song` `before_save` tag write-through with `throw :abort` on failure
  - [x] `test/support/library_test_helper.rb` — temp-dir `setup`/`teardown`, `create_test_song`,
        `songs_in_temp_dir`, `copy_fixture`, `tags_on_disk`; required from `test_helper.rb`
  - [x] No `test/fixtures/songs.yml` — fixtures cannot point at real files and would leak across
        the temp-dir tests
  - Notes: `create_test_song(subpath, **attributes)` takes keyword attributes, not a positional
    hash (`CLAUDE.md`'s sketch predates the real helper).

- [x] **Step 3 — Song index UI**
  - [x] `SongsController#index`, `root "songs#index"`, layout brand → `root_path`
  - [x] `songs/index.html.erb`, `_list`, `_song`, `_count`, `_empty` inside `turbo_frame_tag "songs"`
  - [x] Kaminari views generated and themed (`.page-link` component class); `paginates_per 50`
  - [x] `songs_helper.rb` — `formatted_duration`, `formatted_file_size`, `formatted_track`,
        `metadata_value`
  - [x] `nav_link_to` helper (deferred from step 1 until there were real nav links)
  - [x] First system tests, running against the selenium container
  - Notes: the count/pagination indicator lives **inside** the `songs` frame. Anything that must
    stay in step with the rendered rows has to be in that frame — a system test caught the count
    going stale when it sat outside. Songs with a NULL artist sort first (SQLite NULLS FIRST),
    which usefully surfaces untagged files.

- [ ] **Step 4 — Library sync**
  - [ ] `LibraryScanner`, `LibrarySync` + `LibrarySync::Status`, `LibrarySyncJob`
  - [ ] `SyncsController#show/#create`; `syncs/_status`, `_sync_button`, `_update.turbo_stream.erb`
  - [ ] `turbo_stream_from "library_sync"` in the layout; auto-hide after 5s
  - [ ] Prune songs whose files vanished; re-sync updates instead of skipping
  - [ ] Per-file error isolation (one bad MP3 must not abort the run)
  - [ ] `config/environments/test.rb`: `cache_store = :memory_store` (status must survive in-process)

- [ ] **Step 5 — Search & filtering**
  - [ ] `ransackable_attributes` / `ransackable_scopes`; global `title_or_artist_or_album_or_genre_cont`
  - [ ] Debounced search form + clear button; collapsible advanced filter panel
  - [ ] File path filter escaping `_` (SQL LIKE wildcard)
  - [ ] `sort_link` on every column; missing-metadata filter

- [ ] **Step 6 — Edit modal + deletion**
  - [ ] `SongsController#edit/#update/#destroy`; `shared/_modal` + `modal_controller.js`
  - [ ] Turbo Stream response closes the modal and re-renders the list preserving `q` and `page`
  - [ ] Delete removes the row **and** the file from disk

- [ ] **Step 7 — Inline editing**
  - [ ] `Songs::FieldsController` (`edit`/`update`, `param: :name`, allow-listed against
        `Song::EDITABLE_FIELDS`)
  - [ ] Per-cell turbo frames; `inline_edit_controller.js` on `dblclick`, Esc/blur cancels

- [ ] **Step 8 — Album art**
  - [ ] `Mp3File#album_art`, `#album_art=`, `#remove_album_art`
  - [ ] `Songs::AlbumArtsController` (`show`/`edit`/`update`/`destroy`) with etag from
        `album_art_checksum`; `Rails.cache.fetch` around extraction
  - [ ] Thumbnail column in the list; art in the edit modal; placeholder when absent

- [ ] **Step 9 — Bulk operations**
  - [ ] `selection_controller.js` — row checkboxes, select/deselect all, live count
  - [ ] `BulkUpdatesController#new/#create` + `Song::BulkUpdate` PORO (only non-blank fields applied)
  - [ ] Optional bulk album-art assignment; per-song error collection in the summary toast

- [ ] **Step 10 — File organization**
  - [ ] `PathTemplate` — all tokens incl. `<Track:N>` and `<Filename>`; filename sanitization
  - [ ] `FileOrganizer#preview` / `#apply!` — mkdir_p, move, update `file_path`, prune empty dirs,
        collision handling
  - [ ] `FileOrganizationsController#new` (preview re-rendered in a frame) / `#create`

- [ ] **Step 11 — Upload**
  - [ ] `UploadsController#show/#create`; files land in `_NEW/` preserving dragged folder structure
  - [ ] `UploadChannel` streaming `uploads:<uuid>`; `upload_controller.js` dropzone + per-file XHR,
        progress bar, counter, scrollable log, summary
  - [ ] Path-traversal prevention; non-MP3 rejected; duplicates via `find_or_initialize_by`
  - [ ] Upload link in the nav

- [ ] **Step 12 — Polish & hardening**
  - [ ] Cross-feature system tests, seeds, README pass
  - [ ] Responsive/mobile pass, focus rings, `aria-live` on progress
  - [ ] Full `bin/ci` + `bin/rails test:system`

---

## Schema notes (step 2)

`songs`: `file_path` (unique index — the natural key for `find_or_initialize_by` in both sync and
upload), `title`, `artist`, `album`, `genre`, `year`, `track_number`, `disc_number`, `duration`
(integer seconds), `bitrate`, `file_size`, `file_modified_at`, `album_art_checksum`,
`album_art_content_type`, `last_seen_at`, timestamps.

Index every sortable column — ransack exposes "sort by any column", and without them SQLite
full-sorts the table on every page. Composite `[artist, album, disc_number, track_number]` serves
the default ordering. `last_seen_at` is stamped each sync pass so pruning is a range delete rather
than a huge `NOT IN (...)`.

## Decisions (don't re-litigate)

| Decision | Why |
|---|---|
| ActiveStorage stays disabled | Album art lives in the ID3 APIC frame. AS would add three tables, a second source of truth, and a "which wins when the file changes underneath us" problem. Uploads are handled in memory. |
| `before_save` tag write, not `after_save`/`after_commit` | Rails only honours `throw :abort` in **before** callbacks — throwing it from `after_save` raises `UncaughtThrowError`. Writing first means a file we cannot write aborts the save and leaves the database untouched, which is the direction that matters: the database must never claim metadata the file does not have. (If the file write succeeds but the DB save then fails, the next sync re-reads the file and reconciles.) |
| Dev/test stay on the `:async` job adapter | `config/cable.yml` uses the in-process `async` cable adapter in development; a separate solid_queue worker would broadcast progress into its own memory and the browser would never see it. There is also no dev `queue` database. Production already uses solid_queue + solid_cable. |
| No `sync_runs` / `uploads` tables | Sync progress is transient: `Rails.cache` + a cable broadcast. Upload progress is entirely client-side. |
| Turbo Streams for sync, raw cable JSON for upload | Sync state is server-side and its markup is non-trivial; upload state (file list, per-file XHR progress, counter, summary) is already owned by the browser. |
| ID3 POROs live in `app/models` | Rails-omakase keeps POROs there; avoids a new autoload root. `Mp3File` is the only class that touches `Mp3Info`. |

## Testing tools

`simplecov` (report at `coverage/index.html`, gitignored) and `minitest-mock` are available in the
test group. Coverage after step 3 is ~96%.

## Backlog / deferred

- [ ] `sync_runs` table if sync history ever needs auditing — `LibrarySync::Status` is already the right shape.
- [ ] Move `FileOrganizer#apply!` into a job if selections grow large enough to time out a request.
- [ ] Persist the path template as a `Setting` record instead of `session`.
- [ ] Skip re-reading tags during sync when `file_modified_at` is unchanged (needs a "force rescan" escape hatch).

## Known issues / gotchas

- `library/` holds the user's real music (543 albums). Never write to it from tests; it is gitignored.
- Selenium cannot drive directory drag-and-drop; the upload system test must use the hidden file input.
- Fixture filenames contain spaces (`test/fixtures/files/song 1.mp3`) — always quote or `File.join`.
- The `ruby_34` branch of the mp3info fork is required; `master` is upstream 0.8.10 and breaks on
  Ruby 3.4+ frozen string literals.
- **SQLite `LIKE` needs an explicit `ESCAPE`.** `sanitize_sql_like` inserts backslashes, but SQLite
  ignores them unless the query says `LIKE ? ESCAPE ?`. Without it every `_` is a wildcard. This bit
  `songs_in_temp_dir` already; step 5's file-path filter must do the same.
- `test/fixtures/files/cover.jpg` **is actually a PNG.** Album art content types must always come
  from magic bytes (`Mp3File.image_content_type`), never from a filename or upload-supplied type.
- ruby-mp3info refuses to *write* invalid UTF-8 and normalizes it on read, so tag sanitization is
  tested directly against `Mp3File.sanitize_string` rather than through a crafted file — a
  file-based test would pass without ever exercising the scrub path.
- Clearing a tag needs an explicit delete from `tag`, `tag1` **and** the ID3v2 frame: ruby-mp3info
  only copies truthy generic values on close, so assigning `nil` silently leaves the old frame.
- Never write raw NUL bytes into Ruby source; use `"\u0000"`. A literal NUL makes `grep` treat the
  file as binary.
