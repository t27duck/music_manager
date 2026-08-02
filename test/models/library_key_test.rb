require "test_helper"

class LibraryKeyTest < ActiveSupport::TestCase
  test "round-trips a pair" do
    assert_equal [ "Various Artists", "Harmony of Heroes" ],
      LibraryKey.decode(LibraryKey.encode("Various Artists", "Harmony of Heroes"), 2)
  end

  test "round-trips a single value" do
    assert_equal [ "Neon Fields" ], LibraryKey.decode(LibraryKey.encode("Neon Fields"), 1)
  end

  # The reason for JSON rather than a delimiter: songs with no album still need
  # a page, and nil has to survive the trip.
  test "round-trips nil" do
    assert_equal [ nil, nil ], LibraryKey.decode(LibraryKey.encode(nil, nil), 2)
  end

  test "round-trips values containing punctuation and non-ASCII" do
    parts = [ %(a/b "c" \\ d), "Splatoon ORIGINAL SOUNDTRACK -Splatune-" ]

    assert_equal parts, LibraryKey.decode(LibraryKey.encode(*parts), 2)
  end

  test "produces a URL-safe key" do
    key = LibraryKey.encode("Rock & Roll / Pop", "100% Hits?")

    assert_equal key, ERB::Util.url_encode(key)
  end

  # A hand-edited URL must be a 404, never a 500.
  test "malformed input is not found rather than an error" do
    [ "", "!!!", "not-base64!", Base64.urlsafe_encode64("not json", padding: false) ].each do |bad|
      assert_raises(ActiveRecord::RecordNotFound, "expected #{bad.inspect} to be rejected") do
        LibraryKey.decode(bad, 2)
      end
    end
  end

  test "the wrong arity is rejected" do
    assert_raises(ActiveRecord::RecordNotFound) { LibraryKey.decode(LibraryKey.encode("only one"), 2) }
  end

  test "a non-array payload is rejected" do
    assert_raises(ActiveRecord::RecordNotFound) do
      LibraryKey.decode(Base64.urlsafe_encode64(%({"a":1}), padding: false), 2)
    end
  end

  test "a payload of the right arity but the wrong types is rejected" do
    assert_raises(ActiveRecord::RecordNotFound) do
      LibraryKey.decode(Base64.urlsafe_encode64("[1, 2]", padding: false), 2)
    end
  end
end
