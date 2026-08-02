class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.string :key, null: false
      t.string :value

      t.timestamps
    end

    # The natural key: Setting[] reads by it, and Setting[]= must not be able to
    # create a second row for a name that already exists.
    add_index :settings, :key, unique: true
  end
end
