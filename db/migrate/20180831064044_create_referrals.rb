class CreateReferrals < ActiveRecord::Migration[5.2]
  def change
    create_table :referrals do |t|
      t.references :user, null: false, index: false
      t.string :remote_ip, null: false
      t.integer :referral_type
      t.string :path
      t.datetime :created_at
    end
    add_index :referrals, [:user_id, :remote_ip], unique: true
  end
end
