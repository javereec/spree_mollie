module Spree
  class MollieCheckout < ActiveRecord::Base
    has_many :payments, :as => :source

    def actions
      %w{capture void}
    end

    def can_capture?(payment)
      ['checkout', 'pending'].include?(payment.state)
    end

    def can_void?(payment)
      payment.state != 'void'
    end
  end
end
