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
