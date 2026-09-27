//! User settings, stored as JSON in the XDG config directory, and where the app keeps its files.

use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use serde::{Deserialize, Serialize};

const APP_DIR: &str = "music-manager";

pub const DEFAULT_TEMPLATES: [&str; 3] = [
    "<AlbumArtist>/<Album>/<Track:2> <Title>",
    "<AlbumArtist>/<Album> (<Year>)/<Disc>-<Track:2> <Title>",
    "<Genre>/<Artist> - <Title>",
];

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    pub library_path: Option<String>,
    /// Saved reorganize templates, most recently used first.
    pub templates: Vec<String>,
}

impl Default for Config {
    fn default() -> Self {
        Self { library_path: None, templates: DEFAULT_TEMPLATES.iter().map(|s| s.to_string()).collect() }
    }
}

/// A `data` folder next to the executable makes the app portable: settings, the index, pasted
/// art and (on Windows) the WebView's storage are all kept in it instead of the user profile.
pub fn portable_dir() -> Option<&'static Path> {
    static DIR: OnceLock<Option<PathBuf>> = OnceLock::new();
    DIR.get_or_init(|| portable_dir_for(&std::env::current_exe().ok()?)).as_deref()
}

fn portable_dir_for(exe: &Path) -> Option<PathBuf> {
    let dir = exe.parent()?.join("data");
    dir.is_dir().then_some(dir)
}

/// The portable folder, or the app's folder under a platform directory such as `dirs::config_dir()`.
fn app_dir(base: Option<PathBuf>) -> PathBuf {
    match portable_dir() {
        Some(dir) => dir.to_path_buf(),
        None => base.unwrap_or_else(|| PathBuf::from(".")).join(APP_DIR),
    }
}

fn config_path() -> PathBuf {
    app_dir(dirs::config_dir()).join("config.json")
}

/// Where pasted album art is kept until it's saved into files.
pub fn staged_art_dir() -> PathBuf {
    app_dir(Some(dirs::cache_dir().unwrap_or_else(std::env::temp_dir))).join("pasted-art")
}

pub fn db_path() -> PathBuf {
    app_dir(dirs::data_dir()).join("library.db")
}

impl Config {
    pub fn load() -> Self {
        std::fs::read_to_string(config_path()).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()
    }

    pub fn save(&self) -> anyhow::Result<()> {
        let path = config_path();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let tmp = path.with_extension("json.tmp");
        std::fs::write(&tmp, serde_json::to_string_pretty(self)?)?;
        std::fs::rename(tmp, path)?;
        Ok(())
    }

    pub fn remember_template(&mut self, template: &str) {
        self.templates.retain(|t| t != template);
        self.templates.insert(0, template.to_string());
        self.templates.truncate(20);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn data_folder_beside_the_executable_makes_it_portable() {
        let dir = tempfile::tempdir().unwrap();
        let exe = dir.path().join("music-manager.exe");
        assert_eq!(portable_dir_for(&exe), None);
        std::fs::write(dir.path().join("data"), b"").unwrap();
        assert_eq!(portable_dir_for(&exe), None, "a file named data doesn't count");
        std::fs::remove_file(dir.path().join("data")).unwrap();
        std::fs::create_dir(dir.path().join("data")).unwrap();
        assert_eq!(portable_dir_for(&exe), Some(dir.path().join("data")));
    }
}
