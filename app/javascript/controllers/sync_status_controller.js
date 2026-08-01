import { Controller } from "@hotwired/stimulus"

// Safety net for the live sync bar.
//
// Progress normally arrives over Action Cable, but a broadcast sent while the
// page is reloading (or while the browser is reconnecting) is simply lost, and
// the bar would then sit at its last known state forever. While a sync is
// running this polls the sync endpoint, which returns the very same Turbo
// Stream the broadcast does, so the page always converges on the truth.
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
