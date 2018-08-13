require 'utils'
require 's_logger'

class ErcTransaction < ApplicationRecord
  belongs_to :user
  validates_presence_of :user_id, :amount
  validate :validate_hash_format, :check_balance
  scope :pending, -> { where(status: 'pending') }

  VALID_STATUS = %w(pending running sent error)
  validates :status, inclusion: { in: VALID_STATUS }
  after_create :deduct_balance!

  def validate_hash_format
    unless tx_hash.blank?
      errors.add(:tx_hash, "Wrong format") if tx_hash.size != 66 || !tx_hash.downcase.start_with?('0x')
    end
  end

  def check_balance
    errors.add(:amount, "Not enough balance") if user.hunt_balance < self.amount
  end

  def deduct_balance!
    user.update!(hunt_balance: user.hunt_balance - self.amount)
  end
end