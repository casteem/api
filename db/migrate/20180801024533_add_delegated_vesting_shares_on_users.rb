class AddDelegatedVestingSharesOnUsers < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :delegated_vesting_shares, :float, default: -1.0
  end
end
