module ApplicationHelper
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
