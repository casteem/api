require 's_logger'
require 'utils'

desc 'Level Stats'
task :level_stats => :environment do |t, args|
  tier = User::LEVEL_TIER

  levels = []
  levels.push User.where('cached_user_score < ?', tier[0]).count
  levels.push User.where('cached_user_score >= ? AND cached_user_score < ?', tier[0], tier[1]).count
  levels.push User.where('cached_user_score >= ? AND cached_user_score < ?', tier[1], tier[2]).count
  levels.push User.where('cached_user_score >= ? AND cached_user_score < ?', tier[2], tier[3]).count
  levels.push User.where('cached_user_score >= ? AND cached_user_score < ?', tier[3], tier[4]).count
  levels.push User.where('cached_user_score >= ?', tier[4]).count

  logger = SLogger.new('bot-log')
  logger.log "==========\nLevel Stats on #{formatted_date(Time.zone.today.to_date)}"
  logger.log "Distribution: #{levels}", true

  logger.log "Top Users:"
  User.order(cached_user_score: :desc).limit(10).each do |u|
    logger.log "- @#{u.username}: #{u.user_score.round(2)}"
  end
  logger.log "\n==========", true
end