require 'radiator'
require 'utils'
require 's_logger'

desc 'Voting bot'
task :voting_bot, [:session] => :environment do |t, args|
  SESSION_NUMBER = args[:session].to_i

  # NOTE: The total voting power is not a constant number like 1000
  #   it will be closer to 1100 because:
  #   when someone cast 100% voting when they have 80% vp left,
  #   it will deduct 0.8 * 100 * 0.02 = 1.6% vp (not 2.0%)

  TEST_MODE = false # Should be false on production
  VOTING_SESSIONS = 6
  SESSION_GAP = 24 / VOTING_SESSIONS
  MAX_HUNTS_PER_SESSION = 50
  TOTAL_VP_TO_USE = 1000.0 / VOTING_SESSIONS

  def current_voting_power(api = Radiator::Api.new)
    account = with_retry(3) do
      api.get_accounts(['steemhunt'])['result'][0]
    end
    vp_left = (account['voting_power'] / 100.0).round(2)

    last_vote_time = Time.parse(account['last_vote_time']) + Time.new.gmt_offset
    time_past = Time.now - last_vote_time

    # VP recovers (20/24)% per hour
    current_vp = (vp_left + (time_past / 3600.0) * (20.0/24.0)).round(2)

    current_vp > 100 ? 100.0 : current_vp
  end

  # POWER_TOTAL_POST = if TEST_MODE || current_voting_power > 99.99
  #   TOTAL_VP_TO_USE * 0.8
  # else
  #   # NOTE:
  #   # If current VP is 70%, we need to only use 10% VP (= 540 VP)
  #   # This script should not run if POWER_TOTAL_POST < 0
  #   (TOTAL_VP_TO_USE - (TOTAL_VP_TO_USE * (100 - current_voting_power) / 20)) * 0.8
  # end

  POWER_TOTAL_POST = TOTAL_VP_TO_USE * 0.8
  POWER_TOTAL_COMMENT = POWER_TOTAL_POST * 0.125 # 10% of total VP
  POWER_PER_MOD_COMMENT = 0.60 # 120% on 200 posts, 240% on 400 posts
  POWER_MAX = 20.0

  def get_minimum_power(size)
    min = POWER_TOTAL_POST / (size * 10.0)
    min = POWER_MAX if min > POWER_MAX
    min = 0.01 if min < 0.01

    min
  end

  # def evenly_distributed_array(size)
  #   return Array.new(size, POWER_MAX) if size <= POWER_TOTAL_POST /  POWER_MAX

  #   average = POWER_TOTAL_POST / size
  #   array = Array.new(size, average)
  #   half = (size / 2).floor

  #   variation = [POWER_MAX - array[0], array[size - 1] - get_minimum_power(size)].min / half

  #   half.times do |i|
  #     array[i] = array[i] + variation * (half - i)
  #     array[size - i - 1] = array[size - i - 1] - variation * (half - i)
  #   end

  #   array.map { |n| n.round(2) }
  # end

  # Ref: https://github.com/Steemhunt/web/issues/102
  def natural_distribution_test(size, temperature)
    orders = (1..size - 1).to_a
    exponents = orders.map { |o| Math.exp(o / temperature.to_f) }
    sum = exponents.sum
    softmaxes = exponents.map { |e| e / sum }

    minimum = get_minimum_power(size)
    allocated = Array.new(size, minimum)
    allocated[0] = POWER_MAX
    available = POWER_TOTAL_POST - POWER_MAX - minimum * (size - 1)

    (1..size - 1).each do |i|
      allocated[i] += (available * softmaxes[size -  i - 1])
    end

    allocated
  end

  def natural_distributed_array(size)
    return Array.new(size, POWER_MAX) if size <= POWER_TOTAL_POST /  POWER_MAX

    minimum = get_minimum_power(size)

    selected = nil
    (1..1000).each do |t|
      test_array = natural_distribution_test(size, t)
      if test_array.any? { |n| n > POWER_MAX || n < minimum ||  n.nan? }
        next
      else
        selected = test_array # first match, steepest possible
        break
      end
    end

    if selected.nil?
      raise "Distribution is not possible - POWER_TOTAL_POST: #{POWER_TOTAL_POST} / size: #{size}"
    else
      selected.map { |n| n.round(2) }
    end
  end

  def do_vote(author, permlink, power, logger)
    tx = Radiator::Transaction.new(wif: ENV['STEEMHUNT_POSTING_KEY'])
    vote = {
      type: :vote,
      voter: 'steemhunt',
      author: author,
      permlink: permlink,
      weight: (power * 100).to_i
    }
    tx.operations << vote
    begin
      with_retry(3) do
        tx.process(!TEST_MODE)
      end
    rescue => e
      logger.log "FAILED VOTING: @#{author}/#{permlink} / POWER: #{power}"
    end
  end

  def do_comment(author, permlink, rank, logger)
    the_date = (Time.zone.now - 1.hour).beginning_of_day # should be yesterday on midnight voting session
    msg = "### Congratulation! Your hunt was ranked in #{rank.ordinalize} place on #{SESSION_NUMBER.ordinalize} session on #{formatted_date(the_date)}.\n" +
      "We have upvoted your post for your contribution within our community.\n" +
      "You will see the final top 10 on [Steemhunt](https://steemhunt.com) after midnight (#{formatted_date(the_date)} KST).\n" +
      "Thanks again and look forward to seeing your next hunt!\n\n" +
      "Want to chat? Join us on:\n" +
      "* Discord: https://discord.gg/mWXpgks\n" +
      "* Telegram: https://t.me/joinchat/AzcqGxCV1FZ8lJHVgHOgGQ\n"

    tx = Radiator::Transaction.new(wif: ENV['STEEMHUNT_POSTING_KEY'])
    comment = {
      type: :comment,
      parent_author: author,
      parent_permlink: permlink,
      author: 'steemhunt',
      permlink: "re-#{permlink}-steemhunt",
      title: '',
      body: msg,
      json_metadata: {
        tags: ['steemhunt'],
        community: 'steemhunt',
        app: 'steemhunt/1.0.0',
        format: 'markdown'
      }.to_json
    }
    tx.operations << comment

    begin
      tx.process(!TEST_MODE)
    rescue => e
      logger.log "FAILED COMMENT: @#{author}/#{permlink} / RANK: #{rank}"
    end
  end

  def comment_already_voted?(comment, api)
    votes = with_retry(3) do
      api.get_content(comment['author'], comment['permlink'])['result']['active_votes']
    end

    votes.each do |vote|
      if vote['voter'] == 'steemhunt'
        return true
      end
    end

    return false
  end


  # Votinbot Begin


  logger = SLogger.new('voting-log')

  if POWER_TOTAL_POST < 0
    logger.log "Not enough voting power left, STOP voting bot"
    next
  end

  api = Radiator::Api.new
  base_date = (Time.zone.now - 1.hour).beginning_of_day # should be yesterday on midnight voting session
  session_start = base_date + (SESSION_NUMBER * SESSION_GAP).hours
  session_end = session_start + SESSION_GAP.hours

  logger.log "\n==========\n POST VOTING STARTS with #{(POWER_TOTAL_POST * 1.25).round(2)}% VP - Session #{SESSION_NUMBER} on #{formatted_date(base_date)}", true
  logger.log "Current voting power: #{current_voting_power(api)}%"
  posts = Post.where('verified_at >= ? AND verified_at < ?', session_start, session_end).
               order('hunt_score DESC').
               limit(MAX_HUNTS_PER_SESSION).to_a
  logger.log "Total #{posts.size} posts found\n==========", true

  review_comments = []
  total_review_comment_count = 0
  moderators_comments =  []
  posts_to_skip = [] # posts that should skip votings, but need to be counted for VP
  posts_to_remove = [] # posts  that should be removed from the ranking entirely (not counted for VP)
  posts.each_with_index do |post, i|
    logger.log "@#{post.author}/#{post.permlink}"

    unless post.is_verified
      posts_to_remove << post.id
      post.update! created_at: Time.now # pass it over to the next date
      logger.log "--> REMOVE: Not yet verified"
      next
    end

    # Get data from blockchain
    result = with_retry(3) do
      api.get_content(post.author, post.permlink)['result']
    end
    votes = result['active_votes']

    if post.is_active
      if result['title'].blank?
        posts_to_remove << post.id
        logger.log "--> REMOVE: No blockchain data on Steem -------------->>> ACTION REQUIRED"
        next
      end

      if User.find_by(username: post.author).try(:blacklist?)
        posts_to_remove << post.id
        logger.log "--> REMOVE_BLACKLIST: still checks comments for moderators and review comments"
      end

      # logger.log "--> VOTE COUNT: #{votes.size}"
      votes.each do |vote|
        if vote['voter'] == 'steemhunt'
          posts_to_skip << post.id
          logger.log "--> SKIP: Already voted"
        end
      end
    else
      posts_to_remove << post.id
      logger.log "--> HIDDEN: still checks comments for moderators and review comments"
    end

    comments = with_retry(3) do
      api.get_content_replies(post.author, post.permlink)['result']
    end
    # logger.log "----> #{comments.size} comments returned"

    # duplication checks for each posts
    review_commnet_added = {}
    mod_comment_added = {}
    comments.each do |comment|
      json_metadata = JSON.parse(comment['json_metadata']) rescue {}
      json_metadata = {} unless json_metadata.is_a?(Hash) # Handle invalid json_metadata format

      is_review = comment['body'] =~ /pros\s*:/i && comment['body'] =~ /cons\s*:/i
      is_moderator = !(json_metadata['verified_by'].blank?)

      if is_review || is_moderator
        should_skip = comment_already_voted?(comment, api)

        # 1. Moderator comments
        if is_moderator
          if  User::MODERATOR_ACCOUNTS.include?(comment['author'])
            if mod_comment_added[comment['author']]
              logger.log "--> REMOVE DUPLICATED_MOD_COMMENT: @#{comment['author']}"
            else
              moderators_comments.push({ author: comment['author'], permlink: comment['permlink'], should_skip: should_skip })
              mod_comment_added[comment['author']] = true
              logger.log "--> #{should_skip ? 'SKIP ALREADY_VOTED' : 'ADDED'} Mod comment: @#{comment['author']}"
            end
          else
            logger.log "--> WTF!!!!! Mod comment: @#{comment['author']}/#{comment['permlink']}"
          end
        # 2. Review comments
        elsif is_review
          total_review_comment_count += 1
          review_user = User.find_by(username: comment['author'])

          if review_commnet_added[comment['author']]
            logger.log "--> REMOVE DUPLICATED_REVIEW_COMMENT: @#{comment['author']}"
          elsif comment['body'].size < 80
            logger.log "--> REMOVE TOO_SHORT_REVIEW_COMMENT: @#{comment['author']}"
          elsif !votes.any? { |v| v['voter'] == comment['author'] && v['percent'] >= 3000 }
            logger.log "--> REMOVE NOT_VOTED_REVIEW_COMMENT: @#{comment['author']}"
          elsif comment['author'] == post.author
            logger.log "--> REMOVE SELF_REVIEW_COMMENT: @#{comment['author']}"
          elsif review_user.nil?
            logger.log "--> REMOVE NOT_A_USER: @#{comment['author']}"
          elsif !review_user.dau_yesterday?
            logger.log "--> REMOVE NOT_DAU: @#{comment['author']}"
          elsif review_user.reputation < 35
            logger.log "--> REMOVE LOW_REPUTATION: @#{comment['author']}"
          elsif review_user.try(:blacklist?)
            logger.log "--> REMOVE_BLACKLIST: @#{comment['author']}"
          else
            review_comments.push({ author: comment['author'], permlink: comment['permlink'], should_skip: should_skip })
            review_commnet_added[comment['author']] = true
            logger.log "--> #{should_skip ? 'SKIP ALREADY_VOTED' : 'ADDED'} Review comment: @#{comment['author']}"
          end
        end
      end
    end # comments.each
  end # posts.each

  original_post_size = posts.size
  posts = posts.to_a.reject { |post| posts_to_remove.include?(post.id) }
  vp_distribution = natural_distributed_array(posts.size)
  total_reward = posts.reduce(0) { |s, p| s + p.payout_value }

  logger.log "\n==========\nTotal #{original_post_size} posts -> #{posts.size} accepted\n"
  logger.log "Total reward (active): $#{total_reward.round(2)} SBD -> \n"
  logger.log "Total #{total_review_comment_count} review comments -> #{review_comments.size} qualified\n"
  logger.log "Voting start with\n - #{POWER_TOTAL_POST.round(2)}% VP on Posts\n - #{POWER_TOTAL_COMMENT.round(2)}% VP on Posts\n==========", true

  posts.each_with_index do |post, i|
    ranking = i + 1
    voting_power = vp_distribution[ranking - 1]

    logger.log "Voting on ##{ranking} / #{posts.size} (#{voting_power.round(2)}%): @#{post.author}/#{post.permlink}", true
    if posts_to_skip.include?(post.id)
      logger.log "--> SKIPPED_POST (#{ranking}/#{posts.size})"
    else
      sleep(20) unless TEST_MODE
      res = do_vote(post.author, post.permlink, voting_power, logger)
      # logger.log "--> VOTED_POST: #{res.inspect}"
      res = do_comment(post.author, post.permlink, ranking, logger)
      # logger.log "--> COMMENTED: #{res.inspect}", true
    end
  end

  logger.log "\n==========\nVOTING ON #{review_comments.size} REVIEW COMMENTS with #{POWER_TOTAL_COMMENT.round(2)}% VP"
  review_comments = review_comments.sample(100)
  logger.log "Pick 100 review comments randomly\n==========", true

  voting_power = (POWER_TOTAL_COMMENT / review_comments.size).floor(2)
  voting_power = 100.0 if voting_power > 100
  review_comments.each_with_index do |comment, i|
    logger.log "[#{i + 1} / #{review_comments.size}] Voting on review comment (#{voting_power}%): @#{comment[:author]}/#{comment[:permlink]}", true
    if comment[:should_skip]
      logger.log "--> SKIPPED_REVIEW", true
    else
      sleep(3) unless TEST_MODE
      res = do_vote(comment[:author], comment[:permlink], voting_power, logger)
      # logger.log "--> VOTED_REVIEW: #{res.inspect}", true
    end
  end

  moderators_comments_size = moderators_comments.size
  logger.log "\n==========\nVOTING ON #{moderators_comments_size} MODERATOR COMMENTS with #{moderators_comments_size *  POWER_PER_MOD_COMMENT}% VP in total\n==========", true

  voting_power = POWER_PER_MOD_COMMENT
  moderators_comments.each_with_index do |comment, i|
    logger.log "[#{i + 1} / #{moderators_comments_size}] Voting on moderator comment (#{voting_power}%): @#{comment[:author]}/#{comment[:permlink]}", true
    if comment[:should_skip]
      logger.log "--> SKIPPED_MODERATOR", true
    else
      sleep(3) unless TEST_MODE
      res = do_vote(comment[:author], comment[:permlink], voting_power, logger)
      # logger.log "--> VOTED_MODERATOR: #{res.inspect}", true
    end
  end

  logger.log "\n==========\nVotings Finished, #{current_voting_power(api)}% VP left\n==========", true
end