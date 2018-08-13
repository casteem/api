class UsersController < ApplicationController
  before_action :ensure_login!, only: [:set_eth_address]

  # Create or Update user's encrypted_token
  # POST /users.json
  def create
    if @user = User.find_by(username: user_params[:username])
      unless @user.validate!(user_params[:token])
        render json: { error: 'UNAUTHORIZED' }, status: :unauthorized and return
      end
    else
      @user = User.new(
        username: user_params[:username],
        encrypted_token: Digest::SHA256.hexdigest(user_params[:token])
      )
    end

    @user.log_session(request.remote_ip)

    if @user.save
      render json: @user.as_json(
        only: [:username, :created_at, :blacklisted_at],
        methods: [:level, :user_score, :boost_score]
      ), status: :ok
    else
      render json: { error: @user.errors.full_messages.first }, status: :unprocessable_entity
    end
  end

  def set_eth_address
    unless @current_user.eth_address.nil?
      render json: { error: 'You have already linked you Ethereum address.' } and return
    end

    if @current_user.update(eth_address: params[:eth_address])
      render json: { result: 'OK', eth_address: @current_user.eth_address }
    else
      render json: { error: 'The Ethereum address you entered is invalid. Please check it again.' }
    end
  end

  private
    def user_params
      params.require(:user).permit(:username, :token)
    end
end