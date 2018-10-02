class CreatePhoneNumbers < ActiveRecord::Migration[5.2]
  def change
    create_table :phone_numbers do |t|
      t.string :number
      t.integer :pin
      t.boolean :verified, default: false
      t.integer :pin_sent, default: 0

      t.timestamps
    end
  end
end
