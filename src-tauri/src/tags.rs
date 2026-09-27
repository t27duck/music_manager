//! Reading and writing ID3 tags and embedded album art.
//!
//! Tags are always written as ID3v2.4. Any ID3v1 tag is removed on write since it
//! cannot represent the full v2 tag and would otherwise go stale.

use std::fs::File;
use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};
use id3::frame::{Comment, Picture, PictureType, Timestamp};
use id3::{ErrorKind, Tag, TagLike, Version};
use lofty::config::ParseOptions;
use lofty::file::AudioFile;
use lofty::mpeg::MpegFile;
use serde::{Deserialize, Serialize};

/// Frames that carry (pieces of) the ID3v2.3 date, superseded by TDRC in v2.4.
const LEGACY_DATE_FRAMES: [&str; 4] = ["TYER", "TDAT", "TIME", "TRDA"];

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct TrackTags {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album_artist: Option<String>,
    pub album: Option<String>,
    pub genre: Option<String>,
    pub composer: Option<String>,
    pub comment: Option<String>,
    pub year: Option<i32>,
    pub track: Option<u32>,
    pub track_total: Option<u32>,
    pub disc: Option<u32>,
    pub disc_total: Option<u32>,
    pub has_art: bool,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct AudioInfo {
    pub duration_ms: u64,
    pub bitrate: u32,
}

/// A single field change. A field that is absent from [`TagEdits`] is left untouched.
#[derive(Debug, Clone, Deserialize, PartialEq)]
#[serde(tag = "op", content = "value", rename_all = "lowercase")]
pub enum FieldEdit<T> {
    Set(T),
    Clear,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct TagEdits {
    pub title: Option<FieldEdit<String>>,
    pub artist: Option<FieldEdit<String>>,
    pub album_artist: Option<FieldEdit<String>>,
    pub album: Option<FieldEdit<String>>,
    pub genre: Option<FieldEdit<String>>,
    pub composer: Option<FieldEdit<String>>,
    pub comment: Option<FieldEdit<String>>,
    pub year: Option<FieldEdit<i32>>,
    pub track: Option<FieldEdit<u32>>,
    pub track_total: Option<FieldEdit<u32>>,
    pub disc: Option<FieldEdit<u32>>,
    pub disc_total: Option<FieldEdit<u32>>,
    /// For art, `Set` carries the path of an image file on disk.
    pub art: Option<FieldEdit<String>>,
}

impl TagEdits {
    pub fn is_empty(&self) -> bool {
        self.title.is_none()
            && self.artist.is_none()
            && self.album_artist.is_none()
            && self.album.is_none()
            && self.genre.is_none()
            && self.composer.is_none()
            && self.comment.is_none()
            && self.year.is_none()
            && self.track.is_none()
            && self.track_total.is_none()
            && self.disc.is_none()
            && self.disc_total.is_none()
            && self.art.is_none()
    }
}

/// Album art loaded into memory once so a bulk edit doesn't re-read the image per file.
#[derive(Debug, Clone)]
pub struct Artwork {
    pub mime: String,
    pub data: Vec<u8>,
}

impl Artwork {
    pub fn load(path: &Path) -> Result<Self> {
        let data = std::fs::read(path).with_context(|| format!("reading {}", path.display()))?;
        let Some(mime) = sniff_image_mime(&data) else {
            bail!("{} is not a JPEG, PNG, GIF or WebP image", path.display());
        };
        Ok(Self { mime: mime.to_string(), data })
    }
}

/// Saves image bytes (e.g. pasted from the clipboard) as a file in `dir` so they can be used
/// like a chosen image file. Earlier staged images in `dir` are removed; only the latest one is
/// ever pending.
pub fn stage_image(dir: &Path, data: &[u8]) -> Result<PathBuf> {
    let ext = match sniff_image_mime(data) {
        Some("image/jpeg") => "jpg",
        Some("image/png") => "png",
        Some("image/gif") => "gif",
        Some("image/webp") => "webp",
        _ => bail!("the pasted image isn't a JPEG, PNG, GIF or WebP"),
    };
    std::fs::create_dir_all(dir).with_context(|| format!("creating {}", dir.display()))?;
    for entry in std::fs::read_dir(dir)?.flatten() {
        let _ = std::fs::remove_file(entry.path());
    }
    let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis();
    let path = dir.join(format!("pasted-{stamp}.{ext}"));
    std::fs::write(&path, data).with_context(|| format!("writing {}", path.display()))?;
    Ok(path)
}

pub fn sniff_image_mime(data: &[u8]) -> Option<&'static str> {
    if data.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some("image/jpeg")
    } else if data.starts_with(b"\x89PNG\r\n\x1a\n") {
        Some("image/png")
    } else if data.starts_with(b"GIF8") {
        Some("image/gif")
    } else if data.len() > 12 && &data[0..4] == b"RIFF" && &data[8..12] == b"WEBP" {
        Some("image/webp")
    } else {
        None
    }
}

/// Read the ID3 tag of a file. A file without any tag yields empty [`TrackTags`].
fn read_id3(path: &Path) -> Result<Option<Tag>> {
    match id3::v1v2::read_from_path(path) {
        Ok(tag) => Ok(Some(tag)),
        Err(e) if matches!(e.kind, ErrorKind::NoTag) => Ok(None),
        Err(e) => Err(e).with_context(|| format!("reading tag of {}", path.display())),
    }
}

/// Multi-value text frames are NUL separated; present them as a readable list.
fn clean(text: Option<&str>) -> Option<String> {
    let text = text?.trim_matches('\0').replace('\0', "; ");
    let text = text.trim();
    (!text.is_empty()).then(|| text.to_string())
}

fn text_frame(tag: &Tag, id: &str) -> Option<String> {
    clean(tag.get(id).and_then(|f| f.content().text()))
}

fn main_comment(tag: &Tag) -> Option<String> {
    tag.comments()
        .find(|c| c.description.is_empty())
        .or_else(|| tag.comments().next())
        .and_then(|c| clean(Some(&c.text)))
}

pub fn tags_from_id3(tag: &Tag) -> TrackTags {
    TrackTags {
        title: clean(tag.title()),
        artist: clean(tag.artist()),
        album_artist: clean(tag.album_artist()),
        album: clean(tag.album()),
        genre: clean(tag.genre_parsed().as_deref()),
        composer: text_frame(tag, "TCOM"),
        comment: main_comment(tag),
        year: tag
            .date_recorded()
            .map(|d| d.year)
            .or_else(|| tag.year())
            .or_else(|| tag.date_released().map(|d| d.year)),
        track: tag.track(),
        track_total: tag.total_tracks(),
        disc: tag.disc(),
        disc_total: tag.total_discs(),
        has_art: tag.pictures().next().is_some(),
    }
}

pub fn read_tags(path: &Path) -> Result<TrackTags> {
    Ok(read_id3(path)?.map(|t| tags_from_id3(&t)).unwrap_or_default())
}

/// Duration and bitrate. Failures are not fatal; plenty of real-world MP3s are slightly broken.
pub fn read_audio(path: &Path) -> Option<AudioInfo> {
    let mut file = File::open(path).ok()?;
    let mpeg = MpegFile::read_from(&mut file, ParseOptions::new().read_tags(false)).ok()?;
    let props = mpeg.properties();
    Some(AudioInfo { duration_ms: props.duration().as_millis() as u64, bitrate: props.audio_bitrate() })
}

/// The front cover if there is one, otherwise the first embedded picture.
pub fn read_art(path: &Path) -> Result<Option<Artwork>> {
    let Some(tag) = read_id3(path)? else { return Ok(None) };
    let pic = tag.pictures().find(|p| p.picture_type == PictureType::CoverFront).or_else(|| tag.pictures().next());
    Ok(pic.map(|p| Artwork {
        mime: sniff_image_mime(&p.data).unwrap_or(p.mime_type.as_str()).to_string(),
        data: p.data.clone(),
    }))
}

fn apply_text(
    tag: &mut Tag,
    edit: &Option<FieldEdit<String>>,
    set: impl FnOnce(&mut Tag, String),
    remove: impl FnOnce(&mut Tag),
) {
    match edit {
        Some(FieldEdit::Set(v)) if !v.trim().is_empty() => set(tag, v.trim().to_string()),
        Some(FieldEdit::Set(_)) | Some(FieldEdit::Clear) => remove(tag),
        None => {}
    }
}

fn apply_num(
    tag: &mut Tag,
    edit: &Option<FieldEdit<u32>>,
    set: impl FnOnce(&mut Tag, u32),
    remove: impl FnOnce(&mut Tag),
) {
    match edit {
        Some(FieldEdit::Set(v)) => set(tag, *v),
        Some(FieldEdit::Clear) => remove(tag),
        None => {}
    }
}

/// v2.3 files keep their year in TYER; v2.4 uses TDRC. Carry the value over so it isn't
/// lost (or left as an invalid frame) when the tag is rewritten as v2.4.
fn migrate_legacy_date(tag: &mut Tag) {
    if tag.date_recorded().is_none() {
        if let Some(year) = tag.year() {
            tag.set_date_recorded(Timestamp { year, month: None, day: None, hour: None, minute: None, second: None });
        }
    }
    for id in LEGACY_DATE_FRAMES {
        tag.remove(id);
    }
}

/// Apply `edits` to a tag in memory.
pub fn apply_edits(tag: &mut Tag, edits: &TagEdits, art: Option<&Artwork>) {
    apply_text(tag, &edits.title, |t, v| t.set_title(v), |t| t.remove_title());
    apply_text(tag, &edits.artist, |t, v| t.set_artist(v), |t| t.remove_artist());
    apply_text(tag, &edits.album_artist, |t, v| t.set_album_artist(v), |t| t.remove_album_artist());
    apply_text(tag, &edits.album, |t, v| t.set_album(v), |t| t.remove_album());
    apply_text(tag, &edits.genre, |t, v| t.set_genre(v), |t| t.remove_genre());
    apply_text(
        tag,
        &edits.composer,
        |t, v| t.set_text("TCOM", v),
        |t| {
            t.remove("TCOM");
        },
    );
    apply_text(
        tag,
        &edits.comment,
        |t, v| {
            t.remove_comment(Some(""), None);
            t.add_frame(Comment { lang: "eng".into(), description: String::new(), text: v });
        },
        |t| t.remove_comment(Some(""), None),
    );

    migrate_legacy_date(tag);
    match edits.year {
        Some(FieldEdit::Set(year)) => {
            tag.set_date_recorded(Timestamp { year, month: None, day: None, hour: None, minute: None, second: None })
        }
        Some(FieldEdit::Clear) => tag.remove_date_recorded(),
        None => {}
    }

    // Totals first: the number setters keep an existing "/total" suffix.
    apply_num(tag, &edits.track_total, |t, v| t.set_total_tracks(v), |t| t.remove_total_tracks());
    apply_num(tag, &edits.track, |t, v| t.set_track(v), |t| t.remove_track());
    apply_num(tag, &edits.disc_total, |t, v| t.set_total_discs(v), |t| t.remove_total_discs());
    apply_num(tag, &edits.disc, |t, v| t.set_disc(v), |t| t.remove_disc());

    match (&edits.art, art) {
        (Some(FieldEdit::Set(_)), Some(art)) => {
            tag.remove_picture_by_type(PictureType::CoverFront);
            tag.add_frame(Picture {
                mime_type: art.mime.clone(),
                picture_type: PictureType::CoverFront,
                description: String::new(),
                data: art.data.clone(),
            });
        }
        (Some(FieldEdit::Clear), _) => tag.remove_all_pictures(),
        _ => {}
    }
}

/// Apply `edits` to the file at `path`, writing ID3v2.4.
pub fn write_tags(path: &Path, edits: &TagEdits, art: Option<&Artwork>) -> Result<TrackTags> {
    // Refuse to write over a tag we couldn't parse rather than silently discarding it.
    let mut tag = read_id3(path)?.unwrap_or_default();
    apply_edits(&mut tag, edits, art);
    id3::v1v2::write_to_path(path, &tag, Version::Id3v24)
        .with_context(|| format!("writing tag of {}", path.display()))?;
    Ok(tags_from_id3(&tag))
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::io::Write;

    /// A few silent MPEG-1 Layer III frames, enough for tag round-trips.
    pub fn fake_mp3(dir: &Path, name: &str) -> std::path::PathBuf {
        let path = dir.join(name);
        let mut f = File::create(&path).unwrap();
        let mut frame = vec![0u8; 417];
        frame[..4].copy_from_slice(&[0xFF, 0xFB, 0x90, 0x64]);
        for _ in 0..20 {
            f.write_all(&frame).unwrap();
        }
        path
    }

    fn png() -> Artwork {
        Artwork { mime: "image/png".into(), data: b"\x89PNG\r\n\x1a\nrest".to_vec() }
    }

    #[test]
    fn untagged_file_reads_empty() {
        let dir = tempfile::tempdir().unwrap();
        let path = fake_mp3(dir.path(), "a.mp3");
        assert_eq!(read_tags(&path).unwrap(), TrackTags::default());
    }

    #[test]
    fn round_trip_all_fields() {
        let dir = tempfile::tempdir().unwrap();
        let path = fake_mp3(dir.path(), "a.mp3");
        let edits = TagEdits {
            title: Some(FieldEdit::Set("Title".into())),
            artist: Some(FieldEdit::Set("Artist".into())),
            album_artist: Some(FieldEdit::Set("Various".into())),
            album: Some(FieldEdit::Set("Album".into())),
            genre: Some(FieldEdit::Set("Rock".into())),
            composer: Some(FieldEdit::Set("Comp".into())),
            comment: Some(FieldEdit::Set("Nice".into())),
            year: Some(FieldEdit::Set(1999)),
            track: Some(FieldEdit::Set(3)),
            track_total: Some(FieldEdit::Set(12)),
            disc: Some(FieldEdit::Set(1)),
            disc_total: Some(FieldEdit::Set(2)),
            art: Some(FieldEdit::Set("x".into())),
        };
        write_tags(&path, &edits, Some(&png())).unwrap();
        let t = read_tags(&path).unwrap();
        assert_eq!(t.title.as_deref(), Some("Title"));
        assert_eq!(t.album_artist.as_deref(), Some("Various"));
        assert_eq!(t.genre.as_deref(), Some("Rock"));
        assert_eq!(t.composer.as_deref(), Some("Comp"));
        assert_eq!(t.comment.as_deref(), Some("Nice"));
        assert_eq!(
            (t.year, t.track, t.track_total, t.disc, t.disc_total),
            (Some(1999), Some(3), Some(12), Some(1), Some(2))
        );
        assert!(t.has_art);
        assert_eq!(read_art(&path).unwrap().unwrap().mime, "image/png");

        let tag = Tag::read_from_path(&path).unwrap();
        assert_eq!(tag.version(), Version::Id3v24);
        assert!(tag.get("TYER").is_none());
    }

    #[test]
    fn absent_fields_are_untouched_and_clear_removes() {
        let dir = tempfile::tempdir().unwrap();
        let path = fake_mp3(dir.path(), "a.mp3");
        let first = TagEdits {
            title: Some(FieldEdit::Set("Keep".into())),
            artist: Some(FieldEdit::Set("Gone".into())),
            track: Some(FieldEdit::Set(4)),
            art: Some(FieldEdit::Set("x".into())),
            ..Default::default()
        };
        write_tags(&path, &first, Some(&png())).unwrap();
        let second = TagEdits { artist: Some(FieldEdit::Clear), art: Some(FieldEdit::Clear), ..Default::default() };
        let t = write_tags(&path, &second, None).unwrap();
        assert_eq!(t.title.as_deref(), Some("Keep"));
        assert_eq!(t.track, Some(4));
        assert_eq!(t.artist, None);
        assert!(!t.has_art);
        assert_eq!(read_tags(&path).unwrap(), t);
    }

    #[test]
    fn v23_year_is_migrated() {
        let dir = tempfile::tempdir().unwrap();
        let path = fake_mp3(dir.path(), "a.mp3");
        let mut tag = Tag::new();
        tag.set_year(1987);
        tag.set_title("Old");
        tag.write_to_path(&path, Version::Id3v23).unwrap();
        assert_eq!(read_tags(&path).unwrap().year, Some(1987));

        let t = write_tags(&path, &TagEdits { title: Some(FieldEdit::Set("New".into())), ..Default::default() }, None)
            .unwrap();
        assert_eq!(t.year, Some(1987));
        let tag = Tag::read_from_path(&path).unwrap();
        assert!(tag.get("TYER").is_none());
        assert_eq!(tag.date_recorded().unwrap().year, 1987);
    }

    #[test]
    fn edits_deserialize_from_json() {
        let e: TagEdits = serde_json::from_str(r#"{"title":{"op":"set","value":"X"},"year":{"op":"clear"}}"#).unwrap();
        assert_eq!(e.title, Some(FieldEdit::Set("X".into())));
        assert_eq!(e.year, Some(FieldEdit::Clear));
        assert!(e.artist.is_none());
    }

    #[test]
    fn stage_image_keeps_only_the_latest_and_rejects_non_images() {
        let dir = tempfile::tempdir().unwrap();
        let staged = dir.path().join("staged");
        let first = stage_image(&staged, b"\x89PNG\r\n\x1a\nrest").unwrap();
        assert_eq!(first.extension().unwrap(), "png");
        std::thread::sleep(std::time::Duration::from_millis(2));
        let second = stage_image(&staged, &[0xFF, 0xD8, 0xFF, 0xE0, 1, 2]).unwrap();
        assert_eq!(second.extension().unwrap(), "jpg");
        assert!(!first.exists());
        assert_eq!(Artwork::load(&second).unwrap().mime, "image/jpeg");
        assert!(stage_image(&staged, b"BM not supported").is_err());
        assert!(second.exists(), "a rejected paste leaves the pending image alone");
    }
}
