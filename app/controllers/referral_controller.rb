class ReferralController < ApplicationController
  def create
    unless user = User.find_by(username: params[:ref])
      render json: { head: :no_content }
    end
    type = (params[:type] || 0).to_i
    referral_type = Referral.referral_types.include?(type) ? type : 0

    referral = user.referrals.build(
      remote_ip: request.remote_ip,
      path: params[:path],
      referral_type: referral_type
    )
    if referral.save
      render json: { head: :no_content }
    else
      render json: { head: :no_content }
    end
  end
end
