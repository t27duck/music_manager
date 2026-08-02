import { Controller } from "@hotwired/stimulus"

// Safety net for the live progress bar.
//
// Progress normally arrives over Action Cable, but a broadcast sent while the
// page is reloading (or while the browser is reconnecting) is simply lost, and
// the bar would then sit at its last known state forever. While an operation is
// running this polls the progress endpoint, which returns the very same Turbo
// Stream the broadcast does, so the page always converges on the truth.
//
// It cancels itself: each response replaces this element, so the controller
// reconnects with a fresh `running` value and stops once that value is false.
export default class extends Controller {
  static values = {
    running: Boolean,
    url: String,
    interval: { type: Number, default: 3000 }
  }

  connect() {
    if (!this.runningValue) return

    this.poll = setInterval(() => this.refresh(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.poll)
  }

  async refresh() {
    const response = await fetch(this.urlValue, {
      headers: { Accept: "text/vnd.turbo-stream.html" }
    })

    if (!response.ok) return

    window.Turbo.renderStreamMessage(await response.text())
  }
}
