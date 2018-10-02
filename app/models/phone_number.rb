class PhoneNumber < ApplicationRecord
  def send_pin
    update(pin: generate_pin)
    return self.pin
  end

  def verify_pin(user_pin)
    if self.pin == user_pin.to_i
      update(verified: true, pin_sent: self.pin_sent + 1)
    end
  end

  private

  def generate_pin
    return '1111' if Rails.env.development?
    # production pin generation
  end
end
