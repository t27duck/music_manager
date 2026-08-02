# Temporarily replaces a constant for the duration of a block.
#
# For limits that exist to guard against sizes no test should actually build --
# SongListing::SELECTION_LIMIT is 5,000 songs, and creating those means 5,000
# real MP3s on disk. Lowering the limit tests the same branch in milliseconds.
module ConstantStubbing
  def stub_const(owner, name, value)
    original = owner.const_get(name)

    owner.send(:remove_const, name)
    owner.const_set(name, value)

    yield
  ensure
    owner.send(:remove_const, name)
    owner.const_set(name, original)
  end
end
