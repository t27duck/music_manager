//! Show a file in the desktop's file manager.

use std::path::Path;

use anyhow::{Context, Result};

/// Opens the file manager at the file's folder with the file selected where the file manager
/// supports it (the freedesktop `FileManager1` D-Bus interface: Nautilus, Dolphin, Nemo, Thunar,
/// …), otherwise just opens the folder.
#[cfg(target_os = "linux")]
pub fn reveal(path: &Path) -> Result<()> {
    use std::time::Duration;

    let show_items = || -> Result<(), dbus::Error> {
        let conn = dbus::blocking::Connection::new_session()?;
        let proxy =
            conn.with_proxy("org.freedesktop.FileManager1", "/org/freedesktop/FileManager1", Duration::from_secs(5));
        proxy.method_call("org.freedesktop.FileManager1", "ShowItems", (vec![file_uri(path)], ""))
    };
    if show_items().is_ok() {
        return Ok(());
    }
    let dir = path.parent().context("file has no folder")?;
    let mut child = std::process::Command::new("xdg-open")
        .arg(dir)
        .spawn()
        .context("couldn't open the folder (is xdg-open installed?)")?;
    // Reap it so it doesn't linger as a zombie.
    std::thread::spawn(move || child.wait());
    Ok(())
}

#[cfg(target_os = "macos")]
pub fn reveal(path: &Path) -> Result<()> {
    let status = std::process::Command::new("open").arg("-R").arg(path).status().context("couldn't run open")?;
    anyhow::ensure!(status.success(), "open -R failed");
    Ok(())
}

/// Opens Explorer at the file's folder with the file selected.
#[cfg(windows)]
pub fn reveal(path: &Path) -> Result<()> {
    use std::os::windows::process::CommandExt;

    // Explorer needs backslashes, and parses `/select,"<path>"` itself rather than by the usual
    // quoting rules, so the argument is passed raw.
    let path: std::path::PathBuf = path.components().collect();
    let mut child = std::process::Command::new("explorer")
        .raw_arg(format!("/select,\"{}\"", path.display()))
        .spawn()
        .context("couldn't run explorer")?;
    // Explorer exits with 1 even when it worked, so only reap it.
    std::thread::spawn(move || child.wait());
    Ok(())
}

#[cfg(not(any(target_os = "linux", target_os = "macos", windows)))]
pub fn reveal(_path: &Path) -> Result<()> {
    anyhow::bail!("showing files isn't supported on this platform")
}

/// `file://` URI for an absolute path, percent-encoding everything but unreserved characters.
#[cfg(target_os = "linux")]
fn file_uri(path: &Path) -> String {
    use std::os::unix::ffi::OsStrExt;

    let mut uri = String::from("file://");
    for &b in path.as_os_str().as_bytes() {
        if b.is_ascii_alphanumeric() || b"/-._~".contains(&b) {
            uri.push(b as char);
        } else {
            uri.push_str(&format!("%{b:02X}"));
        }
    }
    uri
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::*;

    #[test]
    fn file_uri_escapes_reserved_and_non_ascii() {
        assert_eq!(
            file_uri(Path::new("/music/AC/DC/Back in Black #1 (100%).mp3")),
            "file:///music/AC/DC/Back%20in%20Black%20%231%20%28100%25%29.mp3"
        );
        assert_eq!(file_uri(Path::new("/music/Björk/Jóga.mp3")), "file:///music/Bj%C3%B6rk/J%C3%B3ga.mp3");
    }
}
