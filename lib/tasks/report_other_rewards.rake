require 'radiator'
require 's_logger'
require 'utils'

desc 'Report other HUNT token rewards for today'
task :report_other_rewards => :environment do |t, args|
  logger = SLogger.new('reward-log')
  today = Time.zone.today.to_time
  yesterday = (today - 1.day).to_time

  sums = HuntTransaction.where('created_at >= ? AND created_at < ?', yesterday, today).
    group(:bounty_type).
    sum(:amount).
    sort_by { |k, v| v }.reverse

  logger.log "=========="
  logger.log "HUNT DISTRIBUTION - #{formatted_date(yesterday)}"
  logger.log "=========="
  sums.each do |s|
    logger.log "#{s[0]} - #{formatted_number(s[1])}"
  end
  logger.log "==========", true
end
