import { Controller } from "@hotwired/stimulus"

// A play button on a song row or an album track.
//
// The player lives in the layout, outside the songs frame these buttons render
// in, so a plain click->player#play cannot reach it -- the event goes out on
// window instead.
//
// connect() reads the player's current state rather than waiting to be told:
// filtering, sorting or paging replaces the whole frame, so fifty of these
// reconnect at once and each has to work out for itself whether it is the one
// playing. Same shape as selection_controller's checkboxTargetConnected.
export default class extends Controller {
  static values = {
    songId: String, url: String, title: String, artist: String, art: String, duration: Number
  }

  connect() {
    this.sync()
  }

  play() {
    // The prefix is required: Stimulus would otherwise name the event after
    // this controller, and the player is listening for player:play.
    this.dispatch("play", {
      target: window,
      prefix: "player",
      detail: {
        songId: this.songIdValue,
        url: this.urlValue,
        title: this.titleValue,
        artist: this.artistValue,
        art: this.artValue,
        duration: this.durationValue
      }
    })
  }

  sync() {
    const player = document.getElementById("player")
    const playing = player?.dataset.songId === this.songIdValue &&
      player?.dataset.playing === "true"

    this.element.dataset.playing = playing
    this.element.setAttribute("aria-label", `${playing ? "Pause" : "Play"} ${this.titleValue}`)
  }
}
