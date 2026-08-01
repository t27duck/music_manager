import { Controller } from "@hotwired/stimulus"

// Drives a <dialog> rendered into the layout's "modal" turbo frame.
//
// Opening is automatic: the dialog only exists once the frame has loaded it.
// Closing empties the frame, so the same link can open it again afterwards.
export default class extends Controller {
  connect() {
    if (!this.element.open) this.element.showModal()
  }

  close() {
    this.element.close()
  }

  // Clicking the backdrop reports coordinates outside the dialog's own box.
  clickOutside(event) {
    if (event.target !== this.element) return

    const box = this.element.getBoundingClientRect()
    const inside =
      event.clientX >= box.left && event.clientX <= box.right &&
      event.clientY >= box.top && event.clientY <= box.bottom

    if (!inside) this.close()
  }

  // Fires for every close, including Escape, so the frame never keeps a
  // dismissed dialog around.
  dismiss() {
    const frame = this.element.closest("turbo-frame")

    if (frame) {
      frame.innerHTML = ""
      frame.removeAttribute("src")
    } else {
      this.element.remove()
    }
  }
}
