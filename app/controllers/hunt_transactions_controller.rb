class HuntTransactionsController < ApplicationController
  before_action :ensure_login!, except: [:stats, :extensions]

  # GET /hunt_transactions.json
  def index
    @transactions = HuntTransaction.
      where('sender = ? OR receiver = ?', @current_user.username, @current_user.username).
      order(created_at: :desc).
      limit(500)

    @withdrawals = ErcTransaction.
      where(user_id: @current_user.id).
      order(created_at: :desc).
      limit(500)

    render json: {
      balance: @current_user.hunt_balance,
      eth_address: @current_user.eth_address,
      transactions: @transactions,
      withdrawals: @withdrawals
    }
  end

  def stats
    now = Time.zone.now
    sum = Rails.cache.fetch('transaction-stats', expires_in: 10.minutes) do
      {
        record_time: now.strftime("%B #{now.day.ordinalize}, %Y"),
        airdrops: HuntTransaction.group(:bounty_type).sum(:amount)
      }
    end

    airdrops = {
      sp_holders: {
        label: "SP Holders (Completed)", data: sum[:airdrops]['sp_claim'].to_f, disabled: true
      },
      sponsors: {
        label: "Sponsors", data: sum[:airdrops]['sponsor'].to_f, disabled: false
      },
      promotion_contributors: {
        label: "Promotion Contributors", data: sum[:airdrops]['contribution'].to_f, disabled: false
      },
      hunt_post_voters: {
        label: "Hunt Post Voters", data: sum[:airdrops]['voting'].to_f, disabled: false
      },
      role_contributors: {
        label: "Role Contributors", data: (sum[:airdrops]['report'] + sum[:airdrops]['moderator'] + sum[:airdrops]['guardian']).to_f, disabled: false
      },
      social_shares: {
        label: "Social Shares", data: sum[:airdrops]['social_share'].to_f, disabled: false
      },
      participants: {
        label: 'Daily Activity Participants', data: (sum[:airdrops]['daily_shuffle'] + sum[:airdrops]['browser_extension']).to_f, disabled: false
      },
      resteemers: {
        label: "Resteemers (Discontinued)", data: sum[:airdrops]['resteem'].to_f, disabled: true
      }
    }

    render json: {
      record_time: sum[:record_time],
      total: sum[:airdrops].values.sum.to_f,
      days_passed: (now.to_date - "2018-05-22".to_date).to_i,
      airdrops: Hash[airdrops.sort_by {|k, v| v[:data] }.reverse]
    }
  end

  # POST /hunt_transactions/daily_shuffle.json
  def daily_shuffle
    amount = if rand(1000) == 0
      1000 # 0.1% chance for 1,000 jackpot
    else
      (1..10).to_a.map { |x| x * 10 }.sample # average 55.0 * 4 = 220 per user per day
    end

    begin
      HuntTransaction.reward_daily_shuffle!(@current_user.username, amount, Time.zone.today, Time.zone.now)
      render json: { amount: amount }
    rescue => e
      render json: { amount: 0 }
    end
  end

  # POST /hunt_transactions/extensions.json
  def extensions
    user = User.find_by(username: params[:username])

    if user
      begin
        HuntTransaction.reward_browser_extension!(user.username, Time.zone.today)
        render json: { result: 'ok' }
      rescue => e
        render json: { result: 'already given' }
      end
    else
      render json: { error: 'USER_NOT_FOUND' }
    end
  end

  private
    def user_params
      params.require(:user).permit(:username, :token)
    end
end