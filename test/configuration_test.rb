require "test_helper"

class ConfigurationTest < ActiveSupport::TestCase
  setup do
    @original_library_root = Configuration.library_root
    @original_env = ENV["LIBRARY_ROOT"]
  end

  teardown do
    ENV["LIBRARY_ROOT"] = @original_env
    Configuration.instance_variable_set(:@library_root, @original_library_root)
  end

  test "defaults to test/library in the test environment" do
    Configuration.instance_variable_set(:@library_root, nil)

    assert_equal Rails.root.join("test/library").to_s, Configuration.library_root
  end

  test "LIBRARY_ROOT overrides the default" do
    Configuration.instance_variable_set(:@library_root, nil)
    ENV["LIBRARY_ROOT"] = "/somewhere/else"

    assert_equal "/somewhere/else", Configuration.library_root
  end

  test "stubbing the root with instance_variable_set round-trips" do
    Configuration.instance_variable_set(:@library_root, "/tmp/stubbed")
    assert_equal "/tmp/stubbed", Configuration.library_root

    Configuration.instance_variable_set(:@library_root, @original_library_root)
    assert_equal @original_library_root, Configuration.library_root
  end

  test "library_pathname wraps the root" do
    Configuration.instance_variable_set(:@library_root, "/tmp/stubbed")

    assert_equal Pathname.new("/tmp/stubbed"), Configuration.library_pathname
  end

  test "relative_path strips the library root" do
    Configuration.instance_variable_set(:@library_root, "/tmp/stubbed")

    assert_equal "Artist/Album/song.mp3", Configuration.relative_path("/tmp/stubbed/Artist/Album/song.mp3")
  end

  test "relative_path returns the full path for files outside the library" do
    Configuration.instance_variable_set(:@library_root, "/tmp/stubbed")

    assert_equal "../elsewhere/song.mp3", Configuration.relative_path("/tmp/elsewhere/song.mp3")
  end
end
