import { Controller } from "@hotwired/stimulus"

// Fades an element out after a delay. Used for the completed sync bar, which
// should not linger once there is nothing left to report.
export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    this.timeout = setTimeout(() => this.hide(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  hide() {
    this.element.classList.add("transition", "duration-500", "opacity-0")
    this.element.addEventListener("transitionend", () => this.element.remove(), { once: true })
  }
}
