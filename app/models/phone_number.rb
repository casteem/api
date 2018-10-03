class PhoneNumber < ApplicationRecord
  attr_accessor :notification

  def send_pin
    if abusing? || existing_user?
      false
    else
      update(pin: generate_pin, pin_sent: self.pin_sent + 1, pin_sent_at: Time.now)
      self.pin
    end
  end

  def verify_pin(user_pin)
    if self.pin == user_pin.to_i
      update(verified: true)
    else
      @notification = "Your pin number #{user_pin} is incorrect."
    end

    self.verified
  end

  private

  def generate_pin
    return '1111' if Rails.env.development?
    # production pin generation
  end

  def abusing?
    if self.pin_sent_at && self.pin_sent_at > Time.now - 1.minutes
      @notification = "Pin has been sent within a minute. You can try again in #{60 - (Time.now.to_i - self.pin_sent_at.to_i)} seconds later."
      return true
    end
  end

  def existing_user?
    if false #User.where(phone_number: self.number).any?
      @notification = 'This number is already linked to an existing account, or to an account still under review.'
      return true
    end
  end
end
