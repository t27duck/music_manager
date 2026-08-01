import { Controller } from "@hotwired/stimulus"

// Double-click to edit a cell in place.
//
// Mounted twice per cell: once on the read-only view (which knows how to fetch
// the input) and once on the form (which knows how to save or discard it).
// Both drive the same turbo frame.
export default class extends Controller {
  static values = { url: String, cancelUrl: String }

  // Read-only view: load the input into this cell.
  edit() {
    this.frame.src = this.urlValue
  }

  // Form: Escape discards, restoring the read-only cell.
  cancel(event) {
    event.preventDefault()
    this.cancelled = true
    this.frame.src = this.cancelUrlValue
  }

  // Form: blur commits, the way a spreadsheet does. Guarded so that the blur
  // fired by Escape tearing the input down does not save what was discarded.
  save() {
    if (this.cancelled) return

    this.element.requestSubmit()
  }

  get frame() {
    return this.element.closest("turbo-frame")
  }
}
