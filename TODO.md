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

- **Working on:** nothing — all twelve steps are done and every feature in `CLAUDE.md` is built.
- **Last completed:** Step 12 — Polish & hardening
- **Blocked on:** nothing

Pick work from **Backlog / deferred** below, or add a step for anything new.

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

- [x] **Step 4 — Library sync**
  - [x] `LibraryScanner`, `LibrarySync` + `LibrarySync::Status`, `LibrarySyncJob`
  - [x] `SyncsController#show/#create`; `syncs/_status`, `_sync_button`, `_update.turbo_stream.erb`
  - [x] `turbo_stream_from "library_sync"` in the layout; auto-hide after 5s
  - [x] Prune songs whose files vanished; re-sync updates instead of skipping
  - [x] Per-file error isolation (one bad MP3 must not abort the run) + error count in the bar
  - [x] `config/environments/test.rb`: `cache_store = :memory_store`; `Rails.cache.clear` per test
  - [x] `Song.in_library` scope, reused by pruning and by the test helper
  - [x] `turbo_stream.refresh` on completion so the list is not left stale
  - [x] `sync_status_controller.js` polls `syncs#show` while running, as a fallback for
        broadcasts missed during a page reload or cable reconnect

- [x] **Step 5 — Search & filtering**
  - [x] `ransackable_attributes` / `ransortable_attributes` / `ransackable_scopes`; global
        `title_or_artist_or_album_or_genre_cont`
  - [x] Debounced search form + clear button; collapsible `<details>` advanced panel that opens
        itself when a filter is active
  - [x] `file_path_contains` scope escaping `_` and `%` (`LIKE ... ESCAPE`)
  - [x] `sort_link` on every column; `missing_metadata` scope
  - [x] Distinct "no results" state, separate from the empty-library state
  - [x] `SongsController::SEARCH_KEYS` explicit permit (brakeman flagged `permit!`)
  - Notes: the search form sits **outside** the `songs` frame, so it is not re-rendered on submit.
    Anything in it whose visibility depends on state (the clear ×, the Reset link) must be toggled
    in `filter_form_controller.js` — a server-rendered conditional there is stale the moment the
    user types. Default ordering stays `Song.ordered`; Ransack only takes over once `q[s]` is set,
    because the natural order is four columns deep.

- [x] **Step 6 — Edit modal + deletion**
  - [x] `SongsController#edit/#update/#destroy`; `shared/_modal` (a `<dialog>`) + `modal_controller.js`
  - [x] Turbo Stream response closes the modal and re-renders the list preserving `q` and `page`
        via `list_state_fields` / `list_state_params`
  - [x] `Song#destroy_with_file!` removes the row **and** the file, rolling back if the file
        cannot be deleted
  - [x] Toasts finally in use; failed tag writes re-render the modal with errors (422)
  - Notes: `shared/_modal` is reusable — render with `render layout: "shared/modal"`. Steps 9 and
    10 should use it rather than rolling their own.

- [x] **Step 7 — Inline editing**
  - [x] `Songs::FieldsController` (`show`/`edit`/`update`, `param: :name`, allow-listed against
        `Song::EDITABLE_FIELDS`; anything else 404s)
  - [x] Per-cell turbo frames (`dom_id(song, name)`); `inline_edit_controller.js` on `dblclick`
  - [x] Enter and blur save (spreadsheet behaviour), Escape discards
  - [x] Failed tag writes re-render the input with the error inline
  - Notes: `show` exists so Escape has something to restore the cell from — that is why the plan's
    edit/update pair became a trio. Inline edits re-render **only the cell**, not the list, so a row
    edited out of the current filter stays visible until the next load; that is deliberate, since
    replacing the table mid-edit would defeat the point of editing in place. Use the modal when the
    change should re-sort or re-filter.

- [x] **Step 8 — Album art**
  - [x] `Mp3File#album_art`, `#album_art=`, `#remove_album_art`
  - [x] `Song#update_album_art!` / `#remove_album_art!` with type and size validation
        (`Song::InvalidAlbumArt`) — reuse these in step 9's bulk art assignment
  - [x] `Songs::AlbumArtsController` (`show`/`edit`/`update`/`destroy`)
  - [x] Thumbnail column in the list; art panel in the edit modal; placeholder when absent
  - Notes: **no `Rails.cache.fetch`** around extraction, contrary to the original plan. The image
    URL carries `?v=<checksum>`, so a given URL's bytes can never change and the response is
    `expires_in 1.year, public: true` with an etag — the browser fetches each image exactly once.
    That beats storing multi-megabyte blobs in solid_cache, which has its own entry-size limits.

- [x] **Step 9 — Bulk operations**
  - [x] `selection_controller.js` — row checkboxes, select/deselect all (with indeterminate state),
        live count, clear
  - [x] `BulkUpdatesController#new/#create` + `Song::BulkUpdate` PORO (only non-blank fields applied)
  - [x] Bulk album-art assignment and removal; per-song failures reported in the summary toast
  - [x] Extracted `SongListing` concern (`load_songs`, `search_params`, `SEARCH_KEYS`) now that a
        second controller re-renders the list — step 10 should include it too
  - Notes: the selection is **not** a form. The table holds per-cell inline-edit forms, and a form
    wrapping the table would be nested markup the browser discards; `selection_controller.js`
    collects the ids and appends them to the modal frame's URL instead. Title is deliberately not
    a bulk field. Selection resets whenever the list re-renders, which is per-page by design.

- [x] **Step 10 — File organization**
  - [x] `PathTemplate` — all tokens incl. `<Track:N>` and `<Filename>`; per-segment sanitization;
        rejects blank, token-less, absolute and `..` templates
  - [x] `FileOrganizer#preview` / `#apply!` — mkdir_p, move, update `file_path`, prune emptied
        directories, suffix collisions (against both disk and the rest of the batch)
  - [x] `FileOrganizationsController#new` (**is** the preview) / `#create`; template remembered in
        the session; "Organize files" in the selection toolbar
  - [x] Renamed `filter_form_controller.js` → `auto_submit_controller.js` (it was never
        filter-specific); added `path_template_controller.js` for the live preview
  - Notes: the preview is a **GET of #new into its own frame**, never a submit of the surrounding
    form — that form POSTs to #create and moves files. Moves happen inside a transaction that wraps
    `update!` + `mv`, so a failed move leaves the database untouched. The preview puts source and
    destination on separate lines, destination wrapping in full, in a `max-w-3xl` modal: a
    single truncated line hid the destination entirely for real filenames.

- [x] **Step 11 — Upload**
  - [x] `UploadsController#show/#create` (one POST per file); `Upload` PORO writes into `_NEW/`
        preserving the dragged folder structure
  - [x] `UploadChannel` streaming `uploads:<id>`; `upload_controller.js` dropzone with recursive
        directory walk, click-to-browse fallback (files **and** folder), per-file XHR progress,
        counter, scrollable log, summary
  - [x] Path-traversal prevention (`SafeFilename`, plus a re-check of the resolved path);
        non-MP3 rejected by extension *and* by failing to parse; duplicates via `SongImporter`
  - [x] Upload link in the nav
  - [x] `SafeFilename` extracted so the traversal-critical character rules cannot drift from
        `PathTemplate`'s
  - Notes: the browser owns the counters (it has the file list and the XHR progress); the log lines
    come from the server over cable, so what is reported is what actually happened to each file.
    Uploads are sequential on purpose.

- [x] **Step 12 — Polish & hardening**
  - [x] Checked against real library data (a copied slice, plus the 4,892-song dev database)
  - [x] Table switched to `table-fixed` with a `min-w`, cells truncate again — a 205-character
        artist tag was making rows nine lines tall and pushing columns off screen
  - [x] Responsive pass at 390 / 768 / 1400; nav wraps; table scrolls inside its own wrapper and
        the page itself never scrolls sideways
  - [x] Accessibility pass + `test/system/accessibility_test.rb` to hold it: table `aria-label`,
        `aria-live` on the song count and sync status, skip link, and an audit that every visible
        control has an accessible name
  - [x] `db/seeds.rb` documents that there is nothing to seed (songs come from disk)
  - [x] README rewritten with a feature summary and a warning that the app rewrites and deletes
        real files
  - [x] `CLAUDE.md` test-helper docs corrected to match `LibraryTestHelper`
  - [x] Full `bin/ci` green (~14s), 98% line coverage
  - Notes: query timings on the real 4,892-song library are all single-digit milliseconds
    (first page 11 ms, search 4 ms, sort 2 ms), so the per-column indexes are pulling their weight.

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
| `turbo_stream.refresh` after a sync, not broadcast rows | Each page reloads its *own* URL, so a viewer's filters and page number survive. Broadcasting rendered rows would clobber them. |
| System tests use the `:async` job adapter; the rest of the suite keeps `:test` | System tests must let a job finish *after* the request that queued it — that is the only way "Sync complete" appearing in the browser proves the broadcast arrived rather than the POST response having said so. Set in `ApplicationSystemTestCase`, so unit tests can still `assert_enqueued_with`. |
| `Capybara.default_max_wait_time = 10` | Every meaningful interaction is job + cable + re-render. The 2s default has too little headroom under load; raising it once beats scattering `wait:` through the tests. |

## Testing tools

`simplecov` (report at `coverage/index.html`, gitignored) and `minitest-mock` are available in the
test group. Coverage after step 4 is ~98%.

## Backlog / deferred

- [ ] Mobile shows the song table in a sideways-scrolling wrapper. Fine for a desktop-focused app,
      but a card layout under `sm:` would be better if mobile use turns out to matter.
- [ ] Selection is per-page and resets whenever the list re-renders. Selecting across pages would
      need the ids held outside the frame.

- [ ] `sync_runs` table if sync history ever needs auditing — `LibrarySync::Status` is already the right shape.
- [ ] Move `FileOrganizer#apply!` into a job if selections grow large enough to time out a request.
- [x] ~~Persist the path template as a `Setting` record instead of `session`.~~ — done.
      `Setting` is a generic key/value table with `Setting[:key]` / `Setting[:key] =` accessors,
      so the next preference needs no migration.
- [ ] Skip re-reading tags during sync when `file_modified_at` is unchanged (needs a "force rescan" escape hatch).
- [x] ~~Ransack's built-in `cont` does not escape `_`/`%`~~ — done. Every text filter is now a
      `Song.contains`-backed scope (`text_contains`, `title_contains`, …) listed once in
      `Song::FILTER_SCOPES`. A custom Ransack predicate turned out to be impossible: Ransack
      calls the Arel predicate with exactly one argument, so the escape character can never
      reach `Arel::Nodes::Matches`. Fixing it also uncovered two live bugs — see below.

## Known issues / gotchas

- `library/` holds the user's real music (543 albums). Never write to it from tests; it is gitignored.
- Selenium cannot drive directory drag-and-drop; the upload system test must use the hidden file input.
- Fixture filenames contain spaces (`test/fixtures/files/song 1.mp3`) — always quote or `File.join`.
- The `ruby_34` branch of the mp3info fork is required; `master` is upstream 0.8.10 and breaks on
  Ruby 3.4+ frozen string literals.
- **SQLite `LIKE` needs an explicit `ESCAPE`.** `sanitize_sql_like` inserts backslashes, but SQLite
  ignores them unless the query says `LIKE ? ESCAPE ?`. Without it every `_` is a wildcard. Encoded
  once in `Song.contains`, which every text filter goes through, and once in `Song.in_library`.
- **Ransack cannot emit `ESCAPE`.** `nodes/condition.rb` calls `attribute.public_send(arel_pred, values)`
  with exactly one argument, so `Arel::Predications#matches(other, escape = nil, …)` always gets
  `nil` and the visitor never appends the clause. `arel_predicate` may be a Proc, but its return
  value is used as the *method name*, not as a node factory. `Ransack::Constants.escape_wildcards`
  is also a no-op on SQLite. Hence scopes, not a custom predicate.
- **Ransack coerces scope arguments into booleans unless the scope opts out.** `TRUE_VALUES` is
  `[true, 1, '1', 't', 'T', 'true', 'TRUE']`, and Rails scopes report an arity of `-1`, so
  searching for `t` called the scope with *no* argument and raised `ArgumentError` — a 500 from
  typing one character. `0` was read as false and the filter silently vanished. Every scope in
  `Song::FILTER_SCOPES` is listed in `ransackable_scopes_skip_sanitize_args` for this reason;
  any new user-typed scope must be added there too.
- **`Dir.glob` ignores `File::FNM_CASEFOLD`.** `Dir.glob("**/*.mp3", flags: File::FNM_CASEFOLD)`
  silently misses `.MP3`, in both the keyword and positional forms. `LibraryScanner` globs `**/*`
  and filters on `File.extname(...).downcase` instead.
- `ActionCable::TestHelper` (for `assert_broadcasts`) and `ActiveJob::TestHelper` (for
  `assert_enqueued_with`) must each be included explicitly; neither is in `ActiveSupport::TestCase`.
- Rendering a partial from a controller needs `render partial: "syncs/update"`. Plain
  `render "syncs/update"` looks for a *template* and raises `MissingTemplate`.
- `hidden="<%= false %>"` still hides the element — any value of `hidden` counts in HTML. Use
  `<%= "hidden" if condition %>` in raw tags; Rails' own tag helpers handle `hidden: false` correctly.
- Enumerating rows right after a Turbo frame swap raises `StaleElementReferenceError`. Wait for the
  new state with a retrying matcher (`assert_selector "tbody tr:first-child", text: ...`) first.
- Ransack `sort_link` URL-encodes its params, so hrefs read `q%5Bs%5D=title+asc`, and they resolve
  to `/` rather than `/songs` because root maps to the same action.
- **`button_to` renders a `<form>`.** Putting one inside another form is invalid HTML and the
  browser silently drops it, so the button does nothing. Keep `button_to` outside `form_with`.
- Hover-only controls (`opacity-0 group-hover:opacity-100`) are invisible to Capybara *and* to
  anyone on a touch device. Keep row actions visible and merely subdued.
- `ActionController::RoutingError` raised in a controller is rescued into a 404 by the integration
  stack (`show_exceptions = :rescuable`), so assert `:not_found` rather than `assert_raises`.
- Escape-to-cancel also fires `blur`. Any "save on blur" handler needs a flag so the discarded
  value is not written on the way out — see `inline_edit_controller.js`.
- `test/fixtures/files/cover.jpg` is **byte-identical to the art already embedded in the MP3
  fixtures**. A test that needs *different* art must supply its own (both album-art test files
  carry a tiny inline `GIF` constant for this).
- Rails hashes etag values, so `response.headers["ETag"]` is never the raw string passed to
  `stale?`. Assert the contract (it changes when the content changes), not the literal.
- Capybara does not match `aria-label` unless `enable_aria_label` is set. Give inputs real
  `<label>`s — better for users anyway.
- Don't select table cells by position (`td:first-child`); a new column silently breaks every such
  test. The per-cell turbo frames (`turbo-frame[id^='title_song_']`) are stable hooks.
- **`form_with` only infers `multipart` from its own builder's `file_field`.** A standalone
  `file_field_tag` does not flag the form, and the upload is silently dropped — pass
  `multipart: true` explicitly.
- Binding `change->…#submit` at *form* level makes every text field resubmit on blur, including
  when the user clicks something else on the page. Bind `input` to the form and put `change`
  handlers on the discrete controls (selects) themselves.
- `Capybara.enable_aria_label = true` is set, so `aria-label` resolves controls — which is how a
  screen reader finds them too. Table checkboxes are labelled that way rather than with visible
  labels per row.
- **Never wire debounced auto-submit to a form whose submission is destructive.** The organize
  template first lived inside the form that POSTs to `#create`, so typing a valid template moved
  the user's files mid-keystroke. Live previews must be a separate GET into their own frame.
- A failed `update!` still leaves the assigned value on the in-memory record even after the
  transaction rolls back. Reload before handing the object back to a caller.
- One system-test run showed a single unreproducible error; six consecutive runs since have been
  clean. Watch for it rather than assuming it is gone.
- **`crypto.randomUUID()` needs a secure context.** Served over plain HTTP on any hostname other
  than localhost — the normal case for a local music server — it is undefined, and the exception
  killed the whole upload controller silently. `crypto.getRandomValues` has no such restriction.
  Check any other browser API you reach for against the same trap.
- Action Cable's `test` adapter subclasses the async one, so broadcasts really are delivered to a
  browser in system tests as well as recorded for `assert_broadcasts`.
- **Review screens with realistic data, not tidy fixtures.** `a.mp3` / "Test Song" made the
  organize preview look fine; a real path
  ("Bad Hair Day/01 - Amish Paradise (Parody of 'Gangsta's Paradise' by Coolio).mp3") truncated the
  destination away entirely. Tests could not catch it — CSS truncation still reports full text to
  Selenium — so it is worth eyeballing new screens with long names and odd characters.
- `test/fixtures/files/cover.jpg` **is actually a PNG.** Album art content types must always come
  from magic bytes (`Mp3File.image_content_type`), never from a filename or upload-supplied type.
- ruby-mp3info refuses to *write* invalid UTF-8 and normalizes it on read, so tag sanitization is
  tested directly against `Mp3File.sanitize_string` rather than through a crafted file — a
  file-based test would pass without ever exercising the scrub path.
- Clearing a tag needs an explicit delete from `tag`, `tag1` **and** the ID3v2 frame: ruby-mp3info
  only copies truthy generic values on close, so assigning `nil` silently leaves the old frame.
- Never write raw NUL bytes into Ruby source; use `"\u0000"`. A literal NUL makes `grep` treat the
  file as binary.
