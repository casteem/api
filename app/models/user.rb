require 'radiator'
require 's_logger'

class User < ApplicationRecord
  validates_presence_of :username
  validate :validate_eth_format
  has_many :hunt_transactions
  has_many :erc_transactions
  has_many :referrals

  ADMIN_ACCOUNTS = ['steemhunt', 'tabris', 'project7', 'astrocket']
  MODERATOR_ACCOUNTS = [
    'tabris', 'project7',
    'teamhumble', 'urbangladiator', 'dayleeo', 'fknmayhem', 'jayplayco', 'bitrocker2020', 'joannewong',
    'geekgirl', 'playitforward', 'monajam', 'pialejoana'
  ]
  INFLUENCER_ACCOUNTS = [
    'dontstopmenow', 'ogochukwu', 'theversatileguy', 'guyfawkes4-20', 'tobias-g', 'elleok',
    'themanualbot', 'redtravels', 'joythewanderer', 'ady-was-here', 'raulmz', 'chuuuckie', 'shaphir', 'mobi72',
    'fruitdaddy', 'jonsnow1983', 'karamyog', 'josephace135', 'elsiekjay', 'calprut'
  ]
  INFLUENCER_WEIGHT_BOOST = 3.0
  MODERATOR_WEIGHT_BOOST = 2.0
  GUARDIAN_ACCOUNTS = [
    'jayplayco'
  ]

  LEVEL_TIER = [ 1.0, 2.0, 3.0, 5.0, 8.0 ]

  scope :whitelist, -> {
    where('last_logged_in_at >= ?', Time.zone.today.to_time).
    where('cached_user_score >= ?', LEVEL_TIER[0]).
    where('blacklisted_at IS NULL OR blacklisted_at < ?', 1.month.ago)
  }

  @@blacklists = File.read("#{Rails.root}/db/buildawhale_blacklist.txt").split

  def dau?
    last_logged_in_at && last_logged_in_at > Time.zone.today.to_time
  end

  def dau_yesterday?
    last_logged_in_at && last_logged_in_at > Time.zone.yesterday.to_time
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

  def validate_token(token)
    res = User.fetch_with_token(token)

    if res['user'] == self.username
      self.encrypted_token = Digest::SHA256.hexdigest(token)
      self.reputation = User.rep_score(res['account']['reputation'])
      self.vesting_shares = res['account']['vesting_shares'].to_f

      true
    else
      false
    end
  end

  def validate_eth_format
    unless eth_address.blank?
      errors.add(:eth_address, "is incorrect") unless eth_address =~ /^0x[0-9a-f]{40}$/i
    end
  end

  # Fetch user JSON data from SteemConnect
  # Only used when we need to double check current user's token
  def self.fetch_with_token(token)
    retries = 0

    begin
      uri = URI.parse('https://steemconnect.com/api/me')
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

  # def self.fetch_from_public(username)
  #   response = Net::HTTP.get(URI("https://steemit.com/@#{username}.json"))
  #   JSON.parse(response)
  # end

  def sp_to_claim
    exclusion = ['steem', 'steemit', 'steemitblog', 'misterdelegation' ]
    return 0.0 if exclusion.include?(self.username)

    return 0.0 if HuntTransaction.exists?(receiver: self.username, bounty_type: 'sp_claim')

    steem_per_vest = 0.000495

    steem_per_vest * self.vesting_shares
  end

  def log_session(ip_addr)
    # Updata activity_score for login
    today = Time.zone.today.to_time
    yesterday = Time.zone.yesterday.to_time
    if self.last_logged_in_at && self.last_logged_in_at < today
      self.activity_score += 0.1

      if self.last_logged_in_at < yesterday
        self.activity_score -= 0.1 * ((yesterday - self.last_logged_in_at) / 86400).ceil
      end
    end

    # Min / Max : 0.7 - 2.0
    self.activity_score = 0.7 if self.activity_score < 0.7
    self.activity_score = 2.0 if self.activity_score > 2.0

    self.session_count += 1
    self.last_logged_in_at = Time.now
    self.last_ip = ip_addr
  end

  # MARK: - User Score & Voting Weight

  def hunt_score_by(weight)
    return 0 if weight <= 0 # no down-votings
    return 0 unless dau?
    return 0 if blacklist?

    (user_score * weight * 0.01 * boost_score).to_f
  end

  def level
    if user_score >= LEVEL_TIER[4]
      5
    elsif user_score >= LEVEL_TIER[3]
      4
    elsif user_score >= LEVEL_TIER[2]
      3
    elsif user_score >= LEVEL_TIER[1]
      2
    elsif user_score >= LEVEL_TIER[0] || moderator? # minimum level is 1 for mod votings
      1
    else
      0
    end
  end

  def user_score(force = false, debug = false)
    if blacklist?
      puts "Blacklist" if debug
      return 0.0
    end

    if self.username == 'steemhunt'
      puts "Steemhunt" if debug
      return 0.0
    end

    return cached_user_score if cached_user_score >= 0 && user_score_updated_at && user_score_updated_at > 4.hours.ago && !force

    score = credibility_score(debug) *  activity_score * curation_score(debug) * hunter_score(debug)

    puts "#{credibility_score.round(2)} * #{activity_score.round(2)} * #{curation_score.round(2)} * #{hunter_score.round(2)} = #{score.round(2)}" if debug

    self.cached_user_score = score
    self.user_score_updated_at = Time.now
    self.save!

    score.round(2)
  end

  # Voting Weight = User Score
  alias voting_weight user_score

  # 1. Account Credibility
  def external_blacklist?
    @@blacklists.include?(self.username)
  end

  def credibility_score(debug = false)
    score = (self.reputation - 35) * 0.12
    score = 3.0 if score > 3.0
    score = 0.0 if score < 0
    puts "Reputation: #{self.reputation} - Score: #{score}" if debug

    if self.created_at > 1.week.ago
      score *= 0.6
    elsif self.created_at > 1.month.ago
      score *= 0.8
    end
    puts "Age check: #{score} - #{(Time.now - self.created_at).round / 86400} days" if debug

    if external_blacklist?
      score *= 0.3
      puts "External blacklists: #{score.round(2)}" if debug
    end

    # TODO: FB login
    # TODO: Steem-UA

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
      logger.log "@#{username} --> No diff (DS: #{ds.round(2)} / Jerk Count: #{jerk_score})"
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
      weighted_receiver_count += (weighted_counts[id].to_f / count.to_f)
      total_weighted += weighted_counts[id]
    end

    ds = weighted_receiver_count / total_weighted.to_f
    ds = 1.0 if ds.nan?

    score = 1.0
    score *= ds * 2 if ds < 0.5 # only penalty if ds < 0.5
    puts "Curation Score : #{score.round(2)} (DS: #{ds.round(2)})" if debug

    if voting_count < 40
      # Disadvantage if not enough voting data (min 0.6)
      score *= (voting_count + 60) / 100.0
      puts "DS not enough data: #{score.round(2)}" if debug
    end

    # Active curator advantage
    active_score = 1.0 + (total_voted_weight / 20000000.0)
    active_score = 4.0 if active_score > 4
    score *= active_score
    puts "Active Curation Advantage: #{score.round(2)}" if debug

    # Circle voting penalty
    if self.circle_vote_count > 20
      score *= (20.0 / self.circle_vote_count)
    end
    puts "Circle Voting: #{score.round(2)} (JS: #{self.circle_vote_count})" if debug

    score
  end

  # 3. Hunter Score
  def hunter_score(debug = false)
    all_average = Post.for_a_month.active.average(:hunt_score) || 0.0
    my_average = Post.where(author: username).for_a_month.active.average(:hunt_score) || 0.0
    my_count = Post.where(author: username).for_a_month.group(:is_active).count
    all_count = my_count.values.sum


    if my_count[true].nil? || my_count[true] < 3
      if moderator? # Neutral if mods & team
        puts "Hunt Score: 1.0 - Mod" if debug
        return 1.0
      else
        puts "Hunt Score: 0.8 - Not enough data" if debug
        return 0.8
      end
    end

    score = my_average.to_f / all_average
    score = 1.5 if score > 1.5
    puts "Hunt Score: #{score.round(2)}" if debug

    score *= my_count[true] / all_count.to_f # Disadvantage with review pass rate
    puts "Review disadvantage: #{score.round(2)}" if debug

    score
  end

  # 4. Boost Score (Not affected on level)
  def boost_score
    if influencer?
      INFLUENCER_WEIGHT_BOOST
    elsif moderator?
      MODERATOR_WEIGHT_BOOST
    else
      1.0
    end
  end
end
