//! Tauri commands invoked by the frontend.

use std::path::PathBuf;
use std::sync::Arc;

use base64::Engine;
use serde::Serialize;
use tauri::{AppHandle, Emitter, State};

use crate::config::Config;
use crate::db::{Query, Track};
use crate::reorganize::{self, ApplyResult, PlanItem};
use crate::scanner::file_stat;
use crate::tags::{self, Artwork, FieldEdit, TagEdits};
use crate::{progress_emitter, start_library, template, AppState};

type CmdResult<T> = Result<T, String>;

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

fn anyhow_err(e: anyhow::Error) -> String {
    format!("{e:#}")
}

fn require_root(state: &AppState) -> CmdResult<PathBuf> {
    state.root().ok_or_else(|| "no library folder is configured".to_string())
}

/// Run blocking work off the async runtime.
async fn blocking<T: Send + 'static>(f: impl FnOnce() -> CmdResult<T> + Send + 'static) -> CmdResult<T> {
    tauri::async_runtime::spawn_blocking(f).await.map_err(err)?
}

#[derive(Serialize)]
pub struct Status {
    library_path: Option<String>,
    scanning: bool,
    count: i64,
}

#[tauri::command]
pub fn get_config(state: State<'_, Arc<AppState>>) -> Config {
    state.config.lock().unwrap().clone()
}

#[tauri::command]
pub fn status(state: State<'_, Arc<AppState>>) -> CmdResult<Status> {
    Ok(Status {
        library_path: state.config.lock().unwrap().library_path.clone(),
        scanning: state.scanning.load(std::sync::atomic::Ordering::SeqCst),
        count: state.db.lock().unwrap().count().map_err(anyhow_err)?,
    })
}

#[tauri::command]
pub async fn set_library_path(app: AppHandle, state: State<'_, Arc<AppState>>, path: String) -> CmdResult<Config> {
    let state = state.inner().clone();
    let config = blocking(move || {
        let canonical = std::fs::canonicalize(&path).map_err(|e| format!("{path}: {e}"))?;
        if !canonical.is_dir() {
            return Err(format!("{path} is not a folder"));
        }
        let root = canonical.to_str().ok_or("library path must be valid UTF-8")?.to_string();
        // Stop watching before taking the lock: dropping the watcher waits for its handler,
        // which may itself be waiting on the lock.
        *state.watcher.lock().unwrap() = None;
        let _guard = state.op_lock.lock().unwrap();
        state.db.lock().unwrap().set_root(&root).map_err(anyhow_err)?;
        let mut config = state.config.lock().unwrap();
        config.library_path = Some(root);
        config.save().map_err(anyhow_err)?;
        Ok(config.clone())
    })
    .await?;
    let _ = app.emit("library-changed", ());
    start_library(&app);
    Ok(config)
}

#[tauri::command]
pub fn rescan(app: AppHandle) {
    start_library(&app);
}

#[tauri::command]
pub fn query_tracks(state: State<'_, Arc<AppState>>, query: Query) -> CmdResult<Vec<Track>> {
    state.db.lock().unwrap().query(&query).map_err(anyhow_err)
}

#[tauri::command]
pub fn get_tracks(state: State<'_, Arc<AppState>>, ids: Vec<i64>) -> CmdResult<Vec<Track>> {
    state.db.lock().unwrap().get(&ids).map_err(anyhow_err)
}

#[tauri::command]
pub fn distinct_values(state: State<'_, Arc<AppState>>, field: String) -> CmdResult<Vec<String>> {
    state.db.lock().unwrap().distinct(&field).map_err(anyhow_err)
}

/// Embedded cover of a track as a data: URL, or None.
#[tauri::command]
pub async fn get_art(state: State<'_, Arc<AppState>>, id: i64) -> CmdResult<Option<String>> {
    let state = state.inner().clone();
    blocking(move || {
        let root = require_root(&state)?;
        let Some(track) = state.db.lock().unwrap().get(&[id]).map_err(anyhow_err)?.pop() else {
            return Ok(None);
        };
        let art = tags::read_art(&root.join(&track.path)).map_err(anyhow_err)?;
        Ok(art.as_ref().map(data_url))
    })
    .await
}

fn data_url(art: &Artwork) -> String {
    format!("data:{};base64,{}", art.mime, base64::engine::general_purpose::STANDARD.encode(&art.data))
}

/// Preview an image file chosen as new album art.
#[tauri::command]
pub async fn image_preview(path: String) -> CmdResult<String> {
    blocking(move || Artwork::load(path.as_ref()).map(|a| data_url(&a)).map_err(anyhow_err)).await
}

#[derive(Serialize)]
pub struct WriteResult {
    updated: usize,
    failed: Vec<(String, String)>,
}

#[tauri::command]
pub async fn write_tags(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
    ids: Vec<i64>,
    edits: TagEdits,
) -> CmdResult<WriteResult> {
    if edits.is_empty() || ids.is_empty() {
        return Ok(WriteResult { updated: 0, failed: vec![] });
    }
    let state = state.inner().clone();
    let emit_app = app.clone();
    let result = blocking(move || {
        let root = require_root(&state)?;
        let art = match &edits.art {
            Some(FieldEdit::Set(path)) => Some(Artwork::load(path.as_ref()).map_err(anyhow_err)?),
            _ => None,
        };
        let _guard = state.op_lock.lock().unwrap();
        let tracks = state.db.lock().unwrap().get(&ids).map_err(anyhow_err)?;
        let mut progress = progress_emitter(&emit_app, "write");
        let mut result = WriteResult { updated: 0, failed: vec![] };
        let total = tracks.len();
        for (i, t) in tracks.iter().enumerate() {
            progress(i, total);
            let path = root.join(&t.path);
            match tags::write_tags(&path, &edits, art.as_ref()) {
                Ok(new_tags) => {
                    let (mtime, size) = file_stat(&path).unwrap_or_default();
                    if let Err(e) = state.db.lock().unwrap().update_tags(t.id, &new_tags, mtime, size) {
                        result.failed.push((t.path.clone(), anyhow_err(e)));
                    } else {
                        result.updated += 1;
                    }
                }
                Err(e) => result.failed.push((t.path.clone(), anyhow_err(e))),
            }
        }
        progress(total, total);
        Ok(result)
    })
    .await?;
    let _ = app.emit("library-changed", ());
    Ok(result)
}

#[derive(Serialize)]
pub struct TokenInfo {
    token: &'static str,
    description: &'static str,
}

#[tauri::command]
pub fn template_tokens() -> Vec<TokenInfo> {
    template::TOKENS.iter().map(|(token, description)| TokenInfo { token, description }).collect()
}

fn plan_for(state: &AppState, ids: &[i64], template: &str) -> CmdResult<(PathBuf, Vec<PlanItem>)> {
    template::validate(template)?;
    let root = require_root(state)?;
    let tracks = state.db.lock().unwrap().get(ids).map_err(anyhow_err)?;
    let items = reorganize::plan(&root, &tracks, template);
    Ok((root, items))
}

#[tauri::command]
pub async fn preview_reorganize(
    state: State<'_, Arc<AppState>>,
    ids: Vec<i64>,
    template: String,
) -> CmdResult<Vec<PlanItem>> {
    let state = state.inner().clone();
    blocking(move || plan_for(&state, &ids, &template).map(|(_, items)| items)).await
}

#[tauri::command]
pub async fn apply_reorganize(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
    ids: Vec<i64>,
    template: String,
) -> CmdResult<ApplyResult> {
    let state = state.inner().clone();
    let emit_app = app.clone();
    let result = blocking(move || {
        let _guard = state.op_lock.lock().unwrap();
        // Re-plan against the current state of the disk rather than trusting the preview.
        let (root, items) = plan_for(&state, &ids, &template)?;
        let result = reorganize::apply(&root, &state.db, &items, progress_emitter(&emit_app, "reorganize"));
        let mut config = state.config.lock().unwrap();
        config.remember_template(&template);
        let _ = config.save();
        Ok(result)
    })
    .await?;
    let _ = app.emit("library-changed", ());
    Ok(result)
}

#[tauri::command]
pub fn save_template(state: State<'_, Arc<AppState>>, template: String) -> CmdResult<Config> {
    template::validate(&template)?;
    let mut config = state.config.lock().unwrap();
    config.remember_template(&template);
    config.save().map_err(anyhow_err)?;
    Ok(config.clone())
}

#[tauri::command]
pub fn remove_template(state: State<'_, Arc<AppState>>, template: String) -> CmdResult<Config> {
    let mut config = state.config.lock().unwrap();
    config.templates.retain(|t| t != &template);
    config.save().map_err(anyhow_err)?;
    Ok(config.clone())
}

fn player(state: &AppState) -> CmdResult<&crate::player::AudioPlayer> {
    state.player.get().ok_or_else(|| "audio player is not running".to_string())
}

#[tauri::command]
pub fn player_play(state: State<'_, Arc<AppState>>, id: i64) -> CmdResult<()> {
    let root = require_root(&state)?;
    let track = state.db.lock().unwrap().get(&[id]).map_err(anyhow_err)?.pop().ok_or("track not found")?;
    player(&state)?.play(id, root.join(&track.path), track.duration_ms.map(|d| d as u64));
    Ok(())
}

#[tauri::command]
pub fn player_toggle(state: State<'_, Arc<AppState>>) -> CmdResult<()> {
    player(&state)?.toggle();
    Ok(())
}

#[tauri::command]
pub fn player_stop(state: State<'_, Arc<AppState>>) -> CmdResult<()> {
    player(&state)?.stop();
    Ok(())
}

#[tauri::command]
pub fn player_seek(state: State<'_, Arc<AppState>>, position_ms: u64) -> CmdResult<()> {
    player(&state)?.seek(position_ms);
    Ok(())
}

#[tauri::command]
pub fn player_volume(state: State<'_, Arc<AppState>>, volume: f32) -> CmdResult<()> {
    player(&state)?.set_volume(volume);
    Ok(())
}
