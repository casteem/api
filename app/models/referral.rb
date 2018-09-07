class Referral < ApplicationRecord
  belongs_to :user
  validates_presence_of :user_id, :remote_ip
end
