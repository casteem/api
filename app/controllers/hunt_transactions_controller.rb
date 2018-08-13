class HuntTransactionsController < ApplicationController
  before_action :ensure_login!

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
      sp_to_claim: @current_user.sp_to_claim,
      eth_address: @current_user.eth_address,
      transactions: @transactions,
      withdrawals: @withdrawals
    }
  end

  def sp_claim
    sp_to_claim = @current_user.sp_to_claim

    begin
      raise 'Nothing to claim' unless sp_to_claim > 0

      HuntTransaction.claim_sp!(@current_user.username, sp_to_claim)
      t = HuntTransaction.find_by(receiver: @current_user.username, bounty_type: 'sp_claim')

      render json: { success: true, transaction: t }
    rescue => e
      render json: { error: e.message }
    end
  end

  private
    def user_params
      params.require(:user).permit(:username, :token)
    end
end