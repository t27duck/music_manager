module ApplicationHelper
  # Navigation link that highlights itself when it points at the current page.
  def nav_link_to(name, path, **options)
    active = current_page?(path)
    classes = [
      "rounded-md px-3 py-1.5 text-sm font-medium transition",
      active ? "bg-surface-800 text-surface-100" : "text-surface-400 hover:bg-surface-850 hover:text-surface-100"
    ]

    link_to name, path, **options, class: classes, aria: { current: ("page" if active) }
  end

  # Colour-coded progress text: blue while running, green on success, red on
  # failure. Takes anything that includes ProgressStatus, so it serves both a
  # live status and a stored SyncRun.
  def progress_color(status)
    if status.failed? then "text-red-400"
    elsif status.completed? then "text-emerald-400"
    else "text-accent-400"
    end
  end

  def progress_bar_color(status)
    if status.failed? then "bg-red-500"
    elsif status.completed? then "bg-emerald-500"
    else "bg-accent-500"
    end
  end

  # Border/background/text colours for a flash level.
  def toast_classes(level)
    case level.to_s
    when "alert", "error"
      "border-red-800 bg-red-950 text-red-100"
    when "warning"
      "border-amber-800 bg-amber-950 text-amber-100"
    else
      "border-accent-700 bg-surface-850 text-surface-100"
    end
  end
end
