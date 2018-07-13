class AddIpAddrOnUsers < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :last_ip, :string, default: nil
  end
end
