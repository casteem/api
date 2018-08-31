class ChangeColumnTypoOfReferrals < ActiveRecord::Migration[5.2]
  def change
    rename_column :referrals, :remote_id, :remote_ip
  end
end
