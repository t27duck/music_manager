require "test_helper"

# Almost every interaction in this app finishes asynchronously: a background job
# runs, broadcasts over Action Cable, and the page updates itself. Capybara's
# two second default is not enough headroom for that chain under load, and
# raising it here is better than scattering `wait:` through the tests.
Capybara.default_max_wait_time = 10

# Resolve form controls by their accessible name, so `aria-label` counts. Table
# checkboxes are labelled that way on purpose -- a visible label per row would
# be noise -- and tests should find them the way a screen reader would.
Capybara.enable_aria_label = true

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # System tests need jobs to really run, in a background thread, the way they
  # do in development -- a sync must be able to finish *after* the request that
  # started it, so that seeing "Sync complete" in the browser proves the Action
  # Cable broadcast arrived rather than the POST response having said so.
  #
  # Only system tests: the rest of the suite keeps the :test adapter so it can
  # assert on what was enqueued.
  setup { ActiveJob::Base.queue_adapter = :async }
  teardown { ActiveJob::Base.queue_adapter = :test }

  if ENV["CAPYBARA_SERVER_PORT"]
    served_by host: "rails-app", port: ENV["CAPYBARA_SERVER_PORT"]

    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ], options: {
      browser: :remote,
      url: "http://#{ENV["SELENIUM_HOST"]}:4444"
    }
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
  end
end
