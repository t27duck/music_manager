require "application_system_test_case"

class AlbumArtTest < ApplicationSystemTestCase
  include LibraryTestHelper

  setup do
    @with_art = SongImporter.call(copy_fixture("with_art.mp3"))
    @with_art.update!(title: "Has Artwork", skip_tag_write: true)

    @without_art = create_test_song("bare.mp3", title: "No Artwork")
    @without_art.remove_album_art!
  end

  test "the list shows thumbnails and placeholders" do
    visit root_path

    assert_selector "tr", text: "Has Artwork" do
      assert_selector "img[alt*='Has Artwork']"
    end
    assert_selector "[title='No album art']"
  end

  test "uploading art updates the modal and the row thumbnail" do
    visit root_path
    find("tr", text: "No Artwork").click_link("Edit")

    attach_file "Album art image", fixture_file("cover.jpg")
    click_on "Upload art"

    assert_text "Album art updated."
    assert_predicate @without_art.reload, :album_art?

    # The modal stays open and now previews the art.
    assert_selector "dialog img[alt*='No Artwork']"

    click_on "Cancel"
    assert_selector "tr td img[alt*='No Artwork']"
  end

  test "uploaded art is written into the MP3 itself" do
    visit root_path
    find("tr", text: "No Artwork").click_link("Edit")

    attach_file "Album art image", fixture_file("cover.jpg")
    click_on "Upload art"
    assert_text "Album art updated."

    assert_equal File.binread(fixture_file("cover.jpg")), Mp3File.new(@without_art.file_path).album_art
  end

  test "removing art falls back to the placeholder" do
    visit root_path
    find("tr", text: "Has Artwork").click_link("Edit")

    accept_confirm { click_on "Remove art" }

    assert_text "Album art removed."
    assert_not_predicate @with_art.reload, :album_art?
    assert_nil Mp3File.new(@with_art.file_path).album_art

    click_on "Cancel"
    assert_selector "[title='No album art']", count: 2
  end

  test "a non-image upload is rejected without closing the modal" do
    not_an_image = File.join(@temp_dir, "notes.txt")
    File.write(not_an_image, "definitely not an image")

    visit root_path
    find("tr", text: "No Artwork").click_link("Edit")

    attach_file "Album art image", not_an_image
    click_on "Upload art"

    assert_selector "dialog [role=alert]", text: /JPEG, PNG or GIF/
    assert_not_predicate @without_art.reload, :album_art?
  end

  test "the metadata form still works alongside the art panel" do
    visit root_path
    find("tr", text: "No Artwork").click_link("Edit")

    fill_in "Title", with: "Renamed Alongside Art"
    click_on "Save changes"

    assert_no_selector "dialog"
    assert_text "Renamed Alongside Art"
  end
end
