//! Manual check of the preview player: `cargo run --example play -- file.mp3`
use std::sync::{Arc, Mutex};
use std::time::Duration;

use music_manager_lib::player::AudioPlayer;

fn main() {
    let path = std::env::args().nth(1).expect("usage: play <file.mp3>");
    let log = Arc::new(Mutex::new(Vec::new()));
    let sink = log.clone();
    let player = AudioPlayer::start(move |s| sink.lock().unwrap().push(s.clone()));
    let wait = |ms| std::thread::sleep(Duration::from_millis(ms));
    let last = || log.lock().unwrap().last().cloned().unwrap();

    player.set_volume(0.2);
    player.play(1, path.into(), Some(60_000));
    wait(1200);
    println!("after 1.2s: {:?}", last());
    player.seek(30_000);
    wait(600);
    println!("after seek to 30s: {:?}", last());
    player.toggle();
    wait(600);
    let paused = last();
    wait(600);
    println!("paused: {:?} (position held: {})", last(), paused.position_ms == last().position_ms);
    player.stop();
    wait(400);
    println!("stopped: {:?}", last());
    player.play(2, "/nonexistent.mp3".into(), None);
    wait(400);
    println!("missing file: {:?}", last());
}
