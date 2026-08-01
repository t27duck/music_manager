import { Controller } from "@hotwired/stimulus"

// Live preview for the file-organization template.
//
// The preview is a GET of the #new action loaded into its own frame, kept
// deliberately separate from the surrounding form: that form POSTs to #create
// and actually moves files, so submitting it on every keystroke would re-file
// the user's library as they typed.
export default class extends Controller {
  static targets = ["input", "frame"]
  static values = { url: String, delay: { type: Number, default: 300 } }

  disconnect() {
    clearTimeout(this.timeout)
  }

  preview() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.load(), this.delayValue)
  }

  load() {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("template", this.inputTarget.value)

    this.frameTarget.src = url.toString()
  }
}
