class CreateIssueDatetimes < ActiveRecord::Migration[7.2]
  def change
    create_table :issue_datetimes do |t|
      t.references :issue, null: false, index: {unique: true}, foreign_key: true
      t.datetime :starts_at
      t.datetime :ends_at
      t.timestamps null: false
    end
  end
end
