class ChangeBountyGivenColumnType < ActiveRecord::Migration[5.2]
  def up
    change_column :referrals, :bounty_given, :decimal, default: -1.0
  end

  def down
  	change_column :referrals, :bounty_given, :integer, default: 0
  end
end
