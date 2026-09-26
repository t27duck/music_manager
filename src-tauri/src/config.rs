//! User settings, stored as JSON in the XDG config directory.

use std::path::PathBuf;

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

fn config_path() -> PathBuf {
    dirs::config_dir().unwrap_or_else(|| PathBuf::from(".")).join(APP_DIR).join("config.json")
}

pub fn db_path() -> PathBuf {
    dirs::data_dir().unwrap_or_else(|| PathBuf::from(".")).join(APP_DIR).join("library.db")
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
