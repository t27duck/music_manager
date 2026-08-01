# MusicManager has no reference data to seed: every Song is derived from a file
# on disk, so the library itself is the source of truth.
#
# To populate the database, point LIBRARY_ROOT at your music and run a sync --
# either from the "Sync library" button or here:
#
#   bin/rails runner 'LibrarySync.call'
#
# `db:seed:replant` (which bin/ci runs) therefore truncates and does nothing
# further, which is the correct outcome: seeding must never invent songs that
# have no file behind them.
Rails.logger.info("Nothing to seed. Run a library sync to import songs from #{Configuration.library_root}.")
