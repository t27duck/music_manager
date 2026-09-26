mod commands;
mod config;
pub mod db;
pub mod player;
pub mod reorganize;
pub mod scanner;
pub mod tags;
pub mod template;
mod watcher;

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};

use crate::config::Config;
use crate::db::Db;

pub struct AppState {
    pub db: Mutex<Db>,
    pub config: Mutex<Config>,
    /// Serializes everything that touches files: scans, tag writes, reorganizing and
    /// watcher syncs. This keeps the watcher from racing the app's own changes.
    pub op_lock: Mutex<()>,
    pub scanning: AtomicBool,
    pub watcher: Mutex<Option<watcher::LibraryWatcher>>,
    /// Started in `setup` once there is an app handle to emit status events with.
    pub player: std::sync::OnceLock<player::AudioPlayer>,
}

impl AppState {
    pub fn root(&self) -> Option<PathBuf> {
        self.config.lock().unwrap().library_path.as_ref().map(PathBuf::from)
    }
}

#[derive(Clone, Serialize)]
struct Progress<'a> {
    kind: &'a str,
    done: usize,
    total: usize,
}

/// Emits progress events at most every 100ms (plus the final one) to keep IPC quiet.
pub(crate) fn progress_emitter(app: &AppHandle, kind: &'static str) -> impl FnMut(usize, usize) {
    let app = app.clone();
    let mut last = Instant::now() - Duration::from_secs(1);
    move |done, total| {
        if done == total || last.elapsed() >= Duration::from_millis(100) {
            last = Instant::now();
            let _ = app.emit("progress", Progress { kind, done, total });
        }
    }
}

/// Scan the configured library in the background, then (re)start watching it.
pub(crate) fn start_library(app: &AppHandle) {
    let state = app.state::<Arc<AppState>>().inner().clone();
    if state.root().is_none() || state.scanning.swap(true, Ordering::SeqCst) {
        return;
    }
    let app = app.clone();
    std::thread::spawn(move || {
        // Drop the old watcher before taking the lock: dropping waits for its handler,
        // which may itself be waiting on the lock.
        drop(state.watcher.lock().unwrap().take());
        let guard = state.op_lock.lock().unwrap();
        // Read the root only now: the library may have been switched while we waited, in
        // which case the switch's own start_library call deferred to this scan.
        let Some(root) = state.root() else {
            state.scanning.store(false, Ordering::SeqCst);
            return;
        };
        let _ = app.emit("scan-started", ());
        let result = scanner::full_scan(&state.db, &root, progress_emitter(&app, "scan"));
        let stale = match watcher::LibraryWatcher::start(app.clone(), state.clone(), root) {
            Ok(w) => state.watcher.lock().unwrap().replace(w),
            Err(e) => {
                let _ = app.emit("scan-failed", format!("could not watch library: {e:#}"));
                None
            }
        };
        state.scanning.store(false, Ordering::SeqCst);
        drop(guard);
        drop(stale);
        match result {
            Ok(summary) => {
                let _ = app.emit("scan-finished", summary);
            }
            Err(e) => {
                let _ = app.emit("scan-failed", format!("{e:#}"));
            }
        }
    });
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // WebKitGTK's DMA-BUF renderer shows a blank window on some GPU/driver combos
    // (notably NVIDIA). Users can still opt back in by setting the variable themselves.
    if std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none() {
        std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }

    let config = Config::load();
    let db = Db::open(&config::db_path()).expect("could not open the library database");
    if let Some(root) = &config.library_path {
        db.set_root(root).expect("could not initialise the library database");
    }
    let state = Arc::new(AppState {
        db: Mutex::new(db),
        config: Mutex::new(config),
        op_lock: Mutex::new(()),
        scanning: AtomicBool::new(false),
        watcher: Mutex::new(None),
        player: std::sync::OnceLock::new(),
    });

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(state)
        .setup(|app| {
            let handle = app.handle().clone();
            let player = player::AudioPlayer::start(move |status| {
                let _ = handle.emit("player", status);
            });
            let _ = app.state::<Arc<AppState>>().player.set(player);
            start_library(app.handle());
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_config,
            commands::set_library_path,
            commands::rescan,
            commands::status,
            commands::query_tracks,
            commands::get_tracks,
            commands::distinct_values,
            commands::get_art,
            commands::image_preview,
            commands::write_tags,
            commands::template_tokens,
            commands::preview_reorganize,
            commands::apply_reorganize,
            commands::save_template,
            commands::remove_template,
            commands::player_play,
            commands::player_toggle,
            commands::player_stop,
            commands::player_seek,
            commands::player_volume,
        ])
        .run(tauri::generate_context!())
        .expect("error while running MusicManager");
}
