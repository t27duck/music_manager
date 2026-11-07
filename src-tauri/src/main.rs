// Prevents an additional console window on Windows in release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    #[cfg(all(unix, not(debug_assertions)))]
    detach_from_terminal();

    music_manager_lib::run()
}

/// Passed to the relaunched copy, and usable by hand to keep the app attached to the terminal
/// (to see its log output, say).
#[cfg(all(unix, not(debug_assertions)))]
const FOREGROUND_FLAG: &str = "--foreground";

/// When started from an interactive shell, relaunch in the background and exit so the shell gets
/// its prompt back. The copy runs in its own process group with no terminal on its stdio, so
/// Ctrl+C in the terminal or closing it doesn't take the app down. Desktop launchers don't give us
/// a terminal, so this is a no-op there; if the relaunch fails, carry on in the foreground.
#[cfg(all(unix, not(debug_assertions)))]
fn detach_from_terminal() {
    use std::io::IsTerminal;
    use std::os::unix::process::CommandExt;
    use std::process::{Command, Stdio};

    let mut args = std::env::args_os().skip(1).collect::<Vec<_>>();
    if args.iter().any(|a| a == FOREGROUND_FLAG) || !std::io::stdin().is_terminal() {
        return;
    }
    let Ok(exe) = std::env::current_exe() else { return };
    args.push(FOREGROUND_FLAG.into());
    let spawned = Command::new(exe)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn();
    if spawned.is_ok() {
        std::process::exit(0);
    }
}
