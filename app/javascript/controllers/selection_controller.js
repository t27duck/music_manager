import { Controller } from "@hotwired/stimulus"

// Multi-select for the song list, spanning pages and filters.
//
// The selection is not held in a form: the table contains per-cell inline-edit
// forms, and a form wrapping them would be nested markup the browser discards.
// Nor is it held in the checkboxes any more, which is what limited it to one
// page -- every filter, sort or page change replaces the whole `songs` frame
// and took the ticks with it. This controller sits *outside* that frame, so it
// survives each re-render, and re-applies its ids to checkboxes as they
// reconnect.
//
// It is deliberately in-memory only. A full page load clears it, which is
// correct: the only thing that reloads the page on its own is a finished sync
// or organize, and that is exactly when the library has changed underneath the
// selection and "1,204 selected" would have become a lie.
//
// Two modes. Normally the ids are explicit. "Select all matching" instead sends
// the current filter and lets the server resolve it, because the whole point is
// acting on more songs than the browser has ever seen -- and because a few
// thousand ids do not fit in a URL.
export default class extends Controller {
  static targets = ["checkbox", "toggleAll", "actions", "count", "state", "banner"]
  static values = {
    frame: { type: String, default: "modal" },
    // Manual ids ride in the modal's query string, so they have a ceiling.
    // Past it, all-matching is the answer rather than a longer URL.
    limit: { type: Number, default: 500 }
  }

  initialize() {
    this.selected = new Set()
    this.allMatching = false
  }

  connect() {
    this.refresh()
  }

  // Stimulus calls this for every checkbox entering the DOM, including the
  // fifty that arrive with each frame swap -- which is how the selection
  // reappears after paging, filtering or sorting.
  checkboxTargetConnected(box) {
    box.checked = this.allMatching || this.selected.has(box.value)
    this.scheduleRefresh()
  }

  checkboxTargetDisconnected() {
    this.scheduleRefresh()
  }

  // A frame swap reconnects every checkbox at once; coalesce so the toolbar is
  // recomputed once rather than once per row.
  scheduleRefresh() {
    if (this.refreshQueued) return

    this.refreshQueued = true
    queueMicrotask(() => {
      this.refreshQueued = false
      this.refresh()
    })
  }

  toggle(event) {
    const box = event.target

    // Any individual tick is a narrower intent than "everything matching", so
    // it drops back to explicit ids, seeded from what is currently ticked.
    this.exitAllMatching()

    if (box.checked) {
      this.selected.add(box.value)
    } else {
      this.selected.delete(box.value)
    }

    this.refresh()
  }

  toggleAll() {
    this.exitAllMatching()
    const checked = this.toggleAllTarget.checked

    this.checkboxTargets.forEach((box) => {
      box.checked = checked
      if (checked) {
        this.selected.add(box.value)
      } else {
        this.selected.delete(box.value)
      }
    })

    this.refresh()
  }

  // Escalates from "every song on this page" to "every song matching the
  // filter", which may be far more than has ever been rendered.
  selectAllMatching() {
    this.allMatching = true
    this.checkboxTargets.forEach((box) => { box.checked = true })
    this.refresh()
  }

  clear() {
    this.allMatching = false
    this.selected.clear()
    this.checkboxTargets.forEach((box) => { box.checked = false })
    this.refresh()
  }

  refresh() {
    if (this.hasActionsTarget) this.actionsTarget.hidden = this.selectionCount === 0
    if (this.hasCountTarget) this.countTarget.textContent = this.countLabel

    if (this.hasToggleAllTarget) {
      const onPage = this.checkboxTargets.length
      const ticked = this.checkboxTargets.filter((box) => box.checked).length

      this.toggleAllTarget.checked = onPage > 0 && ticked === onPage
      this.toggleAllTarget.indeterminate = ticked > 0 && ticked < onPage
    }

    this.refreshBanner()
  }

  // The offer to widen the selection appears only once the whole page is
  // ticked, and only when there is more to widen to: two deliberate clicks
  // before anything can touch the entire library.
  refreshBanner() {
    if (!this.hasBannerTarget) return

    const onPage = this.checkboxTargets.length
    const wholePageTicked = onPage > 0 && this.checkboxTargets.every((box) => box.checked)

    this.bannerTarget.hidden =
      this.allMatching || !wholePageTicked || this.matchingCount <= onPage
  }

  edit() {
    this.openModal(this.stateTarget.dataset.bulkUrl)
  }

  organize() {
    this.openModal(this.stateTarget.dataset.organizeUrl)
  }

  // The URLs come off a target *inside* the frame, so they carry whatever
  // filter is currently rendered. Held on this controller they would go stale
  // the moment a search re-rendered the list beneath it.
  openModal(path) {
    const url = new URL(path, window.location.origin)

    if (this.allMatching) {
      // The filter is already baked into `path` by the server; this only says
      // "resolve it", rather than listing ids the browser does not have.
      url.searchParams.set("select_all", "1")
    } else {
      this.selectedIds.forEach((id) => url.searchParams.append("song_ids[]", id))
    }

    document.getElementById(this.frameValue).src = url.toString()
  }

  exitAllMatching() {
    if (!this.allMatching) return

    this.allMatching = false
    // Keep what is visibly ticked, so leaving all-matching does not silently
    // empty the selection.
    this.selected = new Set(
      this.checkboxTargets.filter((box) => box.checked).map((box) => box.value)
    )
  }

  get selectedIds() {
    return Array.from(this.selected).slice(0, this.limitValue)
  }

  get matchingCount() {
    return this.hasStateTarget ? Number(this.stateTarget.dataset.matchingCount || 0) : 0
  }

  get selectionCount() {
    return this.allMatching ? this.matchingCount : this.selected.size
  }

  get countLabel() {
    if (this.allMatching) return `All ${this.matchingCount}`
    if (this.selected.size > this.limitValue) return `${this.limitValue} of ${this.selected.size}`

    return String(this.selected.size)
  }
}
