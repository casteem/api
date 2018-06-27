require 's_logger'
require 'utils'

desc 'Moderation Stats'
task :mod_stats => :environment do |t, args|
  today = Time.zone.today.to_time
  yesterday = (today - 1.day).to_time

  posts = Post.where('created_at >= ? AND created_at < ?', yesterday, today)
  total_count = posts.count
  verified_count = posts.where(is_verified: true).count
  active_count = posts.active.where(is_verified: true).count
  pass_rate = 100 * active_count / verified_count.to_f

  groups = posts.active.group(:verified_by).count
  User::MODERATOR_ACCOUNTS.each do |u|
    groups[u] = 0 if groups[u].nil?
  end
  groups = groups.sort_by { |_, v| v}.reverse

  logger = SLogger.new('stats')
  logger.log "==========\nDaily Stats on #{formatted_date(Date.yesterday)}\n==========", true
  logger.log "Number of hunts: #{total_count} in total "
  logger.log "Verified: #{verified_count} (#{total_count - verified_count} unverified, will roll-over)"
  logger.log "Review Pass Rate: #{pass_rate.round(2)}% (#{active_count} passed / #{verified_count - active_count} hidden)"
  logger.log "Moderation Count:"
  groups.each do |g|
    logger.log "@#{g[0]}: #{g[1]}"
  end
  logger.log "==========", true
end