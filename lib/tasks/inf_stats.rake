require 's_logger'
require 'utils'

desc 'Influencer Stats'
task :inf_stats, [:days] => :environment do |t, args|
  days = args[:days].to_i

  today = Time.zone.today.to_time
  yesterday = (today - days.day).to_time

  logger = SLogger.new('stats')
  posts = Post.where('listed_at >= ? AND listed_at < ?', yesterday, today)

  logger.log "=========="
  logger.log "Influencer Curation Score (Average score boost after their votes)"
  logger.log "#{formatted_date(Date.yesterday)} - for #{days} days"
  logger.log "==========", true

  # Influencer stats
  inf_counts = {} # username: count
  inf_scores = {} # username: score
  User::INFLUENCER_ACCOUNTS.each { |u| inf_counts[u] = 0; inf_scores[u] = 0 }

  posts.active.where(is_verified: true).each_with_index do |post, i|
    ranking = i + 1

    valid_vote_scores = {}
    post.valid_votes.each { |v| valid_vote_scores[v['voter']] = v['score'] }
    acc_score = 0
    post.active_votes.sort_by { |v| Time.parse(v['time']).to_i }.each do |v|
      next unless valid_vote_scores[v['voter']]

      acc_score += valid_vote_scores[v['voter']].to_f # HS after the user's vote

      if User::INFLUENCER_ACCOUNTS.include?(v['voter'])
        inf_counts[v['voter']] += 1
        inf_scores[v['voter']] += post.hunt_score - acc_score # score = final score - score after my vote
      end
    end
  end

  # Score is based on the efficiency (boosted by voting count)
  inf_scores.each do |k, v|
    boost = inf_counts[k] / (days * 3.5)
    boost = 2.0 if boost > 2
    inf_scores[k] = inf_counts[k] == 0 ? 0 : (boost * v / inf_counts[k])
  end

  inf_scores.sort_by { |k, v| v }.reverse.each do |c|
    logger.log "@#{c[0]} - Score: #{c[1].round(2)} / Vote count: #{inf_counts[c[0]]}"
  end

  logger.log "==========", true
end