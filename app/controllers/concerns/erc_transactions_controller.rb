class ErcTransactionsController < ApplicationController
  before_action :ensure_login!

  # Post /erc_transactions.json
  def create
    # TODO: After launch
    render json: { error: 'Not yet supported' }

    # @erc_transaction = ErcTransaction.new(
    #   user_id: @current_user.id,
    #   amount: params[:amount]
    # )

    # if @erc_transaction.save
    #   render json: { success: true, balance: @current_user.reload.hunt_balance, withdrawal: @erc_transaction }
    # else
    #   render json: { error: @erc_transaction.errors.values.first }
    # end
  end
end