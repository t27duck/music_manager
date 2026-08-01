ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "tmpdir"

Dir[Rails.root.join("test/support/**/*.rb")].each { |file| require file }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    #
    # Note: there is deliberately no songs.yml. A Song is only meaningful next to
    # a real MP3 on disk, so tests build them with LibraryTestHelper#create_test_song
    # inside a per-test temp directory instead.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
