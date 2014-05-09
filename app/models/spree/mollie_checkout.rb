module Spree
  class MollieCheckout < ActiveRecord::Base
    has_many :payments, :as => :source
  end
end
