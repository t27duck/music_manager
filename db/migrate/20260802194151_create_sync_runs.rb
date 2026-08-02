class CreateSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_runs do |t|
      t.string   :state,    null: false
      t.boolean  :forced,   null: false, default: false   # was it a full rescan?
      t.integer  :total,    null: false, default: 0       # files the scan found
      t.integer  :skipped,  null: false, default: 0       # left unread, timestamp unchanged
      # JSON array of messages, and deliberately nullable: Active Record's
      # serialized type maps an empty array back to NULL (it equals the coder's
      # own default), so a NOT NULL column could never hold a run that had no
      # failures. NULL reads back as [].
      t.text     :failures
      t.datetime :finished_at

      # No started_at: the row is created as the run begins, so created_at *is*
      # the start time and a second column would only drift from it.
      t.timestamps
    end

    # The history page orders by it and retention deletes by it. It is the only
    # index the table earns -- retention caps it at SyncRun::KEEP rows, so every
    # other column is a scan of a hundred rows.
    add_index :sync_runs, :created_at
  end
end
