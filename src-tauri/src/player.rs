//! A minimal preview player, enough to check that a file sounds like what its tags say.
//!
//! Audio runs on a dedicated thread because the output stream can't move between threads.
//! The device is opened only while something is loaded and released on stop or at the end.

use std::fs::File;
use std::path::PathBuf;
use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::time::Duration;

use rodio::{Decoder, DeviceSinkBuilder, MixerDeviceSink, Player};
use serde::Serialize;

const TICK: Duration = Duration::from_millis(250);

enum Cmd {
    Play { id: i64, path: PathBuf, duration_ms: Option<u64> },
    Toggle,
    Stop,
    Seek(u64),
    Volume(f32),
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct PlayerStatus {
    pub track_id: Option<i64>,
    pub playing: bool,
    pub position_ms: u64,
    pub duration_ms: Option<u64>,
    pub error: Option<String>,
}

pub struct AudioPlayer {
    tx: Sender<Cmd>,
}

struct Loaded {
    // Field order matters: the player must drop before the device it plays on.
    player: Player,
    _sink: MixerDeviceSink,
}

struct Worker<F: FnMut(&PlayerStatus)> {
    loaded: Option<Loaded>,
    path: Option<PathBuf>,
    volume: f32,
    status: PlayerStatus,
    emit: F,
}

impl<F: FnMut(&PlayerStatus)> Worker<F> {
    fn open(&mut self, path: &PathBuf) -> Result<(), String> {
        self.loaded = None;
        let file = File::open(path).map_err(|e| format!("{}: {e}", path.display()))?;
        let decoder = Decoder::try_from(file).map_err(|e| format!("cannot decode {}: {e}", path.display()))?;
        let mut sink = DeviceSinkBuilder::open_default_sink().map_err(|e| format!("no audio output: {e}"))?;
        sink.log_on_drop(false);
        let player = Player::connect_new(sink.mixer());
        player.set_volume(self.volume);
        player.append(decoder);
        self.loaded = Some(Loaded { player, _sink: sink });
        Ok(())
    }

    fn handle(&mut self, cmd: Cmd) {
        self.status.error = None;
        match cmd {
            Cmd::Play { id, path, duration_ms } => {
                self.status = PlayerStatus { track_id: Some(id), duration_ms, ..Default::default() };
                if let Err(e) = self.open(&path) {
                    self.status.error = Some(e);
                }
                self.path = Some(path);
            }
            Cmd::Toggle => match &self.loaded {
                Some(l) if l.player.is_paused() => l.player.play(),
                Some(l) => l.player.pause(),
                // Finished or stopped: start the last track over.
                None => {
                    if let Some(path) = self.path.clone() {
                        if let Err(e) = self.open(&path) {
                            self.status.error = Some(e);
                        }
                    }
                }
            },
            Cmd::Stop => {
                self.loaded = None;
                self.status.position_ms = 0;
            }
            Cmd::Seek(ms) => {
                if self.loaded.is_none() {
                    if let Some(path) = self.path.clone() {
                        let _ = self.open(&path);
                        if let Some(l) = &self.loaded {
                            l.player.pause();
                        }
                    }
                }
                if let Some(l) = &self.loaded {
                    if let Err(e) = l.player.try_seek(Duration::from_millis(ms)) {
                        self.status.error = Some(format!("seek failed: {e}"));
                    }
                }
            }
            Cmd::Volume(v) => {
                self.volume = v.clamp(0.0, 1.0);
                if let Some(l) = &self.loaded {
                    l.player.set_volume(self.volume);
                }
            }
        }
    }

    /// Refresh the status from the player and emit it if anything changed.
    fn tick(&mut self, force: bool) {
        let before = self.status.clone();
        if let Some(l) = &self.loaded {
            if l.player.empty() {
                // Reached the end: release the device and rewind.
                self.loaded = None;
                self.status.playing = false;
                self.status.position_ms = 0;
            } else {
                self.status.playing = !l.player.is_paused();
                self.status.position_ms = l.player.get_pos().as_millis() as u64;
            }
        } else {
            self.status.playing = false;
        }
        if force || self.status != before {
            (self.emit)(&self.status);
        }
    }
}

impl AudioPlayer {
    /// Start the audio thread. `emit` receives every status change.
    pub fn start(emit: impl FnMut(&PlayerStatus) + Send + 'static) -> Self {
        let (tx, rx) = mpsc::channel::<Cmd>();
        std::thread::Builder::new()
            .name("audio".into())
            .spawn(move || {
                let mut w = Worker { loaded: None, path: None, volume: 0.8, status: PlayerStatus::default(), emit };
                loop {
                    match rx.recv_timeout(TICK) {
                        Ok(cmd) => {
                            w.handle(cmd);
                            w.tick(true);
                        }
                        Err(RecvTimeoutError::Timeout) => w.tick(false),
                        Err(RecvTimeoutError::Disconnected) => break,
                    }
                }
            })
            .expect("could not start the audio thread");
        Self { tx }
    }

    fn send(&self, cmd: Cmd) {
        let _ = self.tx.send(cmd);
    }

    pub fn play(&self, id: i64, path: PathBuf, duration_ms: Option<u64>) {
        self.send(Cmd::Play { id, path, duration_ms });
    }

    pub fn toggle(&self) {
        self.send(Cmd::Toggle);
    }

    pub fn stop(&self) {
        self.send(Cmd::Stop);
    }

    pub fn seek(&self, ms: u64) {
        self.send(Cmd::Seek(ms));
    }

    pub fn set_volume(&self, volume: f32) {
        self.send(Cmd::Volume(volume));
    }
}
