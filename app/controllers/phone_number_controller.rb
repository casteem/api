class PhoneNumberController < ApplicationController
  before_action :set_phone_number, only: [:send_sms, :verify_pin]

  def send_sms
    data = {
      pin: @phone.send_pin
    }
    p "Pint Sent :::: #{@phone.pin}"
    render_json(data)
  end

  def verify_pin
    data = {
      verified: @phone.verify_pin(params[:user_pin])
    }

    render_json(data)
  end

  private

  def set_phone_number
    @phone = PhoneNumber.where(number: params[:phone_number]).first_or_create
  end

  def render_json(data)
    if @phone.notification.present?
      data.merge!(notification: @phone.notification)
    end
    render json: data.to_json
  end
end
