//! SQLite index of the library. The MP3 files are the source of truth; this is a cache
//! that makes filtering and sorting thousands of files instant.

use std::collections::HashMap;
use std::path::Path;

use anyhow::Result;
use rusqlite::{params, params_from_iter, types::Value, Connection, OptionalExtension, Row};
use serde::{Deserialize, Serialize};

use crate::tags::{AudioInfo, TrackTags};

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tracks (
    id           INTEGER PRIMARY KEY,
    path         TEXT NOT NULL UNIQUE,  -- relative to the library root
    dir          TEXT NOT NULL,
    filename     TEXT NOT NULL,
    title        TEXT,
    artist       TEXT,
    album_artist TEXT,
    album        TEXT,
    genre        TEXT,
    composer     TEXT,
    comment      TEXT,
    year         INTEGER,
    track        INTEGER,
    track_total  INTEGER,
    disc         INTEGER,
    disc_total   INTEGER,
    has_art      INTEGER NOT NULL DEFAULT 0,
    duration_ms  INTEGER,
    bitrate      INTEGER,
    mtime        INTEGER NOT NULL,
    size         INTEGER NOT NULL,
    error        TEXT
);
";

const COLUMNS: &str = "id, path, dir, filename, title, artist, album_artist, album, genre, composer, comment, \
     year, track, track_total, disc, disc_total, has_art, duration_ms, bitrate, size, error";

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Track {
    pub id: i64,
    pub path: String,
    pub dir: String,
    pub filename: String,
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
    pub duration_ms: Option<i64>,
    pub bitrate: Option<i64>,
    pub size: i64,
    /// Set when the file's tag could not be parsed.
    pub error: Option<String>,
}

impl Track {
    fn from_row(r: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: r.get(0)?,
            path: r.get(1)?,
            dir: r.get(2)?,
            filename: r.get(3)?,
            title: r.get(4)?,
            artist: r.get(5)?,
            album_artist: r.get(6)?,
            album: r.get(7)?,
            genre: r.get(8)?,
            composer: r.get(9)?,
            comment: r.get(10)?,
            year: r.get(11)?,
            track: r.get(12)?,
            track_total: r.get(13)?,
            disc: r.get(14)?,
            disc_total: r.get(15)?,
            has_art: r.get(16)?,
            duration_ms: r.get(17)?,
            bitrate: r.get(18)?,
            size: r.get(19)?,
            error: r.get(20)?,
        })
    }
}

/// Everything learned about a file during a scan.
#[derive(Debug, Clone)]
pub struct ScannedFile {
    pub rel_path: String,
    pub mtime: i64,
    pub size: i64,
    pub tags: std::result::Result<TrackTags, String>,
    pub audio: Option<AudioInfo>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Filter {
    pub field: String,
    pub op: String,
    #[serde(default)]
    pub value: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default)]
pub struct Query {
    /// Free text; every word must appear in some tag, the path, or the file name.
    pub search: String,
    pub filters: Vec<Filter>,
    pub sort: Option<String>,
    pub desc: bool,
}

#[derive(Clone, Copy, PartialEq)]
enum Kind {
    Text,
    Number,
    Bool,
}

fn column(field: &str) -> Option<(&'static str, Kind)> {
    use Kind::*;
    Some(match field {
        "title" => ("title", Text),
        "artist" => ("artist", Text),
        "album_artist" => ("album_artist", Text),
        "album" => ("album", Text),
        "genre" => ("genre", Text),
        "composer" => ("composer", Text),
        "comment" => ("comment", Text),
        "path" => ("path", Text),
        "dir" => ("dir", Text),
        "filename" => ("filename", Text),
        "year" => ("year", Number),
        "track" => ("track", Number),
        "track_total" => ("track_total", Number),
        "disc" => ("disc", Number),
        "disc_total" => ("disc_total", Number),
        "bitrate" => ("bitrate", Number),
        "duration" => ("duration_ms / 1000", Number),
        "has_art" => ("has_art", Bool),
        "has_error" => ("(error IS NOT NULL AND error <> '')", Bool),
        _ => return None,
    })
}

const SEARCH_COLUMNS: [&str; 7] = ["title", "artist", "album_artist", "album", "genre", "composer", "path"];

fn like_escape(s: &str) -> String {
    s.replace('\\', "\\\\").replace('%', "\\%").replace('_', "\\_")
}

/// Build a WHERE clause for `q`. Returns the SQL fragment and its bound values.
pub fn build_where(q: &Query) -> Result<(String, Vec<Value>)> {
    let mut clauses: Vec<String> = Vec::new();
    let mut vals: Vec<Value> = Vec::new();

    for word in q.search.split_whitespace() {
        let any: Vec<String> = SEARCH_COLUMNS.iter().map(|c| format!("{c} LIKE ? ESCAPE '\\'")).collect();
        clauses.push(format!("({})", any.join(" OR ")));
        let pat = format!("%{}%", like_escape(word));
        vals.extend(SEARCH_COLUMNS.iter().map(|_| Value::Text(pat.clone())));
    }

    for f in &q.filters {
        let (col, kind) = column(&f.field).ok_or_else(|| anyhow::anyhow!("unknown filter field {:?}", f.field))?;
        let v = f.value.trim();
        let empty =
            if kind == Kind::Text { format!("({col} IS NULL OR {col} = '')") } else { format!("{col} IS NULL") };
        if kind == Kind::Bool {
            clauses.push(format!("{col} = ?"));
            vals.push(Value::Integer(matches!(f.op.as_str(), "yes" | "is_true") as i64));
            continue;
        }
        match f.op.as_str() {
            "empty" => {
                clauses.push(empty);
                continue;
            }
            "not_empty" => {
                clauses.push(format!("NOT {empty}"));
                continue;
            }
            _ => {}
        }
        // A value-based condition with no value would match nothing useful; ignore it
        // so a half-typed filter row doesn't blank the table.
        if v.is_empty() {
            continue;
        }
        if kind == Kind::Number {
            let n: f64 = v.parse().map_err(|_| anyhow::anyhow!("{:?} is not a number", v))?;
            let op = match f.op.as_str() {
                "equals" => "=",
                "not_equals" => "!=",
                "gt" => ">",
                "gte" => ">=",
                "lt" => "<",
                "lte" => "<=",
                other => anyhow::bail!("operator {other:?} does not apply to numbers"),
            };
            if op == "!=" {
                clauses.push(format!("({col} IS NULL OR {col} != ?)"));
            } else {
                clauses.push(format!("{col} {op} ?"));
            }
            vals.push(Value::Real(n));
            continue;
        }
        let esc = like_escape(v);
        let (sql, pat) = match f.op.as_str() {
            "contains" => (format!("{col} LIKE ? ESCAPE '\\'"), format!("%{esc}%")),
            "not_contains" => (format!("({col} IS NULL OR {col} NOT LIKE ? ESCAPE '\\')"), format!("%{esc}%")),
            "equals" => (format!("{col} = ? COLLATE NOCASE"), v.to_string()),
            "not_equals" => (format!("({col} IS NULL OR {col} != ? COLLATE NOCASE)"), v.to_string()),
            "starts_with" => (format!("{col} LIKE ? ESCAPE '\\'"), format!("{esc}%")),
            "ends_with" => (format!("{col} LIKE ? ESCAPE '\\'"), format!("%{esc}")),
            other => anyhow::bail!("operator {other:?} does not apply to text"),
        };
        clauses.push(sql);
        vals.push(Value::Text(pat));
    }

    let sql = if clauses.is_empty() { String::new() } else { format!("WHERE {}", clauses.join(" AND ")) };
    Ok((sql, vals))
}

fn order_by(q: &Query) -> String {
    let dir = if q.desc { "DESC" } else { "ASC" };
    let natural =
        "album_artist IS NULL, COALESCE(album_artist, artist) COLLATE NOCASE, album COLLATE NOCASE, disc, track, path";
    match q.sort.as_deref().and_then(|s| column(s).map(|c| (s, c))) {
        None => natural.to_string(),
        Some((_, (col, kind))) => {
            let collate = if kind == Kind::Text { " COLLATE NOCASE" } else { "" };
            // Blank values always sort last regardless of direction.
            format!("({col} IS NULL) ASC, {col}{collate} {dir}, path")
        }
    }
}

pub struct Db {
    conn: Connection,
}

impl Db {
    pub fn open(path: &Path) -> Result<Self> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        Self::init(Connection::open(path)?)
    }

    pub fn open_in_memory() -> Result<Self> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> Result<Self> {
        conn.execute_batch("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;")?;
        conn.execute_batch(SCHEMA)?;
        Ok(Self { conn })
    }

    pub fn meta(&self, key: &str) -> Result<Option<String>> {
        Ok(self.conn.query_row("SELECT value FROM meta WHERE key = ?", [key], |r| r.get(0)).optional()?)
    }

    pub fn set_meta(&self, key: &str, value: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO meta (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = ?2",
            [key, value],
        )?;
        Ok(())
    }

    /// Point the index at a library root, discarding everything if the root changed.
    pub fn set_root(&self, root: &str) -> Result<()> {
        if self.meta("library_root")?.as_deref() != Some(root) {
            self.conn.execute("DELETE FROM tracks", [])?;
            self.set_meta("library_root", root)?;
        }
        Ok(())
    }

    pub fn count(&self) -> Result<i64> {
        Ok(self.conn.query_row("SELECT COUNT(*) FROM tracks", [], |r| r.get(0))?)
    }

    /// path -> (mtime, size) for change detection.
    pub fn file_stats(&self) -> Result<HashMap<String, (i64, i64)>> {
        let mut stmt = self.conn.prepare("SELECT path, mtime, size FROM tracks")?;
        let rows = stmt.query_map([], |r| Ok((r.get(0)?, (r.get(1)?, r.get(2)?))))?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn file_stat(&self, rel_path: &str) -> Result<Option<(i64, i64)>> {
        Ok(self
            .conn
            .query_row("SELECT mtime, size FROM tracks WHERE path = ?", [rel_path], |r| Ok((r.get(0)?, r.get(1)?)))
            .optional()?)
    }

    pub fn upsert_many(&mut self, files: &[ScannedFile]) -> Result<()> {
        let tx = self.conn.transaction()?;
        {
            let mut stmt = tx.prepare(
                "INSERT INTO tracks (path, dir, filename, title, artist, album_artist, album, genre, composer, comment,
                    year, track, track_total, disc, disc_total, has_art, duration_ms, bitrate, mtime, size, error)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21)
                 ON CONFLICT(path) DO UPDATE SET
                    title = ?4, artist = ?5, album_artist = ?6, album = ?7, genre = ?8, composer = ?9, comment = ?10,
                    year = ?11, track = ?12, track_total = ?13, disc = ?14, disc_total = ?15, has_art = ?16,
                    duration_ms = COALESCE(?17, duration_ms), bitrate = COALESCE(?18, bitrate),
                    mtime = ?19, size = ?20, error = ?21",
            )?;
            for f in files {
                let (dir, filename) = split_rel(&f.rel_path);
                let (t, err) = match &f.tags {
                    Ok(t) => (t.clone(), None),
                    Err(e) => (TrackTags::default(), Some(e.clone())),
                };
                stmt.execute(params![
                    f.rel_path,
                    dir,
                    filename,
                    t.title,
                    t.artist,
                    t.album_artist,
                    t.album,
                    t.genre,
                    t.composer,
                    t.comment,
                    t.year,
                    t.track,
                    t.track_total,
                    t.disc,
                    t.disc_total,
                    t.has_art,
                    f.audio.map(|a| a.duration_ms as i64),
                    f.audio.map(|a| a.bitrate as i64),
                    f.mtime,
                    f.size,
                    err,
                ])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// Update just the tag columns of a track after the app itself wrote the file.
    pub fn update_tags(&self, id: i64, t: &TrackTags, mtime: i64, size: i64) -> Result<()> {
        self.conn.execute(
            "UPDATE tracks SET title = ?2, artist = ?3, album_artist = ?4, album = ?5, genre = ?6, composer = ?7,
                comment = ?8, year = ?9, track = ?10, track_total = ?11, disc = ?12, disc_total = ?13, has_art = ?14,
                mtime = ?15, size = ?16, error = NULL
             WHERE id = ?1",
            params![
                id,
                t.title,
                t.artist,
                t.album_artist,
                t.album,
                t.genre,
                t.composer,
                t.comment,
                t.year,
                t.track,
                t.track_total,
                t.disc,
                t.disc_total,
                t.has_art,
                mtime,
                size
            ],
        )?;
        Ok(())
    }

    pub fn update_path(&self, id: i64, rel_path: &str, mtime: i64) -> Result<()> {
        let (dir, filename) = split_rel(rel_path);
        self.conn.execute(
            "UPDATE tracks SET path = ?2, dir = ?3, filename = ?4, mtime = ?5 WHERE id = ?1",
            params![id, rel_path, dir, filename, mtime],
        )?;
        Ok(())
    }

    pub fn delete_paths(&mut self, paths: &[String]) -> Result<usize> {
        let tx = self.conn.transaction()?;
        let mut n = 0;
        {
            let mut stmt = tx.prepare("DELETE FROM tracks WHERE path = ?")?;
            for p in paths {
                n += stmt.execute([p])?;
            }
        }
        tx.commit()?;
        Ok(n)
    }

    /// Remove every track at or below a directory (used when a folder disappears).
    pub fn delete_under(&self, rel_dir: &str) -> Result<usize> {
        let prefix = format!("{}/%", like_escape(rel_dir));
        Ok(self
            .conn
            .execute("DELETE FROM tracks WHERE path LIKE ? ESCAPE '\\' OR path = ?", params![prefix, rel_dir])?)
    }

    pub fn query(&self, q: &Query) -> Result<Vec<Track>> {
        let (where_sql, vals) = build_where(q)?;
        let sql = format!("SELECT {COLUMNS} FROM tracks {where_sql} ORDER BY {}", order_by(q));
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(params_from_iter(vals), Track::from_row)?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn get(&self, ids: &[i64]) -> Result<Vec<Track>> {
        let mut stmt = self.conn.prepare_cached(&format!("SELECT {COLUMNS} FROM tracks WHERE id = ?"))?;
        let mut out = Vec::with_capacity(ids.len());
        for id in ids {
            if let Some(t) = stmt.query_row([id], Track::from_row).optional()? {
                out.push(t);
            }
        }
        Ok(out)
    }

    /// Distinct non-empty values of a text column, for autocompletion.
    pub fn distinct(&self, field: &str) -> Result<Vec<String>> {
        let Some((col, Kind::Text)) = column(field) else { anyhow::bail!("unknown field {field:?}") };
        let mut stmt = self.conn.prepare(&format!(
            "SELECT DISTINCT {col} FROM tracks WHERE {col} IS NOT NULL AND {col} != '' ORDER BY {col} COLLATE NOCASE"
        ))?;
        let rows = stmt.query_map([], |r| r.get(0))?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }
}

/// Split "a/b/c.mp3" into ("a/b", "c.mp3").
pub fn split_rel(rel: &str) -> (&str, &str) {
    match rel.rfind('/') {
        Some(i) => (&rel[..i], &rel[i + 1..]),
        None => ("", rel),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file(path: &str, artist: &str, album: &str, year: Option<i32>) -> ScannedFile {
        ScannedFile {
            rel_path: path.into(),
            mtime: 1,
            size: 2,
            tags: Ok(TrackTags {
                artist: Some(artist.into()),
                album: Some(album.into()),
                title: Some(format!("{artist} song")),
                year,
                ..Default::default()
            }),
            audio: None,
        }
    }

    fn db() -> Db {
        let mut db = Db::open_in_memory().unwrap();
        db.upsert_many(&[
            file("Rock/Queen/a.mp3", "Queen", "Jazz", Some(1978)),
            file("Rock/Queen 100%/b.mp3", "Queen", "Innuendo", Some(1991)),
            file("Pop/c.mp3", "Madonna", "Ray of Light", None),
        ])
        .unwrap();
        db
    }

    fn paths(db: &Db, q: Query) -> Vec<String> {
        let mut p: Vec<_> = db.query(&q).unwrap().into_iter().map(|t| t.path).collect();
        p.sort();
        p
    }

    fn f(field: &str, op: &str, value: &str) -> Filter {
        Filter { field: field.into(), op: op.into(), value: value.into() }
    }

    #[test]
    fn search_matches_every_word() {
        let db = db();
        assert_eq!(paths(&db, Query { search: "queen jazz".into(), ..Default::default() }), vec!["Rock/Queen/a.mp3"]);
        assert_eq!(paths(&db, Query { search: "pop".into(), ..Default::default() }), vec!["Pop/c.mp3"]);
    }

    #[test]
    fn filters() {
        let db = db();
        let q = |fs| Query { filters: fs, ..Default::default() };
        assert_eq!(paths(&db, q(vec![f("year", "gt", "1980")])), vec!["Rock/Queen 100%/b.mp3"]);
        assert_eq!(paths(&db, q(vec![f("year", "empty", "")])), vec!["Pop/c.mp3"]);
        assert_eq!(paths(&db, q(vec![f("dir", "contains", "100%")])), vec!["Rock/Queen 100%/b.mp3"]);
        assert_eq!(paths(&db, q(vec![f("filename", "equals", "A.MP3")])), vec!["Rock/Queen/a.mp3"]);
        assert_eq!(paths(&db, q(vec![f("artist", "not_equals", "queen")])), vec!["Pop/c.mp3"]);
        assert_eq!(
            paths(&db, q(vec![f("path", "starts_with", "rock/"), f("album", "ends_with", "endo")])),
            vec!["Rock/Queen 100%/b.mp3"]
        );
        // A half-typed filter is ignored.
        assert_eq!(paths(&db, q(vec![f("artist", "contains", " ")])).len(), 3);
        assert!(db.query(&q(vec![f("bogus", "contains", "x")])).is_err());
    }

    #[test]
    fn has_error_filter() {
        let mut db = db();
        let broken =
            ScannedFile { rel_path: "Bad/d.mp3".into(), mtime: 1, size: 2, tags: Err("bad frame".into()), audio: None };
        db.upsert_many(&[broken]).unwrap();
        let q = |op: &str| Query { filters: vec![f("has_error", op, "")], ..Default::default() };
        assert_eq!(paths(&db, q("yes")), vec!["Bad/d.mp3"]);
        assert_eq!(paths(&db, q("no")).len(), 3);
    }

    #[test]
    fn sorting_puts_blanks_last() {
        let db = db();
        let q = |desc| Query { sort: Some("year".into()), desc, ..Default::default() };
        let years = |q| db.query(&q).unwrap().into_iter().map(|t| t.year).collect::<Vec<_>>();
        assert_eq!(years(q(false)), vec![Some(1978), Some(1991), None]);
        assert_eq!(years(q(true)), vec![Some(1991), Some(1978), None]);
    }

    #[test]
    fn delete_under_dir() {
        let db = db();
        assert_eq!(db.delete_under("Rock/Queen").unwrap(), 1);
        assert_eq!(db.count().unwrap(), 2);
    }

    #[test]
    fn root_change_clears() {
        let db = db();
        db.set_root("/a").unwrap();
        assert_eq!(db.count().unwrap(), 0);
    }
}
