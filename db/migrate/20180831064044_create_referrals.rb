class CreateReferrals < ActiveRecord::Migration[5.2]
  def change
    create_table :referrals do |t|
      t.references :user, null: false, index: false
      t.string :remote_ip, null: false
      t.string :path
      t.string :referral
      t.string :user_agent
      t.datetime :created_at
    end
    add_index :referrals, [:user_id, :remote_ip], unique: true
  end
end
