require 'radiator'
require 'utils'
require 's_logger'

desc 'Reward Voters'
task :reward_voters => :environment do |t, args|
  TEST_MODE = false # Should be false on production
  HUNT_DISTRIBUTION_VOTE = 40000.0

  logger = SLogger.new('reward-log')
  api = Radiator::Api.new
  today = Time.zone.today.to_time
  yesterday = (today - 1.day).to_time

  logger.log "\n==========\n#{HUNT_DISTRIBUTION_VOTE} HUNT DISTRIBUTION ON VOTERS \n=========", true

  posts = Post.where('listed_at >= ? AND listed_at < ?', yesterday, today).
               where(is_verified: true).order('hunt_score DESC')
  logger.log "Total #{posts.count} verified posts founds\n=="

  bid_bot_ids = get_bid_bot_ids
  other_bot_ids = get_other_bot_ids
  rshares_by_users = {}
  posts.each_with_index do |post, i|
    logger.log "@#{post.author}/#{post.permlink}"

    # Get data from blockchain
    result = with_retry(3) do
      api.get_content(post.author, post.permlink)['result']
    end
    votes = result['active_votes']
    logger.log "--> VOTE COUNT: #{votes.size}"

    votes.each do |vote|
      if post.author == vote['voter']
        logger.log "----> SKIP SELF_VOTINGS"
        next
      end

      if bid_bot_ids.include?(vote['voter'])
        logger.log "----> SKIP BID_BOT: #{vote['voter']}"
        next
      end

      if other_bot_ids.include?(vote['voter'])
        logger.log "----> SKIP OTHER_BOT: #{vote['voter']}"
        next
      end

      if rshares_by_users[vote['voter']]
        rshares_by_users[vote['voter']] += vote['rshares'].to_i
      else
        rshares_by_users[vote['voter']] = vote['rshares'].to_i
      end

      if User::INFLUENCER_ACCOUNTS.include?(vote['voter'])
        rshares_by_users[vote['voter']] += vote['rshares'].to_i * (User::INFLUENCER_WEIGHT_BOOST - 1) # Give influencer x5 in total
        logger.log "----> INFLUENCER X#{User::INFLUENCER_WEIGHT_BOOST}: #{vote['voter']}"
      end
    end
  end

  only_users = {}
  rshares_by_users.each do |k, v|
    if u = User.find_by(username: k)
      only_users[k] = v if u.dau_yesterday?
    end
  end

  total_rshares = only_users.values.sum.to_f
  only_users = only_users.sort_by {|k,v| v}.reverse

  logger.log "\n==========\nFILTERED OUT ONLY STEEMHUNT USERS: #{only_users.size} VOTERS\n=========", true

  total_hunt_distributed = 0
  only_users.each do |pair|
    username = pair[0]
    proportion = pair[1] / total_rshares
    hunt_amount = HUNT_DISTRIBUTION_VOTE * proportion
    total_hunt_distributed += hunt_amount

    if TEST_MODE
      logger.log "TEST - @#{username} received #{hunt_amount.round(2)} HUNT - #{(100 * proportion).round(4)}%"
    else
      HuntTransaction.reward_votings!(username, hunt_amount, yesterday)
      logger.log "@#{username} received #{hunt_amount.round(2)} HUNT - #{(100 * proportion).round(4)}%"
    end
  end

  logger.log "\n==========\nFINISHED #{total_hunt_distributed} HUNT DISTRIBUTION ON #{only_users.size} / #{rshares_by_users.size} VOTERS\n=========", true
end