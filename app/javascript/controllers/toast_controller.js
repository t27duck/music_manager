import { Controller } from "@hotwired/stimulus"

// Fades a toast out after a few seconds, or immediately when dismissed.
export default class extends Controller {
  static targets = ["root"]
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  dismiss() {
    clearTimeout(this.timeout)
    this.element.classList.add("opacity-0", "translate-y-1")
    this.element.addEventListener("transitionend", () => this.element.remove(), { once: true })
  }
}
