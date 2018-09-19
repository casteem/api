class ReferralController < ApplicationController
  BOT_UA = /curl|googlebot|bingbot|yandex|baiduspider|twitterbot|facebookexternalhit|rogerbot|linkedinbot|embedly|quora link preview|showyoubot|outbrain|pinterest|slackbot|vkShare|W3C_Validator|developers\.google\.com|Google-Structured-Data-Testing-Tool|redditbot|Discordbot|TelegramBot/i

  def create
    unless user = User.find_by(username: params[:ref])
      render status: :not_found and return # 404
    end

    if request.user_agent =~ BOT_UA
      render status: :not_acceptable and return # 422
    end

    begin
      Referral.create(
        user_id: user.id,
        remote_ip: request.remote_ip,
        path: params[:path],
        referrer: params[:referrer],
        user_agent: request.user_agent
      )

      render status: :ok # 200
    rescue ActiveRecord::RecordNotUnique
      render status: :conflict # 409
    end
  end
end
