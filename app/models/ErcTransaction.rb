require 'utils'
require 's_logger'

class ErcTransaction < ApplicationRecord
  belongs_to :user
  validates_presence_of :user_id, :amount
  validate :validate_hash_format
  scope :pending, -> { where(status: 'pending') }

  VALID_STATUS = %w(pending sent error)
  validates :status, inclusion: { in: VALID_STATUS }

  def validate_hash_format
    unless eth_tx_hash.blank?
      errors.add(:eth_tx_hash, "Wrong format") if eth_tx_hash.size != 66 || !eth_tx_hash.downcase.start_with?('0x')
    end
  end
end
