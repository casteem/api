class Referral < ApplicationRecord
  enum referral_type: { unknown: 0, facebook: 1, twitter: 2, linkedin: 3 }
  belongs_to :user
  validates_presence_of :user_id, :remote_ip
end
