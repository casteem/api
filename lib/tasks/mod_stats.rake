require 's_logger'
require 'utils'

desc 'Moderation Stats'
task :mod_stats => :environment do |t, args|
  today = Time.zone.today.to_time
  yesterday = (today - 1.day).to_time

  posts = Post.where('created_at >= ? AND created_at < ?', yesterday, today)
  total_count = posts.count
  verified_count = posts.verified.count
  active_count = posts.active.verified.count
  pass_rate = 100 * active_count / verified_count.to_f

  all_verification = posts.verified.group(:verified_by).count
  active_verification = posts.active.verified.group(:verified_by).count
  User::MODERATOR_ACCOUNTS.each do |u|
    unless User::ADMIN_ACCOUNTS.include?(u)
      all_verification[u] = 0 if all_verification[u].nil?
      active_verification[u] = 0 if active_verification[u].nil?
    end
  end
  all_verification = all_verification.sort_by { |_, v| v}.reverse

  logger = SLogger.new('stats')
  logger.log "==========\nDaily Stats on #{formatted_date(Date.yesterday)}\n==========", true
  logger.log "Number of hunts: #{total_count} in total "
  logger.log "Verified: #{verified_count} (#{total_count - verified_count} unverified, will roll-over)"
  logger.log "Review Pass Rate: #{pass_rate.round(2)}% (#{active_count} passed / #{verified_count - active_count} hidden)"
  logger.log "Moderation Count:"
  all_verification.each do |g|
    unless g[0].blank?
      logger.log "@#{g[0]}: #{g[1]} (Pass rate: #{(100 * active_verification[g[0]] / g[1]).round(2) rescue 0}%)"
    end
  end
  logger.log "==========", true
end