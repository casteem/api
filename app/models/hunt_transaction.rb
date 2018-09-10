require 'utils'
require 's_logger'

class HuntTransaction < ApplicationRecord
  BOUNTY_TYPES = %w(sponsor voting resteem sp_claim posting commenting social_share report moderator contribution guardian)
  SP_CLAIM_EXCLUSION = %w(steem steemit misterdelegation)

  validates_presence_of :amount, :memo, :sender, :receiver
  validates :memo, length: { maximum: 255 }
  validates :bounty_type, inclusion: { in: BOUNTY_TYPES }

  def self.reward_reporter!(username, amount)
    logger = SLogger.new('reward-log')

    if user = User.find_by(username: username)
      today = Time.zone.today.to_time
      reward_user!(username, amount, 'report', "Bounty rewards for reporting abusing users - #{formatted_date(today)}", false)
      logger.log "ABUSING_REPORT] Sent #{amount} HUNT to @#{username}\nBalance: #{user.hunt_balance} -> #{user.reload.hunt_balance}", true
    else
      logger.log "No user found: @#{username}", true
    end
  end

  def self.reward_contributor!(username, amount, week, bounty_type, memo)
    logger = SLogger.new('reward-log')

    if user = User.find_by(username: username)
      msg = "#{memo} - week #{week}"
      reward_user!(username, amount, bounty_type, msg, true)
      logger.log "#{bounty_type.upcase}] Sent #{amount} HUNT to @#{username} - #{msg}\n" +
        "Balance: #{user.hunt_balance.round(2)} -> #{user.reload.hunt_balance.round(2)}", true
    else
      logger.log "No user found: @#{username}", true
    end
  end

  def self.reward_sponsor!(username, amount, week)
    reward_user!(username, amount, 'sponsor', "Weekly reward for delegation sponsor - week #{week}", true)
  end

  def self.reward_votings!(username, amount, date)
    reward_user!(username, amount, 'voting', "Daily reward for voting contribution - #{formatted_date(date)}", true)
  end

  def self.reward_social_shares!(username, amount, date)
    reward_user!(username, amount, 'social_share', "Daily reward for social shares - #{formatted_date(date)}", true)
  end

  # DEPRECATED
  # def self.reward_resteems!(username, amount, date)
  #   reward_user!(username, amount, 'resteem', "Daily reward for resteem contribution - #{formatted_date(date)}", true)
  # end

  def self.claim_sp!(username, sp_amount)
    raise 'Already claimed' if self.exists?(receiver: username, bounty_type: 'sp_claim')
    raise 'Excluded' if SP_CLAIM_EXCLUSION.include?(username)
    raise 'Airdrop for SP holder has finished' if HuntTransaction.where(bounty_type: 'sp_claim').sum(:amount) > 100000000

    reward_user!(username, sp_amount, 'sp_claim', "Airdrop for SP Holder - @#{username}: #{formatted_number(sp_amount)} SP - #{formatted_date(Time.now)}", true)
  end

  private_class_method def self.reward_user!(username, amount, bounty_type, memo, check_dups = false)
    return if amount == 0
    raise 'Duplicated Rewards' if check_dups && self.exists?(receiver: username, memo: memo)

    user = User.find_by(username: username)
    user = User.create!(username: username, encrypted_token: '') unless user

    send!(amount, 'steemhunt', user.username, bounty_type, memo)
  end

  private_class_method def self.send!(amount, sender_name = nil, receiver_name = nil, bounty_type = nil, memo = nil)
    return if amount == 0

    sender = sender_name.blank? ? nil : User.find_by(username: sender_name)
    receiver = receiver_name.blank? ? nil : User.find_by(username: receiver_name)

    ActiveRecord::Base.transaction do
      self.create!(
        sender: sender_name,
        receiver: receiver_name,
        amount: amount,
        bounty_type: bounty_type,
        memo: memo
      )

      unless sender.blank?
        sender.update!(hunt_balance: sender.hunt_balance - amount)
      end
      unless receiver.blank?
        receiver.update!(hunt_balance: receiver.hunt_balance + amount)
      end
    end
  end
end
