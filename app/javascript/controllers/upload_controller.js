import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// Drag-and-drop uploading.
//
// The browser owns the counters: it holds the file list and gets per-file XHR
// progress, so a server round trip would only lag behind. The log lines come
// over Action Cable instead, so what is reported is what the server actually
// did with each file.
export default class extends Controller {
  static targets = [
    "dropzone", "input", "folderInput", "progress", "bar", "counter", "log", "summary", "label"
  ]
  static values = { url: String }

  connect() {
    this.uploadId = this.randomId()

    this.subscription = consumer.subscriptions.create(
      { channel: "UploadChannel", upload_id: this.uploadId },
      { received: (data) => this.appendLog(data) }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
  }

  // --- Drag and drop -------------------------------------------------------

  dragOver(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("border-accent-500", "bg-surface-850")
  }

  dragLeave(event) {
    event.preventDefault()
    this.resetDropzone()
  }

  async drop(event) {
    event.preventDefault()
    this.resetDropzone()

    const files = await this.collect(event.dataTransfer.items)
    this.upload(files)
  }

  // --- Click to browse -----------------------------------------------------

  browseFiles() {
    this.inputTarget.click()
  }

  browseFolder() {
    this.folderInputTarget.click()
  }

  chosen(event) {
    const files = Array.from(event.target.files).map((file) => ({
      file,
      relativePath: file.webkitRelativePath || file.name
    }))

    event.target.value = ""
    this.upload(files)
  }

  // --- Walking a dropped directory tree ------------------------------------

  async collect(items) {
    const entries = Array.from(items)
      .map((item) => item.webkitGetAsEntry?.())
      .filter(Boolean)

    const files = []
    for (const entry of entries) await this.walk(entry, "", files)
    return files
  }

  async walk(entry, prefix, files) {
    if (entry.isFile) {
      const file = await new Promise((resolve, reject) => entry.file(resolve, reject))
      files.push({ file, relativePath: prefix + file.name })
      return
    }

    if (!entry.isDirectory) return

    // readEntries returns at most 100 at a time, so keep reading until it stops.
    const reader = entry.createReader()
    let batch
    do {
      batch = await new Promise((resolve, reject) => reader.readEntries(resolve, reject))
      for (const child of batch) await this.walk(child, `${prefix}${entry.name}/`, files)
    } while (batch.length > 0)
  }

  // --- Uploading -----------------------------------------------------------

  async upload(files) {
    if (files.length === 0) return

    this.total = files.length
    this.completed = 0
    this.succeeded = 0
    this.failed = 0

    this.progressTarget.hidden = false
    this.summaryTarget.hidden = true
    this.labelTarget.textContent = "Uploading…"
    this.labelTarget.classList.replace("text-emerald-400", "text-accent-400")
    this.updateCounter(0)

    // One at a time: the progress bar stays meaningful and the server is not
    // asked to parse a hundred MP3s at once.
    for (const item of files) {
      await this.send(item)
      this.completed += 1
      this.updateCounter(0)
    }

    this.showSummary()
  }

  send({ file, relativePath }) {
    return new Promise((resolve) => {
      const body = new FormData()
      body.append("file", file)
      body.append("relative_path", relativePath)
      body.append("upload_id", this.uploadId)

      const request = new XMLHttpRequest()
      request.open("POST", this.urlValue)
      request.setRequestHeader("X-CSRF-Token", this.csrfToken)
      request.setRequestHeader("Accept", "application/json")

      request.upload.addEventListener("progress", (event) => {
        if (event.lengthComputable) this.updateCounter(event.loaded / event.total)
      })

      request.addEventListener("loadend", () => {
        if (request.status >= 200 && request.status < 300) {
          this.succeeded += 1
        } else {
          this.failed += 1
          // A transport failure never reaches the channel, so say so here.
          if (request.status === 0) {
            this.appendLog({ status: "error", filename: relativePath, message: "Upload failed" })
          }
        }
        resolve()
      })

      request.send(body)
    })
  }

  // --- Reporting -----------------------------------------------------------

  // fraction is how far through the file currently in flight we are, so the bar
  // moves smoothly rather than jumping once per file.
  updateCounter(fraction) {
    const done = Math.min(this.completed + fraction, this.total)

    this.barTarget.style.width = `${(done / this.total) * 100}%`
    this.counterTarget.textContent = `${this.completed} / ${this.total}`
  }

  appendLog({ status, filename, message }) {
    const line = document.createElement("p")
    line.className = status === "error" ? "text-red-400" : "text-surface-300"
    line.textContent = `${filename} — ${message}`

    this.logTarget.appendChild(line)
    this.logTarget.scrollTop = this.logTarget.scrollHeight
  }

  showSummary() {
    const parts = [`${this.succeeded} of ${this.total} uploaded`]
    if (this.failed > 0) parts.push(`${this.failed} failed`)

    this.labelTarget.textContent = "Upload complete"
    this.labelTarget.classList.replace("text-accent-400", "text-emerald-400")

    this.summaryTarget.textContent = `${parts.join(", ")}.`
    this.summaryTarget.hidden = false
  }

  resetDropzone() {
    this.dropzoneTarget.classList.remove("border-accent-500", "bg-surface-850")
  }

  get csrfToken() {
    return document.querySelector("meta[name=csrf-token]")?.content
  }

  // Scopes this page's broadcast stream. Deliberately not crypto.randomUUID():
  // that needs a secure context, and this app is normally served over plain
  // HTTP on a hostname other than localhost, where it is simply undefined.
  // getRandomValues carries no such restriction.
  randomId() {
    const bytes = new Uint8Array(16)

    if (window.crypto?.getRandomValues) {
      window.crypto.getRandomValues(bytes)
    } else {
      for (let i = 0; i < bytes.length; i++) bytes[i] = Math.floor(Math.random() * 256)
    }

    return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("")
  }
}
