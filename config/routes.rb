Spree::Core::Engine.routes.draw do
  post 'mollie',     :to => 'mollie_callbacks#update',  :as => :mollie_callback
  get  'mollie/:id', :to => 'mollie_callbacks#show',    :as => :mollie
end
