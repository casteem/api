class PhoneNumberController < ApplicationController
  before_action :set_phone_number, only: [:send_sms, :verify]

  def send_sms
    @phone.send_pin

    p "Pint Sent :::: #{@phone.pin}"
    render json: {
      pin: @phone.pin
    }
  end

  def verify
    @phone.verify(params[:user_pin])

    render json: {
      verified: @phone.verified
    }
  end

  private

  def set_phone_number
    @phone = PhoneNumber.first_or_create(number: params[:phone_number])
  end
end
