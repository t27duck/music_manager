mod commands;
mod config;
pub mod db;
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
    let Some(root) = state.root() else { return };
    if state.scanning.swap(true, Ordering::SeqCst) {
        return;
    }
    let app = app.clone();
    std::thread::spawn(move || {
        *state.watcher.lock().unwrap() = None;
        let result = {
            let _guard = state.op_lock.lock().unwrap();
            let _ = app.emit("scan-started", ());
            scanner::full_scan(&state.db, &root, progress_emitter(&app, "scan"))
        };
        state.scanning.store(false, Ordering::SeqCst);
        match result {
            Ok(summary) => {
                let _ = app.emit("scan-finished", summary);
            }
            Err(e) => {
                let _ = app.emit("scan-failed", format!("{e:#}"));
            }
        }
        match watcher::LibraryWatcher::start(app.clone(), state.clone(), root) {
            Ok(w) => *state.watcher.lock().unwrap() = Some(w),
            Err(e) => {
                let _ = app.emit("scan-failed", format!("could not watch library: {e:#}"));
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
    });

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(state)
        .setup(|app| {
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
            commands::write_tags,
            commands::template_tokens,
            commands::preview_reorganize,
            commands::apply_reorganize,
            commands::save_template,
            commands::remove_template,
        ])
        .run(tauri::generate_context!())
        .expect("error while running MusicManager");
}
