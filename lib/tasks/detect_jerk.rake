require 's_logger'

desc 'Detect Jerk'
task :detect_jerk => :environment do |t, args|
  logger = SLogger.new
  users = Post.today.order('hunt_score DESC').pluck(:author).to_a
  uniq_users = users.uniq

  logger.log "\n===========\nStart detecting circle jerking on #{users.count} posts -> #{uniq_users.count} users (chained)\n===========\n", true
  uniq_users.each do |user|
    User.find_by(username: user).detect_circle(:optional, logger)
  end
  logger.log "\n===========\nFinished detecting circle jerking\n===========\n", true
end