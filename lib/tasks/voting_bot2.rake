require 'radiator'
require 'utils'
require 's_logger'

desc 'Voting Bot v2'
task :voting_bot2 => :environment do |t, args|
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

  TEST_MODE = true # Should be false on production
  # NOTE: it's more like 1100 as vp decays recursively depending on the current vp
  # We keep 100 for contributor votings
  TOTAL_VP_TO_USE = 950.0
  POWER_TOTAL_POST = if TEST_MODE || current_voting_power > 99.99
    TOTAL_VP_TO_USE
  else
    # NOTE:
    # If current VP is 90%, we need to only use 10% VP (= 500 VP)
    # This script should not run if POWER_TOTAL_POST < 0
    (TOTAL_VP_TO_USE - (TOTAL_VP_TO_USE * (100 - current_voting_power) / 20))
  end
  POWER_ADDED_PER_MOD_COMMENT = 0.60
  POWER_ADDED_PER_INF_COMMENT = 0.50

  MAX_TOTAL_HUNT_VOTING_COUNT = 100
  # MAX_TOTAL_COMMENT_VOTING_COUNT = 200
  MAX_HUNT_VOTING_COUNT_PER_USER = 1
  MAX_COMMENT_VOTING_COUNT_PER_USER = 3
  MAX_INF_COMMENT_VOTING_COUNT_PER_USER = 5
  HUNT_VOTING_WEIGHT_UNIT = 10
  COMMENT_VOTING_WEIGHT_UNIT = 1

  def do_vote(author, permlink, weight, logger)
    tx = Radiator::Transaction.new(wif: ENV['STEEMHUNT_POSTING_KEY'])
    vote = {
      type: :vote,
      voter: 'steemhunt',
      author: author,
      permlink: permlink,
      weight: (weight * 100).to_i
    }
    tx.operations << vote
    begin
      with_retry(3) do
        tx.process(!TEST_MODE)
      end
    rescue => e
      logger.log "FAILED VOTING: @#{author}/#{permlink} / weight: #{weight}"
    end
  end

  def do_comment(author, permlink, logger)
    msg = "### Congratulations!\n" +
      "We have upvoted your post for your contribution within our community.\n" +
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
      logger.log "FAILED COMMENT: @#{author}/#{permlink}"
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

  def voting_weight_for(type, username, weight_per_unit)
    user = User.find_by(username: username)
    return 0 if user.admin?

    unit = case type
      when :hunt
        HUNT_VOTING_WEIGHT_UNIT * user.level
      when :comment
        COMMENT_VOTING_WEIGHT_UNIT * user.level
      else
        0
      end

    weight = unit * weight_per_unit
    weight = 100 if weight > 100

    [weight.round(2), user.level]
  end


  # MARK: - Votinbot Begin

  logger = SLogger.new('voting-log')

  if POWER_TOTAL_POST < 0
    logger.log "Less than 80% voting power left, STOP voting bot"
    next
  end

  api = Radiator::Api.new
  today = Time.zone.today.to_time + 1.day
  yesterday = (today - 1.day).to_time

  logger.log "\n==========\nVOTING STARTS with #{(POWER_TOTAL_POST).round(2)}% TOTAL VP - #{formatted_date(yesterday)}", true
  logger.log "Current voting power: #{current_voting_power(api)}%"
  posts = Post.where('listed_at >= ? AND listed_at < ?', yesterday, today).
               order(hunt_score: :desc, payout_value: :desc, created_at: :desc).to_a
  logger.log "Total #{posts.size} posts found on #{formatted_date(yesterday)}\n==========", true

  posts_to_skip = [] # posts that should skip votings, but need to be counted for VP
  posts_to_remove = [] # posts that should be removed from the ranking entirely (not counted for VP)

  comments_to_vote = { # comments that should be voted
    normal: [],
    normal_count: 0,
    influencers: [],
    influencers_count: 0,
    moderators: [],
    moderators_count: 0,
    author_count: {},
    sh_count: 0,
    all_count: 0
  }

  post_added = {}
  verified_and_active_count = 0
  posts.each_with_index do |post, i|
    logger.log "@#{post.author}/#{post.permlink}"

    unless post.is_verified
      posts_to_remove << post.id
      post.update! listed_at: today unless TEST_MODE # roll over to the next date
      logger.log "--> REMOVE: Not yet verified / SKIP checking comments"
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

      verified_and_active_count += 1

      user = User.find_by(username: post.author)

      if user.blacklist?
        posts_to_remove << post.id
        logger.log "--> REMOVE_BLACKLIST: still checks comments for voting"
      elsif user.level == 0
        posts_to_remove << post.id
        logger.log "--> REMOVE_LEVEL_0: still checks comments for voting"
      elsif votes.any? { |v| v['voter'] == 'steemhunt' }
        posts_to_skip << post.id
        logger.log "--> SKIP: Already voted"
      elsif post_added[post.author].to_i >= MAX_HUNT_VOTING_COUNT_PER_USER
        posts_to_remove << post.id
        logger.log "--> REMOVE: More than #{MAX_HUNT_VOTING_COUNT_PER_USER} hunt by @#{post.author}, still checks comments for voting"
      else
        post_added[post.author] ||= 0
        post_added[post.author] += 1
      end
    else
      posts_to_remove << post.id
      logger.log "--> DE-LISTED: still checks comments for voting"
    end

    comments = with_retry(3) do
      api.get_content_replies(post.author, post.permlink)['result']
    end
    # logger.log "----> #{comments.size} comments returned"

    # duplication checks for each posts
    mod_comment_added = {}
    inf_comment_added = {}
    normal_comment_added = {}
    comments.each do |comment|
      json_metadata = JSON.parse(comment['json_metadata']) rescue {}
      json_metadata = {} unless json_metadata.is_a?(Hash) # Handle invalid json_metadata format

      comments_to_vote[:all_count] += 1

      comment_author = User.find_by(username: comment['author'])
      next if comment_author.nil?

      comments_to_vote[:sh_count] += 1

      # Filter level 0
      if comment_author.level == 0
        logger.log "--> REMOVE LEVEL_0_COMMENTS: #{comment['author']}"
        next
      end

      # Check already voted
      should_skip = comment_already_voted?(comment, api)
      comments_to_vote[:author_count][comment['author']] ||= 0 # initialize

      # 1. Moderator comments
      if json_metadata['verified_by'] == comment['author'] && User::MODERATOR_ACCOUNTS.include?(comment['author'])
        comments_to_vote[:moderators_count] += 1

        if mod_comment_added[comment['author']]
          logger.log "--> REMOVE DUPLICATED_MOD_COMMENT: @#{comment['author']}"
          next
        end

        comments_to_vote[:moderators].push({ author: comment['author'], permlink: comment['permlink'], should_skip: should_skip })
        mod_comment_added[comment['author']] = true # for dup check
        comments_to_vote[:author_count][comment['author']] += 1
        logger.log "--> #{should_skip ? 'SKIP ALREADY_VOTED' : 'ADDED'} MOD comment: @#{comment['author']}"

      # 2. Influencer comments
      elsif User::INFLUENCER_ACCOUNTS.include?(comment['author'])
        comments_to_vote[:influencers_count] += 1

        if inf_comment_added[comment['author']]
          logger.log "--> REMOVE DUPLICATED_INF_COMMENT: @#{comment['author']}"
          next
        end

        if comments_to_vote[:author_count][comment['author']] >= MAX_INF_COMMENT_VOTING_COUNT_PER_USER
          logger.log "--> MAX MAX_COMMENT_VOTING_COUNT_PER_USER REACHED: @#{comment['author']}"
          next
        end

        comments_to_vote[:influencers].push({ author: comment['author'], permlink: comment['permlink'], should_skip: should_skip })
        inf_comment_added[comment['author']] = true # for dup check
        comments_to_vote[:author_count][comment['author']] += 1 # for max votings
        logger.log "--> #{should_skip ? 'SKIP ALREADY_VOTED' : 'ADDED'} INF comment: @#{comment['author']}"

      # 3. Other SH comments
      elsif comment['body'].size > 80
        comments_to_vote[:normal_count] += 1

        if comment['author'] == post.author
          logger.log "--> REMOVE SELF_REVIEW_COMMENT: @#{comment['author']}"
          next
        end

        if normal_comment_added[comment['author']]
          logger.log "--> REMOVE DUPLICATED_REVIEW_COMMENT: @#{comment['author']}"
          next
        end

        if !comment_author.dau_yesterday?
          logger.log "--> REMOVE NOT_DAU: @#{comment['author']}"
          next
        end

        # DEPRECATED after ABV 2.0
        # if !votes.any? { |v| v['voter'] == comment['author'] && v['percent'] >= 3000 }
        #   logger.log "--> REMOVE NOT_VOTED_REVIEW_COMMENT: @#{comment['author']}"
        #   next
        # end

        if comment_author.try(:blacklist?)
          logger.log "--> REMOVE_BLACKLIST: @#{comment['author']}"
          next
        end

        if comments_to_vote[:author_count][comment['author']] >= MAX_COMMENT_VOTING_COUNT_PER_USER
          logger.log "--> MAX MAX_COMMENT_VOTING_COUNT_PER_USER REACHED: @#{comment['author']}"
          next
        end

        comments_to_vote[:normal].push({ author: comment['author'], permlink: comment['permlink'], should_skip: should_skip })
        normal_comment_added[comment['author']] = true # for dup check
        comments_to_vote[:author_count][comment['author']] += 1 # for max votings
        logger.log "--> #{should_skip ? 'SKIP ALREADY_VOTED' : 'ADDED'} Normal comment: @#{comment['author']}"
      end
    end # comments.each
  end # posts.each

  original_post_size = posts.size
  posts = posts.reject { |post| posts_to_remove.include?(post.id) }
  total_reward = posts.reduce(0) { |s, p| s + p.payout_value }

  valid_posts_size = posts.size
  # valid_comments_size = comments_to_vote[:normal].size

  logger.log "\n==========\nSelect first #{MAX_TOTAL_HUNT_VOTING_COUNT} / #{posts.size} posts for voting\n==========", true
  posts = post.first(MAX_TOTAL_HUNT_VOTING_COUNT)

  # Calculates the total voting weight unit for actual voting weights
  weighted_voting_unit_total = 0
  posts.each do |post|
    weighted_voting_unit_total += voting_weight_for(:hunt, post.author, 1)[0]
  end
  comments_to_vote[:author_count].each do |username, count|
    weighted_voting_unit_total += voting_weight_for(:comment, username, 1)[0] *
      (count > MAX_COMMENT_VOTING_COUNT_PER_USER ? MAX_COMMENT_VOTING_COUNT_PER_USER : count) # Limit for mods, inf comments
  end

  weight_per_unit = ((POWER_TOTAL_POST -
    POWER_ADDED_PER_MOD_COMMENT * comments_to_vote[:moderators].size -
    POWER_ADDED_PER_INF_COMMENT * comments_to_vote[:influencers].size) /
    weighted_voting_unit_total)

  logger.log "\n==========\nTotal #{original_post_size} posts -> #{verified_and_active_count} verified and active -> #{posts.size} valid for voting\n"
  logger.log "Total reward (active): $#{total_reward.round(2)} SBD -> \n"
  logger.log "Commnets: #{comments_to_vote[:all_count]} in total / #{comments_to_vote[:sh_count]} on SH"
  logger.log " - Mods: #{comments_to_vote[:moderators_count]} in total -> #{comments_to_vote[:moderators].size} valid for voting"
  logger.log " - Infs: #{comments_to_vote[:influencers_count]} in total -> #{comments_to_vote[:influencers].size} valid for voting"
  logger.log " - Normal: #{comments_to_vote[:normal_count]} in total -> #{comments_to_vote[:normal].size} valid for voting"
  logger.log "\nVoting start with #{POWER_TOTAL_POST.round(2)}% VP in total"
  logger.log " - Voting weight per unit: #{weight_per_unit.round(2)}%\n==========", true

  posts.each_with_index do |post, i|
    voting_weight = voting_weight_for(:hunt, post.author, weight_per_unit)

    logger.log "Voting on ##{i + 1} / #{posts.size} (LV. #{voting_weight[1]}, #{voting_weight[0].round(2)}%): @#{post.author}/#{post.permlink}", true
    if posts_to_skip.include?(post.id)
      logger.log "--> SKIPPED_POST (#{i + 1}/#{posts.size})"
    else
      sleep(20) unless TEST_MODE
      res = do_vote(post.author, post.permlink, voting_weight[0], logger)
      # logger.log "--> VOTED_POST: #{res.inspect}"
      res = do_comment(post.author, post.permlink, logger)
      # logger.log "--> COMMENTED: #{res.inspect}", true
    end
  end

  logger.log "\n==========\nVOTING ON #{comments_to_vote[:normal].size} COMMENTS (#{comments_to_vote[:author_count].size} authors)\n==========", true
  comments_to_vote[:normal].each_with_index do |comment, i|
    voting_weight = voting_weight_for(:comment, comment[:author], weight_per_unit)

    logger.log "[#{i + 1} / #{comments_to_vote[:normal].size}] Voting on comment (LV. #{voting_weight[1]}, #{voting_weight[0].round(2)}%): @#{comment[:author]}/#{comment[:permlink]}", true
    if comment[:should_skip]
      logger.log "--> SKIPPED_REVIEW", true
    else
      sleep(3) unless TEST_MODE
      res = do_vote(comment[:author], comment[:permlink], voting_weight[0], logger)
      # logger.log "--> VOTED_REVIEW: #{res.inspect}", true
    end
  end

  logger.log "\n==========\nVOTING ON #{comments_to_vote[:moderators].size} MODERATOR COMMENTS\n==========", true

  mod_voted_count = {}
  comments_to_vote[:moderators].each_with_index do |comment, i|
    # First 5 comments should be voted as `normal voting weight + 0.6%`
    # Others just flat 0.6%
    mod_voted_count[comment[:author]] ||= 0
    level_voting_weight = voting_weight_for(:comment, comment[:author], weight_per_unit)
    voting_weight = if mod_voted_count[comment[:author]] >= MAX_COMMENT_VOTING_COUNT_PER_USER
      POWER_ADDED_PER_MOD_COMMENT
    else
      level_voting_weight[0] + POWER_ADDED_PER_MOD_COMMENT
    end

    logger.log "[#{i + 1} / #{comments_to_vote[:moderators].size}] Voting on MOD comment (LV. #{level_voting_weight[1]}, #{voting_weight.round(2)}%): @#{comment[:author]}/#{comment[:permlink]}", true
    if comment[:should_skip]
      logger.log "--> SKIPPED_MODERATOR", true
    else
      sleep(3) unless TEST_MODE
      res = do_vote(comment[:author], comment[:permlink], voting_weight, logger)
      mod_voted_count[comment[:author]] += 1
      # logger.log "--> VOTED_MODERATOR: #{res.inspect}", true
    end
  end

  logger.log "\n==========\nVOTING ON #{comments_to_vote[:influencers].size} INFLUENCER COMMENTS\n==========", true

  inf_voted_count = {}
  comments_to_vote[:influencers].each_with_index do |comment, i|
    # First 5 comments should be voted as `normal voting weight + 0.5%`
    # Other 5 comments just flat 0.5%
    inf_voted_count[comment[:author]] ||= 0
    level_voting_weight = voting_weight_for(:comment, comment[:author], weight_per_unit)
    voting_weight = if inf_voted_count[comment[:author]] >= MAX_COMMENT_VOTING_COUNT_PER_USER
      POWER_ADDED_PER_INF_COMMENT
    else
      level_voting_weight[0] + POWER_ADDED_PER_INF_COMMENT
    end

    logger.log "[#{i + 1} / #{comments_to_vote[:influencers].size}] Voting on INF comment (LV. #{level_voting_weight[1]}, #{voting_weight.round(2)}%): @#{comment[:author]}/#{comment[:permlink]}", true
    if comment[:should_skip]
      logger.log "--> SKIPPED_INFLUENCER", true
    else
      sleep(3) unless TEST_MODE
      res = do_vote(comment[:author], comment[:permlink], voting_weight, logger)
      inf_voted_count[comment[:author]] += 1
      # logger.log "--> VOTED_INFLUENCER: #{res.inspect}", true
    end
  end

  logger.log "\n==========\nVotings Finished, #{current_voting_power(api)}% VP left\n==========", true
end