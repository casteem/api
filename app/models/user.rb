require 'radiator'
require 's_logger'

class User < ApplicationRecord
  validates_presence_of :username
  validate :validate_eth_format
  has_many :hunt_transactions

  ADMIN_ACCOUNTS = ['steemhunt', 'tabris', 'project7']
  MODERATOR_ACCOUNTS = [
    'tabris', 'project7',
    'teamhumble', 'folken', 'urbangladiator', 'chronocrypto', 'dayleeo', 'fknmayhem', 'jayplayco', 'bitrocker2020', 'joannewong',
    'geekgirl', 'playitforward'
  ]
  INFLUENCER_ACCOUNTS = [
    'dontstopmenow', 'sambillingham', 'ogochukwu', 'theversatileguy', 'guyfawkes4-20', 'pialejoana', 'tobias-g', 'superoo7',
    'themanualbot', 'redtravels', 'elleok', 'joythewanderer', 'ady-was-here', 'raulmz', 'chuuuckie', 'shaphir', 'mobi72'
  ]
  INFLUENCER_WEIGHT_BOOST = 5
  GUARDIAN_ACCOUNTS = [
    'folken', 'fknmayhem'
  ]

  scope :whitelist, -> {
    where('last_logged_in_at >= ?', Time.zone.today.to_time).
    where.not(encrypted_token: '').where('reputation >= ?', 35).
    where('blacklisted_at IS NULL OR blacklisted_at < ?', 1.month.ago)
  }

  def dau?
    last_logged_in_at > Time.zone.today.to_time
  end

  def dau_yesterday?
    last_logged_in_at > Time.zone.yesterday.to_time
  end

  def blacklist?
    !blacklisted_at.nil? && blacklisted_at > 1.month.ago
  end

  def admin?
    ADMIN_ACCOUNTS.include?(username)
  end

  def moderator?
    MODERATOR_ACCOUNTS.include?(username)
  end

  def influencer?
    INFLUENCER_ACCOUNTS.include?(username)
  end

  def guardian?
    GUARDIAN_ACCOUNTS.include?(username)
  end

  # Ported from steem.js
  # Basic rule: ((Math.log10(raw_score) - 9) * 9 + 25).floor
  def self.rep_score(raw_score)
    return 0 if raw_score.to_i == 0

    raw_score = raw_score.to_i
    neg = raw_score < 0 ? -1 : 1
    raw_score = raw_score.abs
    leading_digits = raw_score.to_s[0..3]
    log = Math.log10(leading_digits.to_i)
    n = raw_score.to_s.length - 1
    out = n + log - log.to_i
    out = 0 if out.nan?
    out = [out - 9, 0].max
    out = neg * out * 9 + 25

    out.to_i
  end

  def validate!(token)
    res = User.fetch_data(token)

    if res['user'] == self.username
      self.update!(
        encrypted_token: Digest::SHA256.hexdigest(token),
        reputation: User.rep_score(res['account']['reputation']),
        vesting_shares: res['account']['vesting_shares'].to_f
      )

      true
    else
      false
    end
  end

  def validate_eth_format
    unless eth_address.blank?
      errors.add(:eth_address, "Wrong format") if eth_address.size != 42 || !eth_address.downcase.start_with?('0x')
    end
  end

  # Fetch user JSON data from SteemConnect
  # Only used when we need to double check current user's token
  def self.fetch_data(token)
    retries = 0

    begin
      uri = URI.parse('https://v2.steemconnect.com/api/me')
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true
      header = {
        'Content-Type' =>'application/json',
        'Authorization' => token
      }
      req = Net::HTTP::Post.new(uri.path, header)
      res = https.request(req)
      body = JSON.parse(res.body)

      raise res.body if body['user'].blank?

      body
    rescue => e
      retry if (retries += 1) < 3

      { error: e.message }
    end
  end


  # MARK: - User Score & Voting Weight

  def hunt_score_by(weight)
    return 0 if weight <= 0 # no down-votings
    return 0 unless dau?
    return 0 if blacklist?

    voting_weight * weight * 0.01
  end

  def user_score(force = false, debug = false)
    return cached_user_score if cached_user_score >= 0 && user_score_updated_at && user_score_updated_at > 24.hours.ago && !force

    score = credibility_score(debug) *  curation_score(debug) * hunt_score(debug) * boost_score(debug)

    self.cached_user_score = score
    self.user_score_updated_at = Time.now
    self.save!

    self.cached_user_score
  end

  # Voting Weight = User Score
  alias voting_weight user_score

  # 1. Account Credibility
  def credibility_score(debug = false)
    score = if reputation >= 60
      3.0
    elsif reputation >= 55
      2.0
    elsif reputation >= 45
      1.0
    elsif reputation >= 35
      0.5
    else
      0
    end
    puts "Reputation: #{score}" if debug

    if created_at > 1.month.ago
      score *= 0.5
    end
    puts "Age check: #{score} - #{(Time.now - created_at).round / 86400} days" if debug

    # TODO: follower count
    # TODO: Steemit post, comment count
    # TODO: FB login

    score
  end

  # 2. Curation Score
  def votee
    Post.from('posts, json_array_elements(posts.valid_votes) v').for_a_month.
      where("v->>'voter' = ?", username).group(:author).count
  end

  def votee_weighted
    Post.from('posts, json_array_elements(posts.valid_votes) v').for_a_month.
      where("v->>'voter' = ?", username).group(:author).sum("(v#>>'{percent}')::integer")
  end

  def total_voted_weight
    Post.from('posts, json_array_elements(posts.valid_votes) v').for_a_month.
      where("v->>'voter' = ?", username).sum("(v#>>'{weight}')::integer")
  end

  def detect_circle(chain = false, logger = nil)
    logger = PLogger.new unless logger

    lists =  User.find_by(username: username).votee.sort_by {|k,v| v}.reverse

    circle = {}
    jerk_score = 0
    lists.first(10).each do |u|
      other_list =  User.find_by(username: u[0]).votee
      if other_list[username] && other_list[username] >= 2
        circle[u[0]] = { sent: u[1], received: other_list[username] }
        jerk_score += [u[1], other_list[username]].min
      end
    end

    old_ds = self.user_score
    self.circle_vote_count = jerk_score
    ds = self.user_score(true, true)

    if (old_ds - ds).abs > 0.0001
      logger.log "@#{username} --> DS: #{old_ds} -> #{ds}"
      logger.log " - Circle: #{circle}"
      logger.log " - Jerk Score: #{jerk_score}"
      chain = true if chain == :optional
    else
      logger.log "@#{username} --> No diff (DS: #{ds} / Jerk Count: #{jerk_score}"
      chain = false if chain == :optional
    end

    if chain
      circle.each do |k, hash|
        if hash[:sent] > 3 || hash[:received] > 3
          User.find_by(username: k).detect_circle(false, logger)
        end
      end
    end
  end

  def curation_score(debug = false)
    counts = votee
    weighted_counts = votee_weighted

    voting_count = 0
    total_weighted = 0
    weighted_receiver_count = 0
    counts.each do |id, count|
      voting_count += count
      weighted_receiver_count += (weighted_counts[id] / count.to_f)
      total_weighted += weighted_counts[id]
    end

    score = weighted_receiver_count / total_weighted.to_f
    puts "DS initial: #{score}" if debug

    if score.nan?
      # Default 1.0
      score = 1.0
    elsif score < 0.4
      # Lower the lower
      score *= 0.5
    end
    puts "DS low: #{score}" if debug

    # Not enough votings for DS calculation
    if voting_count < 10
      score *= 0.4
    elsif voting_count < 30
      score *= 0.6
    elsif voting_count < 50
      score *= 0.8
    end
    puts "DS not enough data: #{score}" if debug

    # Circle voting penalty
    if self.circle_vote_count >= 50
      score *= 0.01
    elsif self.circle_vote_count >= 40
      score *= 0.05
    elsif self.circle_vote_count >= 30
      score *= 0.1
    elsif self.circle_vote_count >= 20
      score *= 0.15
    elsif self.circle_vote_count >= 10
      score *= 0.25
    elsif self.circle_vote_count >= 5
      score *= 0.5
    end
    puts "Circle Voting: #{score} (JS: #{self.circle_vote_count})" if debug

    # Active curator advantage
    active_score = total_voted_weight / 10000000.0
    score *= active_score > 5 ? 5 : active_score if active_score > 1
    puts "Active Curation Advantage: #{score}" if debug

    score
  end

  # 3. Hunt Score
  def hunt_score(debug = false)
    all_average = Post.for_a_month.active.average(:hunt_score) || 0.0
    my_average = Post.where(author: username).for_a_month.active.average(:hunt_score) || 0.0
    my_count = Post.where(author: username).for_a_month.active.count

    return 1.0 if moderator? # Do not cacluate hunt_score for mods & team
    return 0.5 if my_average == 0 # No hunt for a month

    score = if my_count < 3
      1.0
    else
      my_average / all_average
    end
    puts "Hunt Score: #{score}" if debug

    score
  end

  # 4. Boost Score
  def boost_score(debug = false)
    score = influencer? ? INFLUENCER_WEIGHT_BOOST : 1.0
    puts "Boost: #{score}" if debug

    score
  end
end
