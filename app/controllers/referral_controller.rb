class ReferralController < ApplicationController
  def create
    unless user = User.find_by(username: params[:ref])
      render json: { head: :no_content }, status: :not_found and return
    end

    type = params[:type].to_i
    referral_type = Referral.referral_types.include?(type) ? type : 0

    referral = user.referrals.build(
      remote_ip: request.remote_ip,
      path: params[:path],
      referral_type: referral_type
    )

    begin
      referral.save

      render json: { head: :no_content }
    rescue ActiveRecord::RecordNotUnique
      render json: { head: :no_content }, status: :conflict
    end
  end
end
