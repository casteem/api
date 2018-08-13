class ChangeColumnsForEthTransactions < ActiveRecord::Migration[5.2]
  def change
    remove_column :hunt_transactions, :eth_address, :string, limit: 42
    remove_column :hunt_transactions, :eth_tx_hash, :string, limit: 66

    create_table :erc_transactions do |t|
      t.references :user, null: false
      t.decimal :amount, null: false
      t.string :tx_hash, limit: 66, default: nil
      t.string :status, default: 'pending'

      t.timestamps
    end
    add_index :erc_transactions, :status
  end
end
