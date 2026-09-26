//! Path templates such as `<AlbumArtist>/<Album> (<Year>)/<Disc>-<Track:2> <Title>`.
//!
//! `/` in the template separates directories. Values have path separators and characters
//! that are awkward on other filesystems replaced, so a tag can never escape its segment.
//! The original extension (`.mp3`) is always appended.

use crate::db::Track;

pub const TOKENS: [(&str, &str); 14] = [
    ("Artist", "Track artist (\"Unknown Artist\" if blank)"),
    ("AlbumArtist", "Album artist, falling back to the track artist"),
    ("Album", "Album (\"Unknown Album\" if blank)"),
    ("Title", "Title, falling back to the original file name"),
    ("Genre", "Genre (\"Unknown Genre\" if blank)"),
    ("Year", "Year"),
    ("Composer", "Composer"),
    ("Disc", "Disc number; <Disc:N> zero-pads to N digits"),
    ("DiscTotal", "Total discs; <DiscTotal:N> zero-pads"),
    ("Track", "Track number; <Track:N> zero-pads to N digits"),
    ("TrackTotal", "Total tracks; <TrackTotal:N> zero-pads"),
    ("Filename", "Original file name without extension"),
    ("Dir", "Original folder, relative to the library"),
    ("Bitrate", "Bitrate in kbps"),
];

#[derive(Debug, Clone, PartialEq)]
enum Part {
    Literal(String),
    Token { name: String, pad: Option<usize> },
}

fn parse(template: &str) -> Result<Vec<Part>, String> {
    let mut parts = Vec::new();
    let mut rest = template;
    while let Some(start) = rest.find('<') {
        if start > 0 {
            parts.push(Part::Literal(rest[..start].to_string()));
        }
        let after = &rest[start + 1..];
        let end = after.find('>').ok_or_else(|| format!("unclosed '<' in {template:?}"))?;
        let inner = &after[..end];
        let (name, pad) = match inner.split_once(':') {
            Some((n, p)) => {
                let pad: usize = p.trim().parse().map_err(|_| format!("<{inner}>: padding must be a number"))?;
                if pad > 10 {
                    return Err(format!("<{inner}>: padding is too large"));
                }
                (n.trim(), Some(pad))
            }
            None => (inner.trim(), None),
        };
        let canonical = TOKENS
            .iter()
            .map(|(t, _)| *t)
            .find(|t| t.eq_ignore_ascii_case(name))
            .ok_or_else(|| format!("unknown token <{name}>"))?;
        if pad.is_some() && !matches!(canonical, "Disc" | "DiscTotal" | "Track" | "TrackTotal") {
            return Err(format!("<{inner}>: only numeric tokens can be padded"));
        }
        parts.push(Part::Token { name: canonical.to_string(), pad });
        rest = &after[end + 1..];
    }
    if !rest.is_empty() {
        parts.push(Part::Literal(rest.to_string()));
    }
    if parts.is_empty() {
        return Err("template is empty".into());
    }
    Ok(parts)
}

/// Check a template for errors without rendering it.
pub fn validate(template: &str) -> Result<(), String> {
    parse(template).map(|_| ())
}

fn text(v: &Option<String>) -> Option<&str> {
    v.as_deref().map(str::trim).filter(|s| !s.is_empty())
}

fn number(v: Option<u32>, pad: Option<usize>) -> String {
    match v {
        Some(n) => format!("{n:0width$}", width = pad.unwrap_or(0)),
        None => String::new(),
    }
}

fn stem(filename: &str) -> &str {
    filename.rsplit_once('.').map(|(s, _)| s).filter(|s| !s.is_empty()).unwrap_or(filename)
}

fn token_value(name: &str, pad: Option<usize>, t: &Track) -> String {
    match name {
        "Artist" => text(&t.artist).unwrap_or("Unknown Artist").to_string(),
        "AlbumArtist" => text(&t.album_artist).or(text(&t.artist)).unwrap_or("Unknown Artist").to_string(),
        "Album" => text(&t.album).unwrap_or("Unknown Album").to_string(),
        "Title" => text(&t.title).unwrap_or(stem(&t.filename)).to_string(),
        "Genre" => text(&t.genre).unwrap_or("Unknown Genre").to_string(),
        "Composer" => text(&t.composer).unwrap_or("").to_string(),
        "Year" => t.year.map(|y| y.to_string()).unwrap_or_default(),
        "Disc" => number(t.disc, pad),
        "DiscTotal" => number(t.disc_total, pad),
        "Track" => number(t.track, pad),
        "TrackTotal" => number(t.track_total, pad),
        "Filename" => stem(&t.filename).to_string(),
        // Dir is the one token allowed to contribute directory separators.
        "Dir" => return t.dir.clone(),
        "Bitrate" => t.bitrate.map(|b| b.to_string()).unwrap_or_default(),
        _ => String::new(),
    }
    .chars()
    .map(|c| match c {
        '/' | '\\' | ':' => '-',
        '*' | '?' | '"' | '<' | '>' | '|' => '_',
        c if c.is_control() => '_',
        c => c,
    })
    .collect()
}

/// Tidy one path segment: drop brackets left empty by blank tokens, collapse whitespace,
/// trim, avoid hidden/relative names, and keep within filesystem name limits.
fn clean_segment(seg: &str) -> String {
    let mut s = seg.to_string();
    loop {
        let before = s.len();
        for empty in ["()", "[]", "{}", "( )", "[ ]"] {
            s = s.replace(empty, "");
        }
        if s.len() == before {
            break;
        }
    }
    let mut s = s.split_whitespace().collect::<Vec<_>>().join(" ");
    // Separators left dangling by empty tokens, e.g. "01 - " or " - Title".
    for sep in [" -", ","] {
        while s.ends_with(sep) {
            s.truncate(s.len() - sep.len());
            s = s.trim_end().to_string();
        }
    }
    while let Some(rest) = s.strip_prefix("- ") {
        s = rest.trim_start().to_string();
    }
    let s = s.trim().to_string();
    let mut s = match s.strip_prefix('.') {
        Some(rest) => format!("_{rest}"),
        None => s,
    };
    // 255 bytes, leaving room for ".mp3".
    while s.len() > 250 {
        s.pop();
    }
    s
}

/// Render a template for one track into a path relative to the library root.
pub fn render(template: &str, t: &Track) -> Result<String, String> {
    let parts = parse(template)?;
    let mut out = String::new();
    for p in &parts {
        match p {
            Part::Literal(s) => out.push_str(s),
            Part::Token { name, pad } => out.push_str(&token_value(name, *pad, t)),
        }
    }
    let segments: Vec<String> = out.split(['/', '\\']).map(clean_segment).filter(|s| !s.is_empty()).collect();
    let Some((file, dirs)) = segments.split_last() else {
        return Err("template produced an empty path".into());
    };
    let ext = t.filename.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_else(|| "mp3".into());
    let mut path = dirs.join("/");
    if !path.is_empty() {
        path.push('/');
    }
    path.push_str(file);
    path.push('.');
    path.push_str(&ext);
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn track() -> Track {
        Track {
            id: 1,
            path: "old/dir/01 thing.MP3".into(),
            dir: "old/dir".into(),
            filename: "01 thing.MP3".into(),
            title: Some("Don't Stop Me Now".into()),
            artist: Some("Queen".into()),
            album_artist: None,
            album: Some("Jazz: Remastered/2011".into()),
            genre: Some("Rock".into()),
            composer: None,
            comment: None,
            year: Some(1978),
            track: Some(12),
            track_total: Some(13),
            disc: Some(1),
            disc_total: None,
            has_art: false,
            duration_ms: None,
            bitrate: Some(320),
            size: 0,
            error: None,
        }
    }

    #[test]
    fn renders_tokens_and_padding() {
        let t = track();
        assert_eq!(
            render("<AlbumArtist>/<Album> (<Year>)/<Disc>-<Track:3> <Title>", &t).unwrap(),
            "Queen/Jazz- Remastered-2011 (1978)/1-012 Don't Stop Me Now.mp3"
        );
        assert_eq!(render("<genre>/<Filename>", &t).unwrap(), "Rock/01 thing.mp3");
        assert_eq!(render("<Dir>/<Track:2>", &t).unwrap(), "old/dir/12.mp3");
    }

    #[test]
    fn blanks_are_tidied() {
        let mut t = track();
        t.year = None;
        t.track = None;
        t.title = None;
        t.artist = None;
        assert_eq!(
            render("<Artist>/<Album> [<Year>]/<Track:2> - <Title>", &t).unwrap(),
            "Unknown Artist/Jazz- Remastered-2011/01 thing.mp3"
        );
        t.album = Some("..".into());
        assert_eq!(render("<Album>/<Title>", &t).unwrap(), "_./01 thing.mp3");
    }

    #[test]
    fn rejects_bad_templates() {
        assert!(render("<Nope>", &track()).is_err());
        assert!(render("<Title", &track()).is_err());
        assert!(render("<Title:2>", &track()).is_err());
        assert!(render("", &track()).is_err());
        assert!(render("<Composer>", &track()).is_err());
    }
}
