require "test_helper"

# Cheap smoke test: proves the app boots with the mp3info gem, the Action Cable
# scaffolding, and the import map pins in place. Import map typos otherwise stay
# silent until a browser loads the page.
class HealthCheckTest < ActionDispatch::IntegrationTest
  test "responds to the health check" do
    get "/up"

    assert_response :success
  end

  test "every import map pin resolves to a real asset" do
    Rails.application.importmap.packages.each_value do |package|
      assert Rails.application.assets.load_path.find(package.path),
        "Import map pins #{package.name.inspect} to #{package.path.inspect}, which does not resolve"
    end
  end
end
