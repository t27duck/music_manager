# MusicManager 0.1.0

The first release of MusicManager: a desktop app for filtering, tagging and reorganizing a local MP3 library. Your MP3 files are the source of truth. A SQLite index mirrors their tags so that search stays instant across thousands of files. It catches up with any changes at startup and watches the library while the app is open.

## Highlights

- **Browse and filter**: search across tags and paths, and stack field filters (artist, album, year, bitrate, duration, has album art, folder, …) with operators such as *contains*, *starts with*, *is empty* and `>`. *Find problems* finds tracks with tag errors, no album art, or a missing title, artist, album, track number or year.
- **Edit tags** on one file or hundreds at once. In a bulk edit, a field left blank is left alone on every file, and the × button clears that field on all of them. If you have unsaved edits, the app asks before you lose them.
- **Album art**: set or remove the embedded front cover with *Set image…*, by dropping an image onto the editor, or by pasting one with Ctrl+V.
- **Listen** to a track to check it matches its tags (double-click or Space). Audio is decoded inside the app, so it doesn't need GStreamer plugins.
- **Reorganize** files with a path template such as `<AlbumArtist>/<Album> (<Year>)/<Disc>-<Track:2> <Title>`. You can preview every move first. Conflicts are skipped and nothing is overwritten. Folders left empty are removed, and loose cover images follow their album when it moves as a whole.
- **Tags are written as ID3v2.4.** Old ID3v1 tags are stripped, and a v2.3 year (`TYER`) is carried over to the v2.4 date frame. Frames the app doesn't edit, such as lyrics and ReplayGain, are kept.

## Downloads

| Platform | File | |
| --- | --- | --- |
| Ubuntu 24.04+ / Debian | `MusicManager_0.1.0_amd64.deb` | `sudo apt install ./MusicManager_0.1.0_amd64.deb` |
| Arch Linux | `music-manager-0.1.0-1-x86_64.pkg.tar.zst` | `sudo pacman -U music-manager-0.1.0-1-x86_64.pkg.tar.zst` |
| macOS (Apple Silicon) | `MusicManager_0.1.0_macos-arm64.tar.gz` | Unofficial; see below |
| Windows x64 | `MusicManager_0.1.0_x64-setup.exe` | Unofficial installer |
| Windows x64 (portable) | `MusicManager_0.1.0_x64-portable.zip` | Unofficial; keeps settings in its own `data` folder |

`SHA256SUMS` has checksums for every file: `sha256sum -c SHA256SUMS --ignore-missing`.

### Notes for the unofficial builds

- **macOS**: an unsigned binary. Extract it, then run `xattr -d com.apple.quarantine music-manager` before the first launch.
- **Windows**: unsigned, so SmartScreen warns on first run; choose *More info → Run anyway*. The installer fetches WebView2 if it's missing. The portable build needs WebView2 already installed, as it is on Windows 11 and current Windows 10.
