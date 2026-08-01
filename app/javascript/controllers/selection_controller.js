import { Controller } from "@hotwired/stimulus"

// Multi-select for the song list.
//
// The selection is not held in a form: the table contains per-cell inline-edit
// forms, and a form wrapping them would be nested markup the browser discards.
// Instead the ids are collected here and appended to the bulk-edit URL, which
// is loaded into the modal frame.
export default class extends Controller {
  static targets = ["checkbox", "toggleAll", "actions", "count"]
  static values = {
    url: String,
    organizeUrl: String,
    frame: { type: String, default: "modal" }
  }

  connect() {
    this.refresh()
  }

  toggleAll() {
    this.checkboxTargets.forEach((box) => { box.checked = this.toggleAllTarget.checked })
    this.refresh()
  }

  clear() {
    this.checkboxTargets.forEach((box) => { box.checked = false })
    this.refresh()
  }

  // Called whenever an individual checkbox changes.
  refresh() {
    const selected = this.selectedIds

    if (this.hasActionsTarget) this.actionsTarget.hidden = selected.length === 0
    if (this.hasCountTarget) this.countTarget.textContent = selected.length

    if (this.hasToggleAllTarget) {
      const all = this.checkboxTargets.length
      this.toggleAllTarget.checked = all > 0 && selected.length === all
      this.toggleAllTarget.indeterminate = selected.length > 0 && selected.length < all
    }
  }

  edit() {
    this.openModal(this.urlValue)
  }

  organize() {
    this.openModal(this.organizeUrlValue)
  }

  openModal(path) {
    const url = new URL(path, window.location.origin)
    this.selectedIds.forEach((id) => url.searchParams.append("song_ids[]", id))

    document.getElementById(this.frameValue).src = url.toString()
  }

  get selectedIds() {
    return this.checkboxTargets.filter((box) => box.checked).map((box) => box.value)
  }
}
