require 's_logger'
require 'utils'

desc 'Moderation Stats'
task :mod_stats, [:days] => :environment do |t, args|
  days = args[:days].to_i

  today = Time.zone.today.to_time
  yesterday = (today - days.day).to_time

  logger = SLogger.new('stats')
  posts = Post.where('listed_at >= ? AND listed_at < ?', yesterday, today)

  # Moderator's stats
  total_count = posts.count
  verified_count = posts.where(is_verified: true).count
  active_count = posts.active.where(is_verified: true).count
  pass_rate = 100 * active_count / verified_count.to_f

  all_verification = posts.where(is_verified: true).group(:verified_by).count
  active_verification = posts.active.where(is_verified: true).group(:verified_by).count
  User::MODERATOR_ACCOUNTS.each do |u|
    unless User::ADMIN_ACCOUNTS.include?(u)
      all_verification[u] = 0 if all_verification[u].nil?
      active_verification[u] = 0 if active_verification[u].nil?
    end
  end
  all_verification = all_verification.sort_by { |_, v| v}.reverse

  logger.log "==========\nModerator Stats\n#{formatted_date(Date.yesterday)} - for #{days} days\n==========", true
  logger.log "Number of hunts: #{total_count} in total "
  logger.log "Verified: #{verified_count} (#{total_count - verified_count} unverified, will roll-over)"
  logger.log "Review Pass Rate: #{pass_rate.round(2)}% (#{active_count} passed / #{verified_count - active_count} hidden)"
  logger.log "=========="
  logger.log "Moderation Count:", true
  all_verification.each do |g|
    unless g[0].blank?
      logger.log "@#{g[0]}: #{g[1]} (Pass rate: #{(100 * active_verification[g[0]] / g[1]).round(2) rescue 0}%)"
    end
  end
  logger.log "==========", true
end