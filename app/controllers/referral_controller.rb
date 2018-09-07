class ReferralController < ApplicationController
  def create
    unless user = User.find_by(username: params[:ref])
      render json: { head: :no_content } and return
    end

    type = params[:type].to_i
    referral_type = Referral.referral_types.include?(type) ? type : 0

    referral = user.referrals.build(
      remote_ip: request.remote_ip,
      path: params[:path],
      referral_type: referral_type,
      created_at: DateTime.now
    )

    begin
      referral.save
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    render json: { head: :no_content }
  end
end
