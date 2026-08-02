import { Controller } from "@hotwired/stimulus"

// The playback bar pinned to the bottom of every page.
//
// Its element carries data-turbo-permanent, so Turbo *moves* the node into each
// new page rather than re-rendering it: the <audio> element, its buffer and its
// currentTime all survive a visit. This controller does not survive -- the move
// is a real DOM mutation, so Stimulus disconnects and reconnects it on every
// Turbo Drive visit and every turbo_stream.refresh a finished sync broadcasts.
//
// Everything therefore lives in the DOM. connect() only reads; it must never
// touch src, currentTime or hidden, or navigating would restart the song. For
// the same reason there is no timer and no listener added here: the media
// events are bound with data-action on the <audio> element itself, so Stimulus
// unbinds them for free and there is nothing left to leak.
//
// One track at a time, by design. Playing a song replaces whatever was playing;
// nothing auto-advances when it ends.
export default class extends Controller {
  static targets = ["audio", "cover", "title", "artist", "toggle", "seek", "elapsed", "duration"]

  connect() {
    this.render()
  }

  // Started from anywhere on the page: the play buttons live inside the songs
  // frame, outside this element, so they dispatch on window instead.
  play({ detail: { songId, url, title, artist, art, duration } }) {
    if (this.element.dataset.songId === String(songId)) return this.toggle()

    this.element.dataset.songId = songId
    this.titleTarget.textContent = title
    this.artistTarget.textContent = artist || "Unknown artist"
    this.coverTarget.src = art || ""
    this.coverTarget.hidden = !art
    this.seekTarget.max = duration || 0
    this.seekTarget.value = 0
    this.durationTarget.textContent = this.formatted(duration)
    this.element.hidden = false
    document.documentElement.classList.add("player-open")

    this.audioTarget.src = url
    this.start()
  }

  toggle() {
    this.audioTarget.paused ? this.start() : this.audioTarget.pause()
  }

  start() {
    // A rejected play() -- an autoplay policy, or a file that will not decode --
    // must not leave the bar claiming to be playing.
    this.audioTarget.play().then(() => this.render()).catch(() => this.render())
  }

  close() {
    this.audioTarget.pause()
    // Never src = "": an empty src makes the browser re-request the current page
    // URL as media.
    this.audioTarget.removeAttribute("src")
    this.audioTarget.load()

    this.element.hidden = true
    delete this.element.dataset.songId
    document.documentElement.classList.remove("player-open")
    this.render()
  }

  // Bound to timeupdate. Skipped while the user is dragging, so the handle does
  // not fight them.
  tick() {
    if (this.scrubbing) return

    this.seekTarget.value = this.audioTarget.currentTime
    this.elapsedTarget.textContent = this.formatted(this.audioTarget.currentTime)
  }

  scrubStart() {
    this.scrubbing = true
  }

  scrubEnd() {
    this.scrubbing = false
    this.audioTarget.currentTime = Number(this.seekTarget.value)
  }

  // The duration the file actually reports, which is more trustworthy than the
  // one read from its tags.
  durationLoaded() {
    const { duration } = this.audioTarget

    if (!Number.isFinite(duration)) return

    this.seekTarget.max = duration
    this.durationTarget.textContent = this.formatted(duration)
  }

  ended() {
    this.render()
  }

  // The song was deleted or moved out from under us: the next range request
  // 404s and the element fires error.
  failed() {
    this.titleTarget.textContent = "This song is no longer available"
    this.artistTarget.textContent = ""
    this.seekTarget.hidden = true
    this.render()
  }

  // Publishes the state every play button reads, and does it on the element so
  // a button that connects later can catch up without having heard the event.
  render() {
    const playing = !this.audioTarget.paused && this.element.dataset.songId

    this.element.dataset.playing = Boolean(playing)
    this.toggleTarget.textContent = playing ? "Pause" : "Play"
    this.toggleTarget.setAttribute("aria-label", playing ? "Pause" : "Play")

    this.dispatch("changed", { target: window, prefix: "player" })
  }

  // Mirrors SongsHelper#formatted_duration. Unavoidably duplicated: the running
  // time cannot come from the server.
  formatted(seconds) {
    if (!Number.isFinite(seconds)) return "—"

    const whole = Math.floor(seconds)
    const minutes = Math.floor(whole / 60)

    return `${minutes}:${String(whole % 60).padStart(2, "0")}`
  }
}
