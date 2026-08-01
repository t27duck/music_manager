import { Controller } from "@hotwired/stimulus"

// Submits a filter form as the user types, without a Search button.
//
// Typing would fire one request per keystroke otherwise, so submissions are
// debounced; select changes submit immediately since they are discrete.
//
// The clear and reset controls are shown and hidden here rather than in the
// template: only the results frame is re-rendered on submit, so anything in
// this form that depended on a server round trip would never update.
export default class extends Controller {
  static targets = ["query", "clear", "reset"]
  static values = { delay: { type: Number, default: 300 } }

  connect() {
    this.toggleControls()
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  // Debounced: for text inputs.
  search() {
    this.toggleControls()
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.submit(), this.delayValue)
  }

  // Immediate: for selects and other discrete controls.
  submit() {
    this.toggleControls()
    clearTimeout(this.timeout)
    this.element.requestSubmit()
  }

  // Empties every field and reloads the unfiltered list.
  reset(event) {
    event.preventDefault()
    this.fields.forEach((field) => { field.value = "" })
    this.submit()
  }

  // Clears just the global search box.
  clearQuery() {
    this.queryTarget.value = ""
    this.queryTarget.focus()
    this.submit()
  }

  toggleControls() {
    if (this.hasClearTarget) {
      this.clearTarget.hidden = this.queryTarget.value.trim() === ""
    }

    if (this.hasResetTarget) {
      this.resetTarget.hidden = !this.fields.some((field) => field.value.trim() !== "")
    }
  }

  get fields() {
    return Array.from(this.element.querySelectorAll("input[type=search], input[type=text], select"))
  }
}
