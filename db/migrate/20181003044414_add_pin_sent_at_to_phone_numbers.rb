class AddPinSentAtToPhoneNumbers < ActiveRecord::Migration[5.2]
  def change
    add_column :phone_numbers, :pin_sent_at, :datetime
  end
end
