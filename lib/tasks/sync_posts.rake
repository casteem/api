require 'radiator'
require 's_logger'

desc 'Synchronize posts'
task :sync_posts, [:days] => :environment do |t, args|
  days = args[:days].to_i

  logger = SLogger.new
  today = Time.zone.today.to_time + 1.day
  day_start = (today - (days).day).to_time
  day_end = (today - (days + 1).day).to_time

  posts = Post.where('listed_at >= ? AND listed_at < ?', day_end, day_start).
               where(is_active: true)

  api = Radiator::Api.new
  diff = 0
  posts.each do |post|
    # logger.log "@#{post.author}/#{post.permlink}"
    old_votes = post.active_votes.size
    old_payout = post.payout_value
    old_comments = post.children
    old_hunt_score = post.hunt_score
    post.sync! api.get_content(post.author, post.permlink)['result']

    diff += post.payout_value - old_payout
    # logger.log "--> HuntScore: #{old_hunt_score.round(2)} -> #{post.hunt_score.round(2)}"
    # logger.log "--> Payout: #{old_payout.round(2)} -> #{post.payout_value.round(2)}" if diff.abs > 0.1
    # logger.log "--> Likes: #{old_votes} -> #{post.active_votes.size}" if post.active_votes.size != old_votes
    # logger.log "--> Comments: #{old_comments} -> #{post.children}" if post.children != old_comments
  end

  logger.log "== UPDATES #{posts.count} POSTS ON DAY #{days}: #{'+' if diff > 0}#{diff.round(2)} SBD", true
end